import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mime/mime.dart';

/// Uploads public media with unsigned provider presets. Never put a Cloudinary
/// API secret in the mobile app; use a signed backend endpoint for private media.
class MediaUploadService {
  static final Dio _dio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 3)),
  );

  static Future<String> upload(File file, {required bool isVideo}) async {
    if (isVideo) return _uploadCloudinary(file);
    return _uploadImgbb(file);
  }

  static Future<String> _uploadImgbb(File file) async {
    final key = dotenv.env['IMGBB_API_KEY']?.trim() ?? '';
    if (key.isEmpty) throw Exception('Set IMGBB_API_KEY in frontend/voxa/.env');
    final response = await _dio.post<dynamic>(
      'https://api.imgbb.com/1/upload',
      queryParameters: {'key': key},
      data: FormData.fromMap({'image': await MultipartFile.fromFile(file.path)}),
    );
    final url = (response.data as Map<String, dynamic>)['data']?['url'] as String?;
    if (url == null || url.isEmpty) throw Exception('ImgBB did not return an image URL');
    return url;
  }

  static Future<String> _uploadCloudinary(File file) async {
    final configuredCloud = dotenv.env['CLOUDINARY_CLOUD_NAME']?.trim() ?? '';
    final cloudinaryUrl = dotenv.env['CLOUDINARY_URL']?.trim() ?? '';
    final cloud = configuredCloud.isNotEmpty
        ? configuredCloud
        : Uri.tryParse(cloudinaryUrl)?.host ?? '';
    final preset = dotenv.env['CLOUDINARY_UPLOAD_PRESET']?.trim() ?? '';
    if (cloud.isEmpty || preset.isEmpty) {
      throw Exception('Set CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET in frontend/voxa/.env');
    }
    final mime = lookupMimeType(file.path) ?? 'application/octet-stream';
    final resourceType = mime.startsWith('video/') ? 'video' : 'raw';
    final response = await _dio.post<dynamic>(
      'https://api.cloudinary.com/v1_1/$cloud/$resourceType/upload',
      data: FormData.fromMap({
        'upload_preset': preset,
        'file': await MultipartFile.fromFile(file.path),
      }),
    );
    final url = (response.data as Map<String, dynamic>)['secure_url'] as String?;
    if (url == null || url.isEmpty) throw Exception('Cloudinary did not return a file URL');
    return url;
  }
}
