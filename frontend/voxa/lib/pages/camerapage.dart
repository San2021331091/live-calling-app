import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voxa/screens/capturephoto.dart';
import 'package:voxa/media/media_result.dart';




class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  int selectedCameraIndex = 0;

  FlashMode flashMode = FlashMode.off;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
    cameras = await availableCameras();
    if (cameras!.isEmpty) throw CameraException('no_camera', 'No camera is available');
    _controller = CameraController(
      cameras![selectedCameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (mounted) setState(() {});
    } catch (_) { if (mounted) setState(() {}); }
  }

  /// -------- GALLERY --------
  Future<void> _pickFromGallery() async {
    final XFile? image =
        await _picker.pickImage(source: ImageSource.gallery);

    if (image == null || !mounted) return;

    final result = await Navigator.push<MediaResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CapturePhoto(file: File(image.path)),
      ),
    );
    if (result != null && mounted) Navigator.pop(context, result);
  }

  /// -------- CAMERA CONTROLS --------
  Future<void> _switchCamera() async {
    if ((cameras?.length ?? 0) < 2) return;
    selectedCameraIndex = selectedCameraIndex == 0 ? 1 : 0;
    await _controller?.dispose();
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    flashMode = flashMode == FlashMode.off
        ? FlashMode.torch
        : FlashMode.off;
    await _controller?.setFlashMode(flashMode);
    setState(() {});
  }

  /// -------- PHOTO --------
  Future<void> _capturePhoto() async {
    final XFile file = await _controller!.takePicture();

    if (!mounted) return;

    final result = await Navigator.push<MediaResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CapturePhoto(file: File(file.path)),
      ),
    );
    if (result != null && mounted) Navigator.pop(context, result);
  }

  Future<void> _captureVideo() async {
    final video = await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 60));
    if (video == null || !mounted) return;
    Navigator.pop(context, MediaResult(file: File(video.path), isVideo: true, caption: ''));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('Camera unavailable. Check camera permission.', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.22, 0.62, 1],
                    colors: [Color(0x99000000), Colors.transparent, Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Column(
                children: [
                  Row(children: [
                    _circleButton(Icons.close_rounded, () => Navigator.pop(context)),
                    const Expanded(child: Column(children: [
                      Text('CREATE UPDATE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                      SizedBox(height: 3),
                      Text('Capture a moment', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ])),
                    _circleButton(flashMode == FlashMode.off ? Icons.flash_off_rounded : Icons.flash_on_rounded, _toggleFlash),
                  ]),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _bottomAction(Icons.photo_library_outlined, 'GALLERY', _pickFromGallery),
                      GestureDetector(
                        onTap: _capturePhoto,
                        child: Container(
                          width: 78, height: 78, padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                          child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                        ),
                      ),
                      _bottomAction(Icons.videocam_outlined, 'VIDEO', _captureVideo),
                      _bottomAction(Icons.cameraswitch_rounded, 'FLIP', _switchCamera),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
        child: Icon(icon, color: Colors.white, size: 21),
      ),
    );
  }

  Widget _bottomAction(IconData icon, String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(width: 62, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white, size: 25),
      const SizedBox(height: 7),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.7)),
    ])),
  );
}
