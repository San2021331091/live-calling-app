import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:voxa/model/call_model.dart';
import 'package:voxa/services/incoming_call_ringtone.dart';
import 'package:voxa/services/webrtc_call_session.dart';

class WebRtcCallScreen extends StatefulWidget {
  const WebRtcCallScreen({
    super.key,
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
    required this.media,
    required this.isIncoming,
    this.groupParticipants = const [],
  });

  final String callId;
  final String peerId;
  final String peerName;
  final String peerAvatar;
  final CallMedia media;
  final bool isIncoming;
  final List<GroupCallParticipant> groupParticipants;

  @override
  State<WebRtcCallScreen> createState() => _WebRtcCallScreenState();
}

class _WebRtcCallScreenState extends State<WebRtcCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _groupRemoteRenderers = {};
  final Map<String, WebRtcCallSession> _groupSessions = {};
  WebRtcCallSession? _session;
  MediaStream? _sharedLocalStream;
  String _status = 'Starting call...';
  String? _error;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;
  bool _ending = false;

  bool get _isGroupCall => widget.groupParticipants.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.isIncoming) {
      _initializeCall();
    } else {
      _startOutgoingCall();
    }
  }

  Future<void> _startOutgoingCall() async {
    try {
      await CallRingtone.instance.startOutgoing();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'outgoing call ringtone',
          context: ErrorDescription('while starting the outgoing call sound'),
        ),
      );
    }
    if (!mounted) {
      await _stopOutgoingRingtone();
      return;
    }
    await _initializeCall();
  }

  Future<void> _stopOutgoingRingtone() async {
    try {
      await CallRingtone.instance.stopOutgoing();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'outgoing call ringtone',
          context: ErrorDescription('while stopping the outgoing call sound'),
        ),
      );
    }
  }

  Future<void> _initializeCall() async {
    try {
      if (_isGroupCall) {
        final stream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': widget.media == CallMedia.video
              ? {'facingMode': 'user'}
              : false,
        });
        _sharedLocalStream = stream;
        await _localRenderer.initialize();
        _localRenderer.srcObject = stream;
        for (final participant in widget.groupParticipants) {
          final renderer = RTCVideoRenderer();
          await renderer.initialize();
          _groupRemoteRenderers[participant.peerId] = renderer;
          final session = WebRtcCallSession(
            callId: participant.callId,
            peerId: participant.peerId,
            media: widget.media,
            isIncoming: false,
            externalLocalStream: stream,
            onStatusChanged: (status) {
              if (status == 'Connecting...' || status == 'Connected') {
                unawaited(_stopOutgoingRingtone());
              }
              if (mounted) {
                setState(
                  () => _status =
                      'Connected to ${_groupSessions.length} participants',
                );
              }
            },
            onRemoteStream: (remoteStream) {
              if (!mounted) return;
              final renderer = _groupRemoteRenderers[participant.peerId];
              if (renderer == null) return;
              renderer.srcObject = remoteStream;
              setState(() {});
            },
            onError: (error) {
              unawaited(_stopOutgoingRingtone());
              if (mounted) setState(() => _error = error);
            },
          );
          _groupSessions[participant.peerId] = session;
          await session.start();
        }
        if (mounted) setState(() {});
        return;
      }

      final session = WebRtcCallSession(
        callId: widget.callId,
        peerId: widget.peerId,
        media: widget.media,
        isIncoming: widget.isIncoming,
        onStatusChanged: (status) {
          if (!widget.isIncoming &&
              status != 'Calling...' &&
              status != 'Ringing...') {
            unawaited(_stopOutgoingRingtone());
          }
          if (mounted) setState(() => _status = status);
        },
        onRemoteStream: (stream) {
          _remoteRenderer.srcObject = stream;
          if (mounted) setState(() {});
        },
        onError: (error) {
          unawaited(_stopOutgoingRingtone());
          if (mounted) setState(() => _error = error);
        },
      );
      _session = session;
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      await session.start();
      _localRenderer.srcObject = session.localStream;
      if (mounted) setState(() {});
    } catch (error) {
      await _stopOutgoingRingtone();
      var statusError = '';
      try {
        await _session?.close(notifyPeer: true);
        for (final session in _groupSessions.values) {
          await session.close(notifyPeer: true);
        }
      } catch (closeError) {
        statusError = ' The server could not be notified: $closeError';
        await _session?.close();
        for (final session in _groupSessions.values) {
          await session.close();
        }
      }
      if (mounted) {
        setState(() {
          _error = 'Could not start the call: $error$statusError';
          _status = 'Call unavailable';
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_stopOutgoingRingtone());
    _session?.close();
    for (final session in _groupSessions.values) {
      session.close();
    }
    _sharedLocalStream?.dispose();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    for (final renderer in _groupRemoteRenderers.values) {
      renderer.srcObject = null;
      renderer.dispose();
    }
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _hangUp() async {
    if (_ending) return;
    setState(() => _ending = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await _stopOutgoingRingtone();
    try {
      await _session?.close(notifyPeer: true);
      for (final session in _groupSessions.values) {
        await session.close(notifyPeer: true);
      }
      if (mounted) navigator.pop();
    } catch (error) {
      await _session?.close();
      for (final session in _groupSessions.values) {
        await session.close();
      }
      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Call ended locally, but the server could not be notified: $error',
            ),
          ),
        );
      }
    }
  }

  Future<void> _toggleMicrophone() async {
    final enabled = !_microphoneEnabled;
    if (_isGroupCall) {
      for (final session in _groupSessions.values) {
        session.setMicrophoneEnabled(enabled);
      }
    } else {
      _session?.setMicrophoneEnabled(enabled);
    }
    setState(() => _microphoneEnabled = enabled);
  }

  Future<void> _toggleCamera() async {
    final enabled = !_cameraEnabled;
    if (_isGroupCall) {
      for (final session in _groupSessions.values) {
        session.setCameraEnabled(enabled);
      }
    } else {
      _session?.setCameraEnabled(enabled);
    }
    setState(() => _cameraEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.media == CallMedia.video;
    final remoteView = _buildRemoteView();
    final label = _isGroupCall
        ? '${widget.groupParticipants.length} participants'
        : widget.peerName;
    return Scaffold(
      backgroundColor: const Color(0xff102c2b),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (remoteView != null) remoteView else _audioBackdrop(),
            if (isVideo && _localRenderer.srcObject != null)
              Positioned(
                right: 18,
                top: 18,
                width: 120,
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            Positioned(
              top: 32,
              left: 24,
              right: 24,
              child: Column(
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ?? _status,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 34,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _control(
                    _microphoneEnabled ? Icons.mic : Icons.mic_off,
                    _microphoneEnabled ? 'Mute' : 'Unmute',
                    _toggleMicrophone,
                  ),
                  if (isVideo)
                    _control(
                      _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                      'Camera',
                      _toggleCamera,
                    ),
                  if (isVideo && !_isGroupCall)
                    _control(Icons.cameraswitch, 'Flip', () async {
                      try {
                        await _session?.switchCamera();
                      } catch (error) {
                        if (mounted) {
                          setState(
                            () => _error = 'Could not switch camera: $error',
                          );
                        }
                      }
                    }),
                  _control(
                    _ending ? Icons.hourglass_top : Icons.call_end,
                    'End',
                    _hangUp,
                    color: Colors.red,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildRemoteView() {
    if (_isGroupCall) {
      final renderers = _groupRemoteRenderers.entries.toList();
      if (renderers.isEmpty) return null;
      return GridView.count(
        crossAxisCount: renderers.length > 1 ? 2 : 1,
        padding: const EdgeInsets.all(12),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: renderers.map((entry) {
          final renderer = entry.value;
          final peer = widget.groupParticipants.firstWhere(
            (participant) => participant.peerId == entry.key,
            orElse: () => GroupCallParticipant(
              callId: '',
              peerId: entry.key,
              peerName: 'Participant',
            ),
          );
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.black26,
            ),
            child: renderer.srcObject == null
                ? Center(
                    child: Text(
                      peer.peerName,
                      style: const TextStyle(color: Colors.white),
                    ),
                  )
                : RTCVideoView(
                    renderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
          );
        }).toList(),
      );
    }
    if (_remoteRenderer.srcObject != null && widget.media == CallMedia.video) {
      return RTCVideoView(
        _remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return null;
  }

  Widget _audioBackdrop() {
    return Container(
      alignment: const Alignment(0, -0.1),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff17675e), Color(0xff102c2b)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: CircleAvatar(
        radius: 76,
        backgroundColor: Colors.white24,
        backgroundImage: widget.peerAvatar.isEmpty
            ? null
            : NetworkImage(widget.peerAvatar),
        child: widget.peerAvatar.isEmpty
            ? const Icon(Icons.person, size: 78, color: Colors.white)
            : null,
      ),
    );
  }

  Widget _control(
    IconData icon,
    String label,
    Future<void> Function() onPressed, {
    Color color = Colors.white,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: _ending ? null : onPressed,
          style: IconButton.styleFrom(
            backgroundColor: color == Colors.red ? color : Colors.white24,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(16),
          ),
          icon: Icon(icon, size: 26),
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
