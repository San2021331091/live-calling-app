import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MediaPreview extends StatefulWidget {
  const MediaPreview({super.key, required this.url});
  final String url;

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
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
    body: Center(child: _controller.value.isInitialized
      ? AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller))
      : const CircularProgressIndicator()),
    floatingActionButton: FloatingActionButton(
      onPressed: () { setState(() { _controller.value.isPlaying ? _controller.pause() : _controller.play(); }); },
      child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
    ),
  );
}
