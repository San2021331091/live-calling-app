import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:voxa/model/call_model.dart';
import 'package:voxa/services/api_client.dart';

class WebRtcCallSession {
  WebRtcCallSession({
    required this.callId,
    required this.peerId,
    required this.media,
    required this.isIncoming,
    required this.onStatusChanged,
    required this.onRemoteStream,
    required this.onError,
  });

  final String callId;
  final String peerId;
  final CallMedia media;
  final bool isIncoming;
  final void Function(String status) onStatusChanged;
  final void Function(MediaStream? stream) onRemoteStream;
  final void Function(String error) onError;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  Timer? _pollTimer;
  int _lastSequence = 0;
  bool _closed = false;
  bool _remoteDescriptionSet = false;
  bool _pollInProgress = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  MediaStream? get localStream => _localStream;

  Future<void> start() async {
    onStatusChanged(isIncoming ? 'Connecting...' : 'Calling...');
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': media == CallMedia.video
          ? {'facingMode': 'user'}
          : false,
    });
    _peerConnection = await createPeerConnection({
      'iceServers': await ApiClient.instance.loadCallIceServers(),
      'sdpSemantics': 'unified-plan',
    });

    _peerConnection!.onIceCandidate = (candidate) {
      final candidateText = candidate.candidate;
      if (candidateText == null || candidateText.isEmpty || _closed) return;
      unawaited(
        _sendSignal('ice', candidate.toMap()).catchError((Object error) {
          if (!_closed) onError('Could not send network candidate: $error');
        }),
      );
    };
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) onRemoteStream(event.streams.first);
    };
    _peerConnection!.onConnectionState = (state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          onStatusChanged('Connected');
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          onStatusChanged('Connecting...');
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          onError('Could not establish a WebRTC connection. Check network or TURN configuration.');
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          onStatusChanged('Reconnecting...');
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          onStatusChanged('Call ended');
        default:
          break;
      }
    };

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => unawaited(_pollSignals()),
    );

    if (!isIncoming) {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      await _sendSignal('offer', offer.toMap());
      onStatusChanged('Ringing...');
    }
  }

  Future<void> _pollSignals() async {
    if (_closed || _pollInProgress) return;
    _pollInProgress = true;
    try {
      final batch = await ApiClient.instance.loadCallSignals(
        callId: callId,
        afterSequence: _lastSequence,
      );
      final callStatus = batch['status'];
      if (callStatus != 'started' && callStatus != 'active') {
        if (!_closed) {
          onStatusChanged(callStatus == 'missed' ? 'Call declined' : 'Call ended');
          await close();
        }
        return;
      }
      if (callStatus == 'active') onStatusChanged('Connected');
      final signals = batch['signals'] as List<Map<String, dynamic>>;
      for (final signal in signals) {
        if (_closed) break;
        _lastSequence = signal['sequence'] as int;
        await _handleSignal(signal);
      }
    } catch (error) {
      if (!_closed) {
        _pollTimer?.cancel();
        onError('Call signaling failed: $error');
      }
    } finally {
      _pollInProgress = false;
    }
  }

  Future<void> _handleSignal(Map<String, dynamic> signal) async {
    final payload = Map<String, dynamic>.from(
      signal['payload'] as Map<dynamic, dynamic>? ?? const {},
    );
    switch (signal['type']) {
      case 'offer':
        if (!isIncoming || _remoteDescriptionSet) return;
        await _setRemoteDescription(payload);
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        await _sendSignal('answer', answer.toMap());
        onStatusChanged('Connecting...');
      case 'answer':
        if (isIncoming || _remoteDescriptionSet) return;
        await _setRemoteDescription(payload);
        onStatusChanged('Connecting...');
      case 'ice':
        final candidate = RTCIceCandidate(
          payload['candidate'] as String?,
          payload['sdpMid'] as String?,
          (payload['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_remoteDescriptionSet) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _pendingCandidates.add(candidate);
        }
      default:
        break;
    }
  }

  Future<void> _setRemoteDescription(Map<String, dynamic> value) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(
        value['sdp'] as String?,
        value['type'] as String?,
      ),
    );
    _remoteDescriptionSet = true;
    for (final candidate in _pendingCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  Future<void> _sendSignal(String type, Map<String, dynamic> payload) {
    return ApiClient.instance
        .signalCall(callId: callId, targetId: peerId, type: type, payload: payload)
        .then((_) {});
  }

  void setMicrophoneEnabled(bool enabled) {
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  void setCameraEnabled(bool enabled) {
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> close({bool notifyPeer = false, bool missed = false}) async {
    if (_closed) return;
    _closed = true;
    _pollTimer?.cancel();
    Object? notificationError;
    try {
      if (notifyPeer) {
        await ApiClient.instance.endCall(callId, missed: missed);
      }
    } catch (error) {
      notificationError = error;
    } finally {
      onRemoteStream(null);
      await _peerConnection?.close();
      await _peerConnection?.dispose();
      await _localStream?.dispose();
    }
    if (notificationError != null) throw notificationError;
  }
}
