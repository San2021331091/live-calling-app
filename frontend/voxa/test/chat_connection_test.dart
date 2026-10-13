import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxa/services/chat_connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'HTTP transport drains pages and delivers clear before new messages',
    () async {
      final calls = <String?>[];
      final connection = HttpChatConnection(
        load: (cursor) async {
          calls.add(cursor);
          return {
            'messages': [
              {'id': cursor == null ? 'first' : 'second'},
            ],
            'cleared_before': '2026-10-13T12:00:00Z',
            'has_more': cursor == null,
          };
        },
        send: (_) async => {},
        interval: const Duration(days: 1),
      );
      await connection.start();
      final events = <Map<String, dynamic>>[];
      final subscription = connection.stream.listen(
        (raw) => events.add(jsonDecode(raw as String) as Map<String, dynamic>),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, [null, 'first']);
      expect(events.map((e) => e['type']), [
        'history_cleared',
        'message',
        'message',
        'appearance_changed',
      ]);
      await subscription.cancel();
    },
  );
  test('HTTP send acknowledges only after server confirms storage', () async {
    final saved = Completer<Map<String, dynamic>>();
    final connection = HttpChatConnection(
      load: (_) async => {'messages': [], 'has_more': false},
      send: (body) {
        expect(body['client_id'], 'request-id');
        return saved.future;
      },
      interval: const Duration(days: 1),
    );
    await connection.start();
    final events = <Map<String, dynamic>>[];
    final subscription = connection.stream.listen(
      (raw) => events.add(jsonDecode(raw as String) as Map<String, dynamic>),
    );
    connection.add(
      jsonEncode({
        'type': 'message',
        'client_id': 'request-id',
        'content': 'Hello',
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events.where((e) => e['type'] == 'message'), isEmpty);
    saved.complete({
      'type': 'message',
      'message': {'id': 'saved-id', 'client_id': 'request-id', 'is_me': true},
    });
    await Future<void>.delayed(Duration.zero);
    expect(events.last['message']['id'], 'saved-id');
    await subscription.cancel();
  });
  test('Closing HTTP transport ignores in-flight responses', () async {
    final snapshot = Completer<Map<String, dynamic>>();
    final connection = HttpChatConnection(
      load: (_) => snapshot.future,
      send: (_) async => {},
    );
    final start = connection.start();
    await connection.close();
    snapshot.complete({
      'messages': [
        {'id': 'late'},
      ],
    });
    await start;
    expect(await connection.stream.toList(), isEmpty);
  });
}
