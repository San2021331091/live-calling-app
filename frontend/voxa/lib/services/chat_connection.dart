import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

abstract class ChatConnection {
  Stream<dynamic> get stream;
  void add(String event);
  Future<void> close();
}

class SocketChatConnection implements ChatConnection {
  SocketChatConnection(this.channel, {Stream<dynamic>? stream})
    : _stream = stream ?? channel.stream;
  final WebSocketChannel channel;
  final Stream<dynamic> _stream;
  @override
  Stream<dynamic> get stream => _stream;
  @override
  void add(String event) => channel.sink.add(event);
  @override
  Future<void> close() async {
    await channel.sink.close();
  }
}

typedef ChatSnapshotLoader =
    Future<Map<String, dynamic>> Function(String? afterId);
typedef ChatMessageSender =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> message);

class HttpChatConnection extends WidgetsBindingObserver
    implements ChatConnection {
  HttpChatConnection({
    required this.load,
    required this.send,
    this.interval = const Duration(seconds: 3),
  }) {
    _events = StreamController<dynamic>(onCancel: close);
  }
  final ChatSnapshotLoader load;
  final ChatMessageSender send;
  final Duration interval;
  late final StreamController<dynamic> _events;
  Timer? _timer;
  String? _cursor, _cutoff;
  bool _closed = false, _polling = false, _paused = false;
  @override
  Stream<dynamic> get stream => _events.stream;

  Future<void> start() async {
    await _poll();
    if (_closed) return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) {
      if (!_paused) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    try {
      await _poll();
    } catch (error, trace) {
      if (!_closed) {
        _events.addError(error, trace);
        await close();
      }
    }
  }

  Future<void> _poll() async {
    if (_closed || _polling) return;
    _polling = true;
    try {
      var more = true;
      while (more && !_closed && !_paused) {
        final result = await load(_cursor);
        if (_closed) return;
        final cutoff = result['cleared_before'] as String?;
        if (cutoff != null && cutoff != _cutoff) {
          _emit({'type': 'history_cleared', 'cleared_before': cutoff});
          _cutoff = cutoff;
        }
        final messages = (result['messages'] as List)
            .cast<Map<String, dynamic>>();
        for (final message in messages) {
          _emit({'type': 'message', 'message': message});
        }
        if (messages.isNotEmpty) _cursor = messages.last['id'] as String;
        more = result['has_more'] == true && messages.isNotEmpty;
      }
      _emit({'type': 'appearance_changed'});
    } finally {
      _polling = false;
    }
  }

  void _emit(Map<String, dynamic> event) {
    if (!_closed) _events.add(jsonEncode(event));
  }

  @override
  void add(String event) {
    if (_closed) throw StateError('Chat connection is closed');
    unawaited(_send(jsonDecode(event) as Map<String, dynamic>));
  }

  Future<void> _send(Map<String, dynamic> message) async {
    try {
      _emit(await send(message));
    } catch (_) {
      _emit({
        'type': 'error',
        'client_id': message['client_id'],
        'error':
            'Could not confirm delivery. Check the conversation before retrying.',
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    if (!_paused) unawaited(_refresh());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events.close());
  }
}
