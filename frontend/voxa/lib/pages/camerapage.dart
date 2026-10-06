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
          CameraPreview(_controller!),

          /// TOP BAR
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _circleButton(Icons.close, () => Navigator.pop(context)),
                _circleButton(
                  flashMode == FlashMode.off
                      ? Icons.flash_off
                      : Icons.flash_on,
                  _toggleFlash,
                ),
              ],
            ),
          ),

          /// BOTTOM CONTROLS
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _circleButton(Icons.photo, _pickFromGallery),

                /// CAPTURE BUTTON
                InkWell(
                  borderRadius: BorderRadius.circular(50),
                  onTap: _capturePhoto,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 5,
                      ),
                    ),
                  ),
                ),

                _circleButton(Icons.videocam, _captureVideo),

                _circleButton(Icons.cameraswitch, _switchCamera),
              ],
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
      child: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.black54,
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
