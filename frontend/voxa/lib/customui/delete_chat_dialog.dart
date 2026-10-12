import 'package:flutter/material.dart';
import 'package:voxa/services/api_client.dart';

Future<bool> deleteChatFromInbox(BuildContext context, String chatId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete chat from your inbox?'),
      content: const Text(
        'This removes the chat and its previous messages from your account. Other participants keep their copies. A new message will bring the chat back.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete chat'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await ApiClient.instance.deleteInboxChat(chatId);
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete chat: $error')));
    }
    return false;
  }
}
