import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:voxa/media/media_result.dart';
import 'package:voxa/screens/editimage.dart';


class CapturePhoto extends StatefulWidget {
  final File? file;

  const CapturePhoto({super.key, this.file});

  @override
  State<CapturePhoto> createState() => _CapturePhotoState();
}

class _CapturePhotoState extends State<CapturePhoto> {
  CameraController? _controller;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();

    if (widget.file != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openImage(widget.file!);
      });
    } else {
      _initCamera();
    }
  }

  /// 📸 Camera initialization (photo only)
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  /// Open captured image
  Future<void> _openImage(File file) async {
    final result = await Navigator.push<MediaResult>(
      context,
      MaterialPageRoute(
        builder: (_) => EditImage(file: file),
      ),
    );
    if (mounted && result != null) Navigator.pop(context, result);
  }

  /// 📸 Take photo
  Future<void> _takePhoto() async {
    if (_isBusy) return;
    if (_controller == null || !_controller!.value.isInitialized) return;

    _isBusy = true;

    try {
      final XFile file = await _controller!.takePicture();
      _isBusy = false;

      final result = await Navigator.push<MediaResult>(
        context,
        MaterialPageRoute(
          builder: (_) => EditImage(file: File(file.path)),
        ),
      );

      if (result != null) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      _isBusy = false;
      debugPrint('Photo capture error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controller!.value.hasError) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CameraPreview(_controller!),

          /// Capture button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _takePhoto,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
