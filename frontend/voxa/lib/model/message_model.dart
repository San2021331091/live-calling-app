import 'dart:convert';

class MessageModel {
  final String? id;
  final String? chatId;
  final String? senderId;
  final String sender;
  final String message;
  final String time;
  final bool isMe;
  final String? mediaUrl;
  final String? mediaType;
  final String? mediaName;

  MessageModel({
    this.id,
    this.chatId,
    this.senderId,
    required this.sender,
    required this.message,
    required this.time,
    required this.isMe,
    this.mediaUrl,
    this.mediaType,
    this.mediaName,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['created_at'] as String).toLocal();
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final content = json['content'] as String? ?? '';
    String? mediaUrl, mediaType, mediaName;
    var display = content;
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> && decoded['_voxa_media'] == true) {
        mediaUrl = decoded['url'] as String?;
        mediaType = decoded['type'] as String?;
        mediaName = decoded['name'] as String?;
        display = decoded['caption'] as String? ?? mediaName ?? 'Attachment';
      }
    } catch (_) {}
    return MessageModel(
      id: json['id'] as String?,
      chatId: json['chat_id'] as String?,
      senderId: json['sender_id'] as String?,
      sender: json['sender'] as String? ?? '',
      message: display,
      time: '$hour:$minute',
      isMe: json['is_me'] as bool? ?? false,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      mediaName: mediaName,
    );
  }
}
