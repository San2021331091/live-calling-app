class MessageModel {
  final String? id;
  final String? chatId;
  final String? senderId;
  final String sender;
  final String message;
  final String time;
  final bool isMe;

  MessageModel({
    this.id,
    this.chatId,
    this.senderId,
    required this.sender,
    required this.message,
    required this.time,
    required this.isMe,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['created_at'] as String).toLocal();
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return MessageModel(
      id: json['id'] as String?,
      chatId: json['chat_id'] as String?,
      senderId: json['sender_id'] as String?,
      sender: json['sender'] as String? ?? '',
      message: json['content'] as String? ?? '',
      time: '$hour:$minute',
      isMe: json['is_me'] as bool? ?? false,
    );
  }
}
