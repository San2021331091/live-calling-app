import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voxa/pages/camerapage.dart';
import 'package:voxa/pages/ChatPage.dart';
import 'package:voxa/pages/communitypage.dart';
import 'package:voxa/screens/calllistscreen.dart';
import 'package:voxa/screens/createcommunity.dart';
import 'package:voxa/screens/creategroup.dart';
import 'package:voxa/screens/myprofilescreen.dart';
import 'package:voxa/screens/searchscreen.dart';
import 'package:voxa/screens/status_screen.dart';
import 'package:voxa/model/call_model.dart';
import 'package:voxa/screens/webrtc_call_screen.dart';
import 'package:voxa/screens/loginscreen.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/media/media_result.dart';
import 'package:voxa/services/status_upload_service.dart';
import 'package:voxa/services/push_notification_service.dart';
import 'package:voxa/pages/groupchatpage.dart';
import 'package:voxa/pages/individualpage.dart';

// HomeScreen widget with TabBar and AppBar
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

// State class for HomeScreen
class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey<StatusScreenState> _statusScreenKey =
      GlobalKey<StatusScreenState>();
  late TabController tabController;
  Timer? _incomingCallTimer;
  final Set<String> _seenIncomingCallIds = {};
  bool _checkingIncomingCalls = false;
  bool _showingIncomingDialog = false;
  bool _incomingErrorShown = false;
  bool _uploadingStatus = false;
  StreamSubscription<PushEvent>? _pushSubscription;
  bool _openingPush = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pushSubscription = PushNotificationService.instance.events.listen(
      (event) => unawaited(_handlePush(event)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(PushNotificationService.instance.connectSession());
    });
    tabController = TabController(length: 4, vsync: this);
    tabController.addListener(_handleTabChanged);
    _incomingCallTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_checkIncomingCalls()),
    );
    unawaited(_checkIncomingCalls());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushSubscription?.cancel();
    _incomingCallTimer?.cancel();
    tabController.removeListener(_handleTabChanged);
    tabController.dispose();
    super.dispose();
  }

  Future<void> _checkIncomingCalls() async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (_checkingIncomingCalls || _showingIncomingDialog) return;
    _checkingIncomingCalls = true;
    try {
      final calls = await ApiClient.instance.loadIncomingCalls();
      _incomingErrorShown = false;
      for (final call in calls) {
        if (_seenIncomingCallIds.contains(call.id)) continue;
        _seenIncomingCallIds.add(call.id);
        if (!mounted) return;
        await _promptForCall(call);
        break;
      }
    } on ApiException catch (error) {
      if (mounted && !_incomingErrorShown) {
        _incomingErrorShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Incoming call check failed: ${error.message}'),
          ),
        );
      }
    } finally {
      _checkingIncomingCalls = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(PushNotificationService.instance.sync());
      unawaited(_checkIncomingCalls());
    }
  }

  Future<void> _handlePush(PushEvent event) async {
    if (!mounted || !event.isFor(ApiClient.instance.userId)) return;
    if (event.isCall) {
      if (!event.opened) {
        await _checkIncomingCalls();
        return;
      }
      if (_showingIncomingDialog || _checkingIncomingCalls) return;
      _checkingIncomingCalls = true;
      try {
        final calls = await ApiClient.instance.loadIncomingCalls();
        if (!mounted || !event.isFor(ApiClient.instance.userId)) return;
        final matching = calls.where((call) => call.id == event.callId);
        if (matching.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This call is no longer ringing.')),
          );
        } else {
          final call = matching.first;
          _seenIncomingCallIds.add(call.id);
          await _promptForCall(call);
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not check this call. Please retry from Calls.',
              ),
            ),
          );
        }
      } finally {
        _checkingIncomingCalls = false;
      }
      return;
    }
    if (_openingPush) return;
    _openingPush = true;
    try {
      final chats = await ApiClient.instance.loadChats();
      if (!mounted || !event.isFor(ApiClient.instance.userId)) return;
      final matching = chats.where((chat) => chat.id == event.chatId);
      if (matching.isEmpty) return;
      final chat = matching.first;
      if (event.opened) {
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => chat.isGroup == true
                  ? GroupChatPage(group: chat)
                  : IndividualPage(chatModel: chat),
            ),
          ),
        );
      } else if (!chat.muted && ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${chat.name}: ${chat.currentMessage ?? "New message"}',
            ),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () {
                unawaited(_handlePush(PushEvent(event.data, opened: true)));
              },
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && event.opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open this conversation. Please retry from Chats.',
            ),
          ),
        );
      }
    } finally {
      _openingPush = false;
    }
  }

  Future<void> _showNotificationSettings() async {
    final push = PushNotificationService.instance;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Notifications'),
        content: ValueListenableBuilder<String>(
          valueListenable: push.status,
          builder: (_, value, _) => Text(value),
        ),
        actions: [
          TextButton(
            onPressed: () => unawaited(push.sync()),
            child: const Text('Retry'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await push.openSettings();
              } catch (_) {
                /* Device may not support settings links. */
              }
            },
            child: const Text('Device settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _publishStatusMedia(MediaResult media) async {
    if (_uploadingStatus) return;
    setState(() => _uploadingStatus = true);
    try {
      await StatusUploadService.publish(media);
      if (mounted) {
        final statusScreen = _statusScreenKey.currentState;
        if (statusScreen != null) await statusScreen.refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Your update is live')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _uploadingStatus = false);
    }
  }

  Future<void> _promptForCall(CallModel call) async {
    _showingIncomingDialog = true;
    final navigator = Navigator.of(context);
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('Incoming ${call.media.name} call'),
        content: Text('${call.name} is calling you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    _showingIncomingDialog = false;
    if (!mounted) return;
    if (accept == true) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => WebRtcCallScreen(
            callId: call.id,
            peerId: call.peerId ?? '',
            peerName: call.name,
            peerAvatar: call.avatar,
            media: call.media,
            isIncoming: true,
          ),
        ),
      );
    } else {
      try {
        await ApiClient.instance.endCall(call.id, missed: true);
      } on ApiException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not decline call: ${error.message}')),
          );
        }
      }
    }
  }

  void _handleTabChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openCamera() async {
    final media = await Navigator.of(
      context,
    ).push<MediaResult>(MaterialPageRoute(builder: (_) => const CameraPage()));
    if (media != null && mounted) await _publishStatusMedia(media);
  }

  Future<void> _handleMenu(String value) async {
    Widget? page;
    switch (value) {
      case 'group':
        page = const CreateGroup();
      case 'community':
        page = const CreateNewCommunity();
      case 'profile':
        page = const MyProfileScreen();
      case 'notifications':
        await _showNotificationSettings();
        return;
      case 'signout':
        final navigator = Navigator.of(context);
        try {
          await ApiClient.instance.signOut();
        } on ApiException catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.message)));
          }
          return;
        }
        if (!mounted) return;
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        return;
    }
    if (page != null && mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => page!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF17251F),
        iconTheme: const IconThemeData(color: Color(0xFF17251F)),
        actionsIconTheme: const IconThemeData(color: Color(0xFF17251F)),
        title: const Text(
          'Voxa',
          style: TextStyle(
            color: Color(0xFF168A62),
            fontSize: 27,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Camera update',
            onPressed: _uploadingStatus ? null : _openCamera,
            icon: _uploadingStatus
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt_outlined),
          ),
          IconButton(
            tooltip: 'Find people',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'group', child: Text('New group')),
              PopupMenuItem(value: 'community', child: Text('New community')),
              PopupMenuItem(value: 'profile', child: Text('My profile')),
              PopupMenuItem(
                value: 'notifications',
                child: Text('Notifications'),
              ),
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: tabController,
        children: [
          const ChatPage(),
          StatusScreen(key: _statusScreenKey),
          const CommunityPage(),
          const CallListScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFD9F4E4),
        selectedIndex: tabController.index,
        onDestinationSelected: tabController.animateTo,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.update_rounded),
            label: 'Updates',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'Communities',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call_rounded),
            label: 'Calls',
          ),
        ],
      ),
    );
  }
}
