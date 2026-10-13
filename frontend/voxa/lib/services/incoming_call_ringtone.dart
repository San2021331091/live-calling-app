import 'package:audioplayers/audioplayers.dart';

class IncomingCallRingtone {
  IncomingCallRingtone._();

  static final instance = IncomingCallRingtone._();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  Future<void> start() async {
    if (_isPlaying) return;
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          audioMode: AndroidAudioMode.ringtone,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notificationRingtone,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
      ),
    );
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource('call_ring.mp3'));
    _isPlaying = true;
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } finally {
      _isPlaying = false;
    }
  }
}
