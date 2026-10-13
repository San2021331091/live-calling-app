import 'dart:convert';

class ChatModel {
  final String theme;
  final String personalTheme;
  final String sharedTheme;
  final bool muted;
  final DateTime? lastMessageAt;
  final String lastSenderId;
  final String name;
  final String img;
  final String? id;
  final String? peerId;
  final String? peerPhone;
  final bool? isGroup;
  final bool? isCommunity;
  final bool isCreator;
  final String? about;
  final String? currentMessage;
  final String? time;

  const ChatModel({
    this.theme = 'classic',
    this.personalTheme = '',
    this.sharedTheme = 'classic',
    this.muted = false,
    this.lastMessageAt,
    this.lastSenderId = '',
    required this.name,
    required this.img,
    this.id,
    this.peerId,
    this.peerPhone,
    this.isGroup,
    this.isCommunity,
    this.isCreator = false,
    this.about,
    this.currentMessage,
    this.time,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    final lastMessageAt = json['last_message_at'] as String?;
    return ChatModel(
      id: json['id'] as String?,
      muted: json['muted'] as bool? ?? false,
      lastMessageAt: lastMessageAt == null
          ? null
          : DateTime.parse(lastMessageAt),
      lastSenderId: json['last_sender_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      img: json['avatar_url'] as String? ?? '',
      theme: json['theme'] as String? ?? 'classic',
      personalTheme: json['personal_theme'] as String? ?? '',
      sharedTheme: json['shared_theme'] as String? ?? 'classic',
      peerId: json['peer_id'] as String?,
      peerPhone: json['peer_phone'] as String?,
      isGroup: json['is_group'] as bool? ?? false,
      isCommunity: json['is_community'] as bool? ?? false,
      isCreator: json['is_creator'] as bool? ?? false,
      about: json['community_type'] as String?,
      currentMessage: previewContent(json['current_message'] as String? ?? ''),
      time: lastMessageAt == null
          ? ''
          : _formatTime(DateTime.parse(lastMessageAt).toLocal()),
    );
  }

  static String previewContent(String content) {
    try {
      final media = jsonDecode(content);
      if (media is Map<String, dynamic> && media['_voxa_media'] == true) {
        final label = switch (media['type']) {
          'image' => 'Photo',
          'video' => 'Video',
          'audio' => 'Voice message',
          _ => 'Attachment',
        };
        final caption = media['caption'] as String? ?? '';
        return caption.isNotEmpty
            ? '$label: $caption'
            : (media['name'] as String? ?? label);
      }
    } catch (_) {}
    return content;
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }
}
