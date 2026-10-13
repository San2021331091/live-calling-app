import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:voxa/model/call_model.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/model/message_model.dart';
import 'package:voxa/model/user_model.dart';
import 'package:voxa/status/statusmodel.dart';
import 'package:voxa/services/web_socket_connector.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

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
  static final Dio _dio = Dio(
    BaseOptions(
      contentType: Headers.jsonContentType,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => status != null,
    ),
  );

  Uri get _baseUri {
    final configuredBaseUrl = dotenv.env['API_BASE_URL']?.trim() ?? '';
    final value = configuredBaseUrl.isNotEmpty
        ? configuredBaseUrl
        : kIsWeb
        ? 'http://localhost:8080'
        : 'http://10.0.2.2:8080';
    final uri = Uri.parse(value);
    if (uri.host.isEmpty || !{'http', 'https'}.contains(uri.scheme)) {
      throw const ApiException(
        'API_BASE_URL must be an absolute HTTP or HTTPS URL',
      );
    }
    return uri;
  }

  Future<void> updateGroupName(String chatId, String name) async {
    await _request(
      _baseUri.resolve('api/chats/$chatId'),
      method: 'PATCH',
      body: {'name': name},
    );
  }

  Future<void> updateGroupAppearance(
    String chatId, {
    String? avatarUrl,
    String? theme,
  }) async {
    await _request(
      _baseUri.resolve('api/chats/$chatId'),
      method: 'PATCH',
      body: {'avatar_url': ?avatarUrl, 'theme': ?theme},
    );
  }

  Future<Map<String, dynamic>> loadChatAppearance(String chatId) =>
      _request(_baseUri.resolve('api/chats/$chatId/appearance'));

  Future<void> setChatTheme(String chatId, String theme) async {
    await _request(
      _baseUri.resolve('api/chats/$chatId/preferences'),
      method: 'PATCH',
      body: {'theme': theme},
    );
  }

  Future<void> deleteGroup(String chatId) async {
    await _request(_baseUri.resolve('api/chats/$chatId'), method: 'DELETE');
  }

  String get userId => _cachedUserId;
  String _cachedUserId = '';

  String get userName => _cachedUserName;
  String _cachedUserName = '';

  Future<String?> get _token => _storage.read(key: _tokenKey);

  Future<bool> hasStoredSession() async {
    final token = await _token;
    return token != null && token.isNotEmpty;
  }

  Future<void> register({
    required String name,
    required String phone,
    required String password,
  }) async {
    await _authenticate('api/auth/register', {
      'name': name,
      'phone': phone,
      'password': password,
    });
  }

  Future<void> login({required String phone, required String password}) async {
    await _authenticate('api/auth/login', {
      'phone': phone,
      'password': password,
    });
  }

  Future<void> _authenticate(String path, Map<String, String> body) async {
    final response = await _post(
      _baseUri.resolve(path),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final result = _decodeResponse(response);
    final token = result['access_token'] as String?;
    final user = result['user'];
    if (token == null || user is! Map<String, dynamic>) {
      throw const ApiException(
        'The server returned an invalid sign-in response',
      );
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
    final user = UserModel.fromJson(result);
    _cachedUserId = user.id;
    _cachedUserName = user.name;
    return user;
  }

  Future<UserModel> updateProfile({
    String? name,
    String? bio,
    String? avatarUrl,
  }) async {
    final result = await _request(
      _baseUri.resolve('api/profile'),
      method: 'PATCH',
      body: {'name': ?name, 'bio': ?bio, 'avatar_url': ?avatarUrl},
    );
    final user = UserModel.fromJson(result);
    _cachedUserName = user.name;
    await _storage.write(key: _userNameKey, value: user.name);
    return user;
  }

  Future<void> signOut() async {
    await _storage.deleteAll();
    _cachedUserId = '';
    _cachedUserName = '';
  }

  Future<List<UserModel>> loadUsers({String query = ''}) async {
    final uri = _baseUri
        .resolve('api/users')
        .replace(queryParameters: query.isEmpty ? null : {'query': query});
    final result = await _request(uri);
    final users = result['users'];
    if (users is! List) {
      throw const ApiException('The server returned an invalid users response');
    }
    return users
        .map((item) => UserModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<UserModel?> findUserByPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[+()\-\s.0-9]+$').hasMatch(phone) ||
        digits.length < 6 ||
        digits.length > 15) {
      throw const ApiException('Enter a valid phone number with country code');
    }

    final currentUser = await loadCurrentUser();
    if (currentUser.phone.replaceAll(RegExp(r'\D'), '') == digits) {
      return currentUser;
    }

    final users = await loadUsers(query: digits);
    for (final user in users) {
      if (user.phone.replaceAll(RegExp(r'\D'), '') == digits) {
        return user;
      }
    }
    return null;
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
    String avatarUrl = '',
  }) async {
    final result = await _request(
      _baseUri.resolve('api/chats/groups'),
      method: 'POST',
      body: {'name': name, 'members': members, 'avatar_url': avatarUrl},
    );
    return ChatModel.fromJson(result);
  }

  Future<ChatModel> createCommunity({
    required String name,
    required String type,
    required List<String> members,
    String avatarUrl = '',
  }) async {
    final result = await _request(
      _baseUri.resolve('api/chats/communities'),
      method: 'POST',
      body: {
        'name': name,
        'type': type,
        'members': members,
        'avatar_url': avatarUrl,
      },
    );
    return ChatModel.fromJson(result);
  }

  Future<List<MessageModel>> loadMessages(
    String chatId, {
    String? beforeId,
  }) async {
    final result = await _request(
      _baseUri
          .resolve('api/chats/$chatId/messages')
          .replace(
            queryParameters: beforeId == null ? null : {'before_id': beforeId},
          ),
    );
    final messages = result['messages'];
    if (messages is! List) {
      throw const ApiException(
        'The server returned an invalid messages response',
      );
    }
    return messages
        .map((item) => decodeMessage(item as Map<String, dynamic>))
        .toList();
  }

  Future<DateTime> clearChatHistory(String chatId) async {
    final result = await _request(
      _baseUri.resolve('api/chats/$chatId/messages'),
      method: 'DELETE',
    );
    return DateTime.parse(result['cleared_before'] as String);
  }

  Future<void> setChatMuted(String chatId, bool muted) async {
    await _request(
      _baseUri.resolve('api/chats/$chatId/preferences'),
      method: 'PATCH',
      body: {'muted': muted},
    );
  }

  Future<void> deleteInboxChat(String chatId) async {
    await _request(
      _baseUri.resolve('api/chats/$chatId/inbox'),
      method: 'DELETE',
    );
  }

  Future<String> uploadAttachment(File file, {String? name}) async {
    if (await file.length() > 15 * 1024 * 1024) {
      throw const ApiException('Choose a file smaller than 15 MB.');
    }
    final token = await _token;
    if (token == null || token.isEmpty) {
      throw const ApiException('Please sign in again.');
    }
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: name),
    });
    final response = await _sendRequest(
      () => _dio.postUri<dynamic>(
        _baseUri.resolve('api/files'),
        data: form,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          contentType: 'multipart/form-data',
        ),
      ),
    );
    final result = _decodeResponse(response);
    return result['media_url'] as String;
  }

  MessageModel decodeMessage(Map<String, dynamic> data) =>
      MessageModel.fromJson(data, mediaBaseUri: _baseUri);

  Future<List<StatusModel>> loadStatuses() async {
    final result = await _request(_baseUri.resolve('api/statuses'));
    final statuses = result['statuses'];
    if (statuses is! List) {
      throw const ApiException(
        'The server returned an invalid statuses response',
      );
    }
    return statuses
        .map((item) => StatusModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> markStatusViewed(String statusId) async {
    await _request(
      _baseUri.resolve('api/statuses/$statusId/view'),
      method: 'POST',
      body: const {},
    );
  }

  Future<void> updateStatusCaption(String statusId, String caption) async {
    await _request(
      _baseUri.resolve('api/statuses/$statusId'),
      method: 'PATCH',
      body: {'caption': caption},
    );
  }

  Future<void> deleteStatus(String statusId) async {
    await _request(
      _baseUri.resolve('api/statuses/$statusId'),
      method: 'DELETE',
    );
  }

  Future<StatusModel> createStatus({
    required String image,
    required bool isVideo,
    String caption = '',
  }) async {
    final result = await _request(
      _baseUri.resolve('api/statuses'),
      method: 'POST',
      body: {'image': image, 'is_video': isVideo, 'caption': caption},
    );
    return StatusModel.fromJson(result);
  }

  Future<WebSocketChannel> connectToChat(String chatId) async {
    final token = await _token;
    if (token == null || token.isEmpty) {
      throw const ApiException(
        'Your session has expired. Please sign in again.',
      );
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
    if (content.trim().isEmpty || content.runes.length > 5000) {
      throw const ApiException('Messages must contain 1 to 5000 characters.');
    }
    final clientId =
        '${DateTime.now().microsecondsSinceEpoch}-${_messageSequence++}';
    final pending = _pendingMessages.putIfAbsent(channel, () => {});
    final completion = Completer<void>();
    pending[clientId] = completion;
    try {
      channel.sink.add(
        jsonEncode({
          'type': 'message',
          'content': content,
          'client_id': clientId,
        }),
      );
      await completion.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw const ApiException(
            'No confirmation received. Check the conversation before retrying.',
          );
        },
      );
    } finally {
      pending.remove(clientId);
      if (pending.isEmpty) _pendingMessages.remove(channel);
    }
  }

  int _messageSequence = 0;
  final Map<WebSocketChannel, Map<String, Completer<void>>> _pendingMessages =
      {};

  void handleChatEvent(WebSocketChannel? channel, Map<String, dynamic> event) {
    final message = event['message'];
    final id =
        event['type'] == 'message' &&
            message is Map<String, dynamic> &&
            message['is_me'] == true
        ? message['client_id']
        : event['client_id'];
    final completion = _pendingMessages[channel]?[id];
    if (completion == null || completion.isCompleted) return;
    if (event['type'] == 'error') {
      completion.completeError(
        ApiException(
          event['error'] as String? ?? 'Message could not be saved.',
        ),
      );
    } else if (event['type'] == 'message') {
      completion.complete();
    }
  }

  void chatDisconnected(WebSocketChannel? channel) {
    final pending = _pendingMessages.remove(channel);
    if (pending == null) return;
    for (final completion in pending.values) {
      if (!completion.isCompleted) {
        completion.completeError(
          const ApiException(
            'Connection lost before confirmation. Check the conversation before retrying.',
          ),
        );
      }
    }
  }

  Future<List<CallModel>> loadCallHistory() async {
    final result = await _request(_baseUri.resolve('api/calls'));
    final calls = result['calls'];
    if (calls is! List) {
      throw const ApiException(
        'The server returned an invalid call history response',
      );
    }
    final currentUserId = await _loadStoredUserId();
    return calls
        .map(
          (item) => CallModel.fromJson(
            item as Map<String, dynamic>,
            currentUserId: currentUserId,
          ),
        )
        .toList();
  }

  Future<List<UserModel>> loadChatMembers(String chatId) async {
    final result = await _request(
      _baseUri.resolve('api/chats/$chatId/members'),
    );
    final members = result['members'];
    if (members is! List) {
      throw const ApiException(
        'The server returned an invalid chat members response',
      );
    }
    return members
        .map((item) => UserModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> startGroupCall({
    required String chatId,
    required CallMedia media,
    String status = 'started',
  }) async {
    final result = await _request(
      _baseUri.resolve('api/chats/$chatId/calls'),
      method: 'POST',
      body: {
        'kind': media == CallMedia.video ? 'video' : 'audio',
        'status': status,
      },
    );
    final calls = result['calls'];
    if (calls is! List || calls.isEmpty) {
      throw const ApiException(
        'The server returned an invalid group call response',
      );
    }
    return result;
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

  Future<List<CallModel>> loadIncomingCalls() async {
    final result = await _request(_baseUri.resolve('api/calls/incoming'));
    final calls = result['calls'];
    if (calls is! List) {
      throw const ApiException(
        'The server returned an invalid incoming calls response',
      );
    }
    final currentUserId = await _loadStoredUserId();
    return calls
        .map(
          (item) => CallModel.fromJson(
            item as Map<String, dynamic>,
            currentUserId: currentUserId,
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> loadCallSignals({
    required String callId,
    required int afterSequence,
  }) async {
    final uri = _baseUri
        .resolve('api/calls/$callId/signals')
        .replace(queryParameters: {'after': '$afterSequence'});
    final result = await _request(uri);
    final signals = result['signals'];
    if (signals is! List) {
      throw const ApiException(
        'The server returned an invalid call signals response',
      );
    }
    return {
      'status': result['status'] as String? ?? 'ended',
      'signals': signals.cast<Map<String, dynamic>>(),
    };
  }

  Future<void> endCall(String callId, {bool missed = false}) async {
    await _request(
      _baseUri.resolve('api/calls/$callId/end'),
      method: 'POST',
      body: {'status': missed ? 'missed' : 'ended'},
    );
  }

  Future<List<Map<String, dynamic>>> loadCallIceServers() async {
    final result = await _request(_baseUri.resolve('api/calls/ice-config'));
    final servers = result['ice_servers'];
    if (servers is! List) {
      throw const ApiException(
        'The server returned invalid WebRTC configuration',
      );
    }
    return servers.cast<Map<String, dynamic>>();
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
      throw const ApiException(
        'Your session has expired. Please sign in again.',
      );
    }
    final response = await switch (method) {
      'POST' => _post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ),
      'PATCH' => _sendJson(
        uri,
        method: method,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body ?? const {},
      ),
      'DELETE' => _sendRequest(
        () => _dio.deleteUri<dynamic>(
          uri,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        ),
      ),
      _ => _get(uri, headers: {'Authorization': 'Bearer $token'}),
    };
    return _decodeResponse(response);
  }

  Future<Response<dynamic>> _post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) {
    return _sendRequest(
      () => _dio.postUri<dynamic>(
        uri,
        data: jsonDecode(body),
        options: Options(headers: headers),
      ),
    );
  }

  Future<Response<dynamic>> _sendJson(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) {
    return _sendRequest(
      () => _dio.requestUri<dynamic>(
        uri,
        data: body,
        options: Options(method: method, headers: headers),
      ),
    );
  }

  Future<Response<dynamic>> _get(
    Uri uri, {
    required Map<String, String> headers,
  }) {
    return _sendRequest(
      () => _dio.getUri<dynamic>(uri, options: Options(headers: headers)),
    );
  }

  Future<Response<dynamic>> _sendRequest(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException(
        error.message ?? 'Could not connect to the backend API',
      );
    }
  }

  Map<String, dynamic> _decodeResponse(Response<dynamic> response) {
    Object? decoded;
    if (response.data is String) {
      try {
        decoded = jsonDecode(response.data as String);
      } on FormatException {
        throw ApiException(
          'The server returned an invalid response (${response.statusCode})',
        );
      }
    } else {
      decoded = response.data;
    }
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(
        'The server returned an invalid response (${response.statusCode})',
      );
    }
    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        decoded['error'] as String? ?? 'Request failed ($statusCode)',
        statusCode: statusCode,
      );
    }
    return decoded;
  }
}
