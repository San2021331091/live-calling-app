import 'dart:async';

import 'package:flutter/material.dart';
import 'package:voxa/status/statusmodel.dart';
import 'package:video_player/video_player.dart';

class StatusViewer extends StatefulWidget {
  final StatusModel status;
  const StatusViewer({super.key, required this.status});

  @override
  State<StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<StatusViewer> {
  VideoPlayerController? _videoController;
  Timer? _dismissTimer;
  @override
  void initState() {
    super.initState();
    if (widget.status.isVideo) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.status.image))
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          _videoController?.play();
          final duration = _videoController?.value.duration ?? const Duration(seconds: 5);
          _dismissTimer = Timer(duration + const Duration(seconds: 1), _close);
        });
    } else {
      _dismissTimer = Timer(const Duration(seconds: 5), _close);
    }
  }

  void _close() { if (mounted) Navigator.pop(context); }

  @override
  void dispose() { _dismissTimer?.cancel(); _videoController?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned(top: 28, right: 12, child: SafeArea(child: IconButton(onPressed: _close, icon: const Icon(Icons.close, color: Colors.white)))),
          Center(
            child: widget.status.isVideo
                ? (_videoController?.value.isInitialized == true
                    ? AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: VideoPlayer(_videoController!))
                    : const CircularProgressIndicator())
                : Image.network(
              widget.status.image,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          if (widget.status.caption?.isNotEmpty == true)
            Positioned(bottom: 36, left: 20, right: 20, child: Text(widget.status.caption!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundImage: widget.status.isVideo ? null : NetworkImage(widget.status.image),
                    child: widget.status.isVideo ? const Icon(Icons.person) : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.status.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
