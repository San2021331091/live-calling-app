import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class VideoCallScreen extends StatefulWidget {
  final String callerName;
  final String callerAvatar;

  const VideoCallScreen({
    super.key,
    required this.callerName,
    required this.callerAvatar,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? cameras;
  bool isMuted = false;
  bool isVideoOff = false;
  bool isFrontCamera = true;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    cameras = await availableCameras();
    _cameraController = CameraController(
      cameras!.first,
      ResolutionPreset.high,
      enableAudio: true,
    );
    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _cameraController == null || !_cameraController!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Camera Preview
                CameraPreview(_cameraController!),

                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black,
                        Colors.transparent,
                        Colors.black,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),

                // Caller info at top
                Positioned(
                  top: 50,
                  left: 20,
                  right: 20,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: NetworkImage(widget.callerAvatar),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.callerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Video Calling...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Action buttons at bottom
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionButton(
                        icon: isMuted ? Icons.mic_off : Icons.mic,
                        color: isMuted ? Colors.redAccent : Colors.green,
                        onTap: () {
                          setState(() {
                            isMuted = !isMuted;
                          });
                        },
                      ),
                      _actionButton(
                        icon: isVideoOff ? Icons.videocam_off : Icons.videocam,
                        color: isVideoOff ? Colors.redAccent : Colors.green,
                        onTap: () {
                          setState(() {
                            isVideoOff = !isVideoOff;
                          });
                        },
                      ),
                      _actionButton(
                        icon: Icons.cameraswitch,
                        color: Colors.blueAccent,
                        onTap: () {
                          _switchCamera();
                        },
                      ),
                      _actionButton(
                        icon: Icons.call_end,
                        color: Colors.redAccent,
                        onTap: () {
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  void _switchCamera() {
    if (cameras == null || cameras!.length < 2) return;

    final newIndex = isFrontCamera ? 1 : 0;
    _cameraController = CameraController(
      cameras![newIndex],
      ResolutionPreset.high,
      enableAudio: true,
    );
    _cameraController!.initialize().then((_) {
      if (mounted) setState(() {});
      isFrontCamera = !isFrontCamera;
    });
  }
}
