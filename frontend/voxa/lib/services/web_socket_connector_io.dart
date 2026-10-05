import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocketChannel(Uri uri, String token) {
  return IOWebSocketChannel.connect(
    uri,
    headers: {'Authorization': 'Bearer $token'},
  );
}
