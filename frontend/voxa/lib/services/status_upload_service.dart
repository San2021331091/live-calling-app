import 'package:voxa/media/media_result.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/services/media_upload_service.dart';
import 'package:voxa/status/statusmodel.dart';

class StatusUploadService {
  StatusUploadService._();

  static Future<StatusModel> publish(MediaResult media) async {
    final url = await MediaUploadService.upload(
      media.file,
      isVideo: media.isVideo,
    );
    return ApiClient.instance.createStatus(
      image: url,
      isVideo: media.isVideo,
      caption: media.caption,
    );
  }
}
