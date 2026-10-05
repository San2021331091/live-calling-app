import 'package:web_socket_channel/web_socket_channel.dart';

import 'web_socket_connector_stub.dart'
    if (dart.library.io) 'web_socket_connector_io.dart' as platform;

WebSocketChannel connectWebSocketChannel(Uri uri, String token) {
  return platform.connectWebSocketChannel(uri, token);
}
