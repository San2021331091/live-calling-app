import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:voxa/model/call_model.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/model/message_model.dart';
import 'package:voxa/model/user_model.dart';
import 'package:voxa/services/web_socket_connector.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'access_token';
  static const _userIdKey = 'user_id';
  static const _userNameKey = 'user_name';
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  Uri get _baseUri {
    final value = _configuredBaseUrl.isNotEmpty
        ? _configuredBaseUrl
        : kIsWeb
        ? 'http://localhost:8080'
        : 'http://10.0.2.2:8080';
    final uri = Uri.parse(value);
    if (uri.host.isEmpty || !{'http', 'https'}.contains(uri.scheme)) {
      throw const ApiException('API_BASE_URL must be an absolute HTTP or HTTPS URL');
    }
    return uri;
  }

  String get userId => _cachedUserId;
  String _cachedUserId = '';

  String get userName => _cachedUserName;
  String _cachedUserName = '';

  Future<String?> get _token => _storage.read(key: _tokenKey);

  Future<void> register({
    required String name,
    required String phone,
    required String password,
  }) async {
    await _authenticate(
      'api/auth/register',
      {'name': name, 'phone': phone, 'password': password},
    );
  }

  Future<void> login({
    required String phone,
    required String password,
  }) async {
    await _authenticate(
      'api/auth/login',
      {'phone': phone, 'password': password},
    );
  }

  Future<void> _authenticate(String path, Map<String, String> body) async {
    final response = await http.post(
      _baseUri.resolve(path),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final result = _decodeResponse(response);
    final token = result['access_token'] as String?;
    final user = result['user'];
    if (token == null || user is! Map<String, dynamic>) {
      throw const ApiException('The server returned an invalid sign-in response');
    }
    final authenticatedUser = UserModel.fromJson(user);
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: authenticatedUser.id);
    await _storage.write(key: _userNameKey, value: authenticatedUser.name);
    _cachedUserId = authenticatedUser.id;
    _cachedUserName = authenticatedUser.name;
  }

  Future<UserModel> loadCurrentUser() async {
    final result = await _request(_baseUri.resolve('api/auth/me'));
    return UserModel.fromJson(result);
  }

  Future<void> signOut() async {
    await _storage.deleteAll();
    _cachedUserId = '';
    _cachedUserName = '';
  }

  Future<List<UserModel>> loadUsers({String query = ''}) async {
    final uri = _baseUri.resolve('api/users').replace(
      queryParameters: query.isEmpty ? null : {'query': query},
    );
    final result = await _request(uri);
    final users = result['users'];
    if (users is! List) {
      throw const ApiException('The server returned an invalid users response');
    }
    return users
        .map((item) => UserModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatModel>> loadChats() async {
    final result = await _request(_baseUri.resolve('api/chats'));
    final chats = result['chats'];
    if (chats is! List) {
      throw const ApiException('The server returned an invalid chats response');
    }
    return chats
        .map((item) => ChatModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatModel> createDirectChat({String? userId, String? phone}) async {
    final body = <String, Object?>{};
    if (userId != null) body['user_id'] = userId;
    if (phone != null) body['phone'] = phone;

    final result = await _request(
      _baseUri.resolve('api/chats/direct'),
      method: 'POST',
      body: body,
    );
    return ChatModel.fromJson(result);
  }

  Future<ChatModel> createGroup({
    required String name,
    required List<String> members,
  }) async {
    final result = await _request(
      _baseUri.resolve('api/chats/groups'),
      method: 'POST',
      body: {'name': name, 'members': members},
    );
    return ChatModel.fromJson(result);
  }

  Future<ChatModel> createCommunity({
    required String name,
    required String type,
    required List<String> members,
  }) async {
    final result = await _request(
      _baseUri.resolve('api/chats/communities'),
      method: 'POST',
      body: {'name': name, 'type': type, 'members': members},
    );
    return ChatModel.fromJson(result);
  }

  Future<List<MessageModel>> loadMessages(String chatId) async {
    final result = await _request(
      _baseUri.resolve('api/chats/$chatId/messages'),
    );
    final messages = result['messages'];
    if (messages is! List) {
      throw const ApiException('The server returned an invalid messages response');
    }
    return messages
        .map((item) => MessageModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<WebSocketChannel> connectToChat(String chatId) async {
    final token = await _token;
    if (token == null || token.isEmpty) {
      throw const ApiException('Your session has expired. Please sign in again.');
    }
    final base = _baseUri;
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/$chatId',
      queryParameters: kIsWeb ? {'access_token': token} : null,
    );
    final channel = connectWebSocketChannel(uri, token);
    await channel.ready;
    return channel;
  }

  Future<void> sendMessage(WebSocketChannel channel, String content) async {
    channel.sink.add(jsonEncode({'type': 'message', 'content': content}));
  }

  Future<List<CallModel>> loadCallHistory() async {
    final result = await _request(_baseUri.resolve('api/calls'));
    final calls = result['calls'];
    if (calls is! List) {
      throw const ApiException('The server returned an invalid call history response');
    }
    final currentUserId = await _loadStoredUserId();
    return calls
        .map((item) => CallModel.fromJson(item as Map<String, dynamic>, currentUserId: currentUserId))
        .toList();
  }

  Future<CallModel> createCall({
    required String peerId,
    required CallMedia media,
    String status = 'started',
  }) async {
    final result = await _request(
      _baseUri.resolve('api/calls'),
      method: 'POST',
      body: {
        'peer_id': peerId,
        'kind': media == CallMedia.video ? 'video' : 'audio',
        'status': status,
      },
    );
    final userId = await _loadStoredUserId();
    return CallModel.fromJson(result, currentUserId: userId);
  }

  Future<Map<String, dynamic>> signalCall({
    required String callId,
    required String type,
    String? targetId,
    Map<String, dynamic>? payload,
  }) async {
    final body = <String, Object?>{'type': type};
    if (targetId != null) body['target_id'] = targetId;
    if (payload != null) body['payload'] = payload;

    final result = await _request(
      _baseUri.resolve('api/calls/$callId/signal'),
      method: 'POST',
      body: body,
    );
    return result;
  }

  Future<String> _loadStoredUserId() async {
    final userId = await _storage.read(key: _userIdKey);
    return userId ?? _cachedUserId;
  }

  Future<Map<String, dynamic>> _request(
    Uri uri, {
    String method = 'GET',
    Map<String, Object?>? body,
  }) async {
    final token = await _token;
    if (token == null || token.isEmpty) {
      throw const ApiException('Your session has expired. Please sign in again.');
    }
    final response = await switch (method) {
      'POST' => http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ),
      _ => http.get(uri, headers: {'Authorization': 'Bearer $token'}),
    };
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        'The server returned an invalid response (${response.statusCode})',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(
        'The server returned an invalid response (${response.statusCode})',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        decoded['error'] as String? ?? 'Request failed (${response.statusCode})',
      );
    }
    return decoded;
  }
}
