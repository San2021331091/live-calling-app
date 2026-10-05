class ChatModel {
  final String name;
  final String img;
  final String? id;
  final String? peerId;
  final String? peerPhone;
  final bool? isGroup;
  final bool? isCommunity;
  final String ? about;
  final String? currentMessage;
  final String? time;
  

  const ChatModel({
    required this.name,
    required this.img,
    this.id,
    this.peerId,
    this.peerPhone,
    this.isGroup,
    this.isCommunity,
    this.about,
    this.currentMessage,
    this.time,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    final lastMessageAt = json['last_message_at'] as String?;
    return ChatModel(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Unknown',
      img: '',
      peerId: json['peer_id'] as String?,
      peerPhone: json['peer_phone'] as String?,
      isGroup: json['is_group'] as bool? ?? false,
      isCommunity: json['is_community'] as bool? ?? false,
      about: json['community_type'] as String?,
      currentMessage: json['current_message'] as String? ?? '',
      time: lastMessageAt == null
          ? ''
          : _formatTime(DateTime.parse(lastMessageAt).toLocal()),
    );
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }
}
