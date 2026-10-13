import 'package:flutter_test/flutter_test.dart';
import 'package:voxa/services/push_notification_service.dart';

void main() {
  test('Notifications cannot navigate into another signed-in account', () {
    const message = PushEvent({
      'type': 'chat_message',
      'recipient_id': 'alice',
      'chat_id': 'chat',
    }, opened: true);
    expect(message.isFor('alice'), isTrue);
    expect(message.isFor('bob'), isFalse);
    expect(message.isFor(''), isFalse);
    const call = PushEvent({
      'type': 'incoming_call',
      'recipient_id': 'alice',
      'call_id': 'call',
    }, opened: true);
    expect(call.isFor('alice'), isTrue);
    expect(call.isFor('bob'), isFalse);
  });

  test('Unknown and incomplete notification routes are ignored', () {
    for (final data in [
      <String, dynamic>{},
      {'type': 'chat_message', 'recipient_id': 'alice'},
      {'type': 'incoming_call', 'recipient_id': 'alice'},
      {'type': 'unknown', 'recipient_id': 'alice', 'chat_id': 'chat'},
    ]) {
      expect(PushEvent(data, opened: true).isFor('alice'), isFalse);
    }
  });
}
