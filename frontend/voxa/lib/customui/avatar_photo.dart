import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:voxa/media/media_result.dart';
import 'package:voxa/screens/editimage.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/services/media_upload_service.dart';

class AvatarPhoto extends StatelessWidget {
  const AvatarPhoto({
    super.key,
    required this.url,
    this.radius = 24,
    this.icon = Icons.person,
  });
  final String url;
  final double radius;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: const Color(0xFFE8F3ED),
      child: Center(
        child: Icon(icon, size: radius, color: const Color(0xFF168A62)),
      ),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: url.isEmpty
            ? placeholder
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class AvatarPhotoEditor extends StatefulWidget {
  const AvatarPhotoEditor({
    super.key,
    required this.url,
    required this.onSave,
    this.radius = 48,
    this.icon = Icons.person,
    this.enabled = true,
    this.onBusyChanged,
  });
  final String url;
  final Future<void> Function(String url) onSave;
  final double radius;
  final IconData icon;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;
  @override
  State<AvatarPhotoEditor> createState() => _AvatarPhotoEditorState();
}

class _AvatarPhotoEditorState extends State<AvatarPhotoEditor> {
  bool _busy = false;
  Future<void> _change() async {
    if (_busy || !widget.enabled) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photo'),
              onTap: () => Navigator.pop(sheet, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheet, 'camera'),
            ),
            if (widget.url.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit current photo'),
                onTap: () => Navigator.pop(sheet, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(sheet, 'remove'),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    File? downloaded;
    File? exported;
    try {
      if (action == 'remove') {
        await widget.onSave('');
      } else {
        File input;
        if (action == 'edit') {
          final directory = await getTemporaryDirectory();
          downloaded = File(
            '${directory.path}/avatar_${DateTime.now().microsecondsSinceEpoch}.jpg',
          );
          final dio = Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
          try {
            await dio.download(widget.url, downloaded.path);
          } finally {
            dio.close();
          }
          input = downloaded;
        } else {
          final picked = await ImagePicker().pickImage(
            source: action == 'camera'
                ? ImageSource.camera
                : ImageSource.gallery,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 85,
          );
          if (picked == null) return;
          input = File(picked.path);
        }
        if (!mounted) return;
        final result = await Navigator.push<MediaResult>(
          context,
          MaterialPageRoute(
            builder: (_) => EditImage(file: input, avatarMode: true),
          ),
        );
        if (result == null || !mounted) return;
        exported = result.file;
        final url = await MediaUploadService.upload(
          result.file,
          isVideo: false,
        );
        if (!mounted) return;
        await widget.onSave(url);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo updated.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Could not update the photo. Please try again.',
            ),
          ),
        );
      }
    } finally {
      for (final file in [downloaded, exported]) {
        if (file != null) {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Change photo',
    button: true,
    child: InkWell(
      onTap: widget.enabled && !_busy ? _change : null,
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AvatarPhoto(
            url: widget.url,
            radius: widget.radius,
            icon: widget.icon,
          ),
          if (_busy) const CircularProgressIndicator(),
          if (widget.enabled && !_busy)
            const Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(
                radius: 13,
                backgroundColor: Color(0xFF168A62),
                child: Icon(Icons.camera_alt, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    ),
  );
}
