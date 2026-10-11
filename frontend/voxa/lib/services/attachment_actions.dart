import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> openAttachment(BuildContext context, String url) async {
  try {
    await const MethodChannel(
      'com.voxa/external_links',
    ).invokeMethod<void>('open', {'url': url});
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open attachment: $error')),
      );
    }
  }
}
