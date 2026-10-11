import 'package:flutter/material.dart';
import 'package:voxa/customui/gradient_app_bar_background.dart';
import 'package:video_player/video_player.dart';

class MediaPreview extends StatefulWidget {
  const MediaPreview({super.key, required this.url, this.isAudio = false});
  final String url;
  final bool isAudio;

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  late final VideoPlayerController _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
    ..initialize().then((_) { if (mounted) setState(() {}); });

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: widget.isAudio ? const Color(0xFFF3F7F4) : Colors.black,
    appBar: AppBar(flexibleSpace: const GradientAppBarBackground()),
    body: Center(
      child: !_controller.value.isInitialized
          ? const CircularProgressIndicator()
          : widget.isAudio
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.graphic_eq, size: 76, color: Color(0xFF168A62)),
                const SizedBox(height: 12),
                const Text('Voice message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                SizedBox(
                  width: 280,
                  child: VideoProgressIndicator(_controller, allowScrubbing: true),
                ),
                const SizedBox(height: 8),
                Text('${_controller.value.position.inSeconds}s / ${_controller.value.duration.inSeconds}s'),
              ],
            )
          : AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () {
        setState(() {
          _controller.value.isPlaying ? _controller.pause() : _controller.play();
        });
      },
      child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
    ),
  );
}
