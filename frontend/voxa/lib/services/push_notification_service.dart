import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voxa/services/api_client.dart';

@pragma('vm:entry-point')
Future<void> handleBackgroundPush(RemoteMessage message) async {
  await Firebase.initializeApp();
  // FCM displays the notification payload while the app is in the background.
  // Navigation and authenticated call checks happen only after the user opens it.
}

class PushEvent {
  const PushEvent(this.data, {required this.opened});
  final Map<String, dynamic> data;
  final bool opened;
  bool get isCall => data['type'] == 'incoming_call';
  String get chatId => data['chat_id'] as String? ?? '';
  String get callId => data['call_id'] as String? ?? '';
  bool isFor(String userId) =>
      userId.isNotEmpty &&
      data['recipient_id'] == userId &&
      (isCall
          ? callId.isNotEmpty
          : data['type'] == 'chat_message' && chatId.isNotEmpty);
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();
  static const _native = MethodChannel('com.voxa/notifications');
  final _events = StreamController<PushEvent>.broadcast();
  final status = ValueNotifier<String>(
    'Notifications are not configured in this build.',
  );
  Stream<PushEvent> get events => _events.stream;
  bool _initialized = false;
  bool _suspended = false;
  bool registered = false;
  Future<void>? _syncing;
  PushEvent? _pendingOpen;
  final Set<String> _seen = {};

  Future<void> initialize() async {
    ApiClient.instance.beforeSignOut = unregister;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      status.value = 'Push notifications are available on mobile builds.';
      return;
    }
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(handleBackgroundPush);
      // Foreground UI is handled once in HomeScreen on both platforms.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: false,
          );
      FirebaseMessaging.onMessage.listen((message) => _receive(message, false));
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _receive(message, true),
      );
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) async {
          // A rotation during a registration must schedule a second registration.
          await _syncing;
          await sync();
        },
        onError: (Object _) {
          registered = false;
          status.value =
              'Notification registration needs a connection. Retry when online.';
        },
      );
      _initialized = true;
      status.value = 'Sign in to enable notifications.';
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pendingOpen = PushEvent(initial.data, opened: true);
    } catch (_) {
      status.value = 'Notifications are not configured in this build.';
    }
  }

  void _receive(RemoteMessage message, bool opened) {
    if (_suspended) return;
    final event = PushEvent(message.data, opened: opened);
    if (opened && !_events.hasListener) {
      _pendingOpen = event;
      return;
    }
    if (!event.isFor(ApiClient.instance.userId)) return;
    final id =
        '${opened ? "open" : "receive"}:${message.data['event_id'] ?? message.messageId}';
    if (!_seen.add(id)) return;
    if (_seen.length > 200) _seen.remove(_seen.first);
    _events.add(event);
  }

  Future<void> connectSession() async {
    _suspended = false;
    final pending = _pendingOpen;
    _pendingOpen = null;
    if (pending != null && pending.isFor(ApiClient.instance.userId)) {
      _events.add(pending);
    }
    await sync();
  }

  Future<String> _installationId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('push_installation_id');
    if (id != null) return id;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    id =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await prefs.setString('push_installation_id', id);
    return id;
  }

  Future<void> sync() {
    if (!_initialized || _suspended || ApiClient.instance.userId.isEmpty) {
      return Future.value();
    }
    return _syncing ??= _register().whenComplete(() => _syncing = null);
  }

  Future<void> _register() async {
    final userId = ApiClient.instance.userId;
    try {
      final prefs = await SharedPreferences.getInstance();
      var permission = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (prefs.getBool('push_permission_asked') != true) {
        await prefs.setBool('push_permission_asked', true);
        permission = await FirebaseMessaging.instance.requestPermission();
      }
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        registered = false;
        status.value =
            'Notifications are off. Enable them in your device settings.';
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        throw const ApiException(
          'Notification token is not ready. Retry shortly.',
        );
      }
      final id = await _installationId();
      if (_suspended || ApiClient.instance.userId != userId) return;
      await ApiClient.instance.registerPushDevice(
        id,
        token,
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      );
      registered = true;
      status.value =
          'Notifications are enabled. Muted chats do not send message alerts.';
    } on ApiException catch (error) {
      registered = false;
      status.value = error.statusCode == 503
          ? 'Notifications are not configured on the server.'
          : 'Could not register notifications. Check your connection and retry.';
    } catch (_) {
      registered = false;
      status.value =
          'Could not register notifications. Check Firebase setup and retry.';
    }
  }

  Future<void> unregister() async {
    _suspended = true;
    await _syncing;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('push_installation_id');
    if (id != null) {
      bool serverRemoved = false;
      bool tokenRemoved = false;
      try {
        await ApiClient.instance.unregisterPushDevice(id);
        serverRemoved = true;
      } catch (_) {
        /* Token deletion can still revoke delivery while API is offline. */
      }
      if (_initialized) {
        try {
          await FirebaseMessaging.instance.deleteToken();
          tokenRemoved = true;
        } catch (_) {
          /* Server revocation is sufficient if Firebase is offline. */
        }
      }
      if (!serverRemoved && !tokenRemoved) {
        _suspended = false;
        throw const ApiException(
          'Connect to the internet to disable notifications before signing out.',
        );
      }
    }
    registered = false;
    _pendingOpen = null;
    _seen.clear();
    status.value = 'Sign in to enable notifications.';
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _native.invokeMethod<void>('clear');
      } catch (_) {
        /* Best effort. */
      }
    }
  }

  Future<void> openSettings() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _native.invokeMethod<void>('settings');
    }
  }
}
