import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:voxa/model/call_model.dart';
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
  });

  final String callId;
  final String peerId;
  final String peerName;
  final String peerAvatar;
  final CallMedia media;
  final bool isIncoming;

  @override
  State<WebRtcCallScreen> createState() => _WebRtcCallScreenState();
}

class _WebRtcCallScreenState extends State<WebRtcCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  WebRtcCallSession? _session;
  String _status = 'Starting call...';
  String? _error;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    try {
      final session = WebRtcCallSession(
        callId: widget.callId,
        peerId: widget.peerId,
        media: widget.media,
        isIncoming: widget.isIncoming,
        onStatusChanged: (status) {
          if (mounted) setState(() => _status = status);
        },
        onRemoteStream: (stream) {
          _remoteRenderer.srcObject = stream;
          if (mounted) setState(() {});
        },
        onError: (error) {
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
      var statusError = '';
      try {
        await _session?.close(notifyPeer: true);
      } catch (closeError) {
        statusError = ' The server could not be notified: $closeError';
        await _session?.close();
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
    _session?.close();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _hangUp() async {
    if (_ending) return;
    setState(() => _ending = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _session?.close(notifyPeer: true);
      if (mounted) navigator.pop();
    } catch (error) {
      await _session?.close();
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
    _session?.setMicrophoneEnabled(enabled);
    setState(() => _microphoneEnabled = enabled);
  }

  Future<void> _toggleCamera() async {
    final enabled = !_cameraEnabled;
    _session?.setCameraEnabled(enabled);
    setState(() => _cameraEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.media == CallMedia.video;
    final hasRemoteVideo = _remoteRenderer.srcObject != null && isVideo;
    return Scaffold(
      backgroundColor: const Color(0xff102c2b),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasRemoteVideo)
              RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              _audioBackdrop(),
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
                    widget.peerName,
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
                  if (isVideo)
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
