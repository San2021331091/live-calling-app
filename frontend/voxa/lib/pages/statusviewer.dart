import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:voxa/status/statusmodel.dart';

class StatusViewer extends StatefulWidget {
  final StatusModel status;
  const StatusViewer({super.key, required this.status});

  @override
  State<StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<StatusViewer> with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF42D392);
  VideoPlayerController? _videoController;
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((status) { if (status == AnimationStatus.completed) _close(); });
    if (widget.status.isVideo) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.status.image))
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          _videoController!.play();
          final duration = _videoController!.value.duration;
          _progress.duration = duration == Duration.zero ? const Duration(seconds: 5) : duration + const Duration(seconds: 1);
          _progress.forward();
        }).catchError((_) {
          if (mounted) _close();
        });
    } else {
      _progress.forward();
    }
  }

  void _close() { if (mounted) Navigator.pop(context); }

  @override
  void dispose() {
    _progress.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07100D),
      body: Stack(fit: StackFit.expand, children: [
        if (widget.status.isVideo)
          Center(child: _videoController?.value.isInitialized == true
              ? AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: VideoPlayer(_videoController!))
              : const CircularProgressIndicator(color: _green))
        else
          Image.network(widget.status.image, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48))),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.center,
          colors: [Color(0x99000000), Colors.transparent],
        ))),
        const Align(alignment: Alignment.bottomCenter, child: SizedBox(height: 230, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ))))),
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedBuilder(
              animation: _progress,
              builder: (_, __) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: _progress.value, minHeight: 3, backgroundColor: Colors.white38, color: _green),
              ),
            ),
            const SizedBox(height: 15),
            Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 1.5)),
                child: ClipOval(child: widget.status.isVideo
                    ? const ColoredBox(color: Color(0xFF1E332A), child: Icon(Icons.person, color: Colors.white))
                    : Image.network(widget.status.image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1E332A), child: Icon(Icons.person, color: Colors.white)))),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.status.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 3),
                Text(_timeAgo(widget.status.time), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
              IconButton(onPressed: _close, icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
            const Spacer(),
            if (widget.status.caption?.isNotEmpty == true)
              Center(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(18)),
                child: Text(widget.status.caption!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35)),
              )),
          ]),
        )),
      ]),
    );
  }

  String _timeAgo(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes} min ago';
    return '${difference.inHours} hr ago';
  }
}
