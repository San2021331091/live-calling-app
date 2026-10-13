import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Coordinates Android outgoing ringback and incoming system ringtone audio.
class CallRingtone {
  CallRingtone._();

  static final instance = CallRingtone._();

  final AudioPlayer _outgoingPlayer = AudioPlayer();
  bool _outgoingPlaying = false;
  bool _incomingPlaying = false;

  Future<void> startOutgoing() async {
    if (defaultTargetPlatform != TargetPlatform.android || _outgoingPlaying) {
      return;
    }
    _outgoingPlaying = true;
    try {
      await _outgoingPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            audioMode: AndroidAudioMode.ringtone,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
        ),
      );
      await _outgoingPlayer.setReleaseMode(ReleaseMode.loop);
      await _outgoingPlayer.play(AssetSource('call_ring.mp3'));
    } catch (_) {
      _outgoingPlaying = false;
      rethrow;
    }
  }

  Future<void> startIncoming() async {
    if (defaultTargetPlatform != TargetPlatform.android || _incomingPlaying) {
      return;
    }
    _incomingPlaying = true;
    try {
      await FlutterRingtonePlayer().playRingtone();
    } catch (_) {
      _incomingPlaying = false;
      rethrow;
    }
  }

  Future<void> stopIncoming() async {
    if (!_incomingPlaying) return;
    _incomingPlaying = false;
    await FlutterRingtonePlayer().stop();
  }

  Future<void> stopOutgoing() async {
    if (!_outgoingPlaying) return;
    _outgoingPlaying = false;
    await _outgoingPlayer.stop();
  }
}
