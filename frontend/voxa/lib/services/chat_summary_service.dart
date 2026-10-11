import 'package:voxa/model/message_model.dart';

/// A factual overview of loaded messages; no generated or inferred topics.
class ChatSummaryService {
  static String summarize(
    List<MessageModel> messages, {
    required String chatName,
  }) {
    if (messages.isEmpty) return '$chatName has no loaded messages yet.';
    final senders = messages
        .map((message) => message.senderId ?? message.sender)
        .where((sender) => sender.isNotEmpty)
        .toSet();
    final attachments = messages
        .where((message) => message.mediaUrl != null)
        .length;
    return '${messages.length} loaded messages from ${senders.length} participants. '
        '$attachments attachments.\n\nLatest message: ${messages.last.message}';
  }
}
