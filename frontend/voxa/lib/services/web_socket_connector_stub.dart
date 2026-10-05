import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocketChannel(Uri uri, String _) {
  return WebSocketChannel.connect(uri);
}
