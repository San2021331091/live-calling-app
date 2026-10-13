import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:voxa/main.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/services/chat_connection.dart';

class TestSink {
  final sent = <String>[];
  void add(dynamic data) => sent.add(data as String);
}

class TestChannel implements ChatConnection {
  final TestSink sink = TestSink();
  @override
  void add(String event) => sink.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Startup opens sign in immediately when no session exists', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsWidgets);
    expect(find.byType(TextFormField), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('Message sending waits for its own saved server event', () async {
    final channel = TestChannel();
    var saved = false;
    final sending = ApiClient.instance
        .sendMessage(channel, 'Hello')
        .then((_) => saved = true);
    final request =
        jsonDecode(channel.sink.sent.single) as Map<String, dynamic>;
    await Future<void>.delayed(Duration.zero);
    expect(saved, isFalse);
    ApiClient.instance.handleChatEvent(channel, {
      'type': 'message',
      'message': {'client_id': request['client_id'], 'is_me': false},
    });
    await Future<void>.delayed(Duration.zero);
    expect(saved, isFalse);
    ApiClient.instance.handleChatEvent(channel, {
      'type': 'message',
      'message': {'client_id': request['client_id'], 'is_me': true},
    });
    await sending;
    expect(saved, isTrue);
  });

  test('Server rejection reports a failed send', () async {
    final channel = TestChannel();
    final sending = ApiClient.instance.sendMessage(channel, 'Hello');
    final failure = expectLater(sending, throwsA(isA<ApiException>()));
    final request =
        jsonDecode(channel.sink.sent.single) as Map<String, dynamic>;
    ApiClient.instance.handleChatEvent(channel, {
      'type': 'error',
      'client_id': request['client_id'],
      'error': 'Could not save message',
    });
    await failure;
  });

  test('Disconnect reports unconfirmed messages as failed', () async {
    final channel = TestChannel();
    final sending = ApiClient.instance.sendMessage(channel, 'Hello');
    final failure = expectLater(sending, throwsA(isA<ApiException>()));
    ApiClient.instance.chatDisconnected(channel);
    await failure;
  });

  test('Attachment previews show readable names and captions', () {
    expect(
      ChatModel.previewContent(
        jsonEncode({
          '_voxa_media': true,
          'type': 'image',
          'caption': 'Our trip',
        }),
      ),
      'Photo: Our trip',
    );
    expect(ChatModel.previewContent('Hello'), 'Hello');
    expect(ChatModel.previewContent('{invalid'), '{invalid');
  });
}
