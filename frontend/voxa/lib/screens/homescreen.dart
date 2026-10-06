import 'dart:async';

import 'package:flutter/material.dart';
import 'package:voxa/pages/camerapage.dart';
import 'package:voxa/pages/chatpage.dart';
import 'package:voxa/colors/colors.dart';
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

// HomeScreen widget with TabBar and AppBar
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

// State class for HomeScreen
class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController tabController;
  Timer? _incomingCallTimer;
  final Set<String> _seenIncomingCallIds = {};
  bool _checkingIncomingCalls = false;
  bool _showingIncomingDialog = false;
  bool _incomingErrorShown = false;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 4, vsync: this);
    _incomingCallTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_checkIncomingCalls()),
    );
    unawaited(_checkIncomingCalls());
  }

  @override
  void dispose() {
    _incomingCallTimer?.cancel();
    tabController.dispose();
    super.dispose();
  }

  Future<void> _checkIncomingCalls() async {
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
          SnackBar(content: Text('Incoming call check failed: ${error.message}')),
        );
      }
    } finally {
      _checkingIncomingCalls = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(110),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColor.dartTealGreen, AppColor.lightGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // AppBar content
                ListTile(
                  title: const Text(
                    "Voxa",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.white),
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
                        },
                      ),
                      PopupMenuButton<String>(
                        color: AppColor.dartTealGreen,
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        itemBuilder: (BuildContext context) => [
                          PopupMenuItem(
                            value: "New Group",
                            child: const Text(
                              "New Group",
                              style: TextStyle(color: Colors.white),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CreateGroup(),
                                ),
                              );
                            },
                          ),

                          PopupMenuItem(
                            value: "New Community",
                            child: const Text(
                              "New Community",
                              style: TextStyle(color: Colors.white),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CreateNewCommunity(),
                                ),
                              );
                            },
                          ),
                          PopupMenuItem(
                            value: "My Profile",
                            child: const Text(
                              "My profile",
                              style: TextStyle(color: Colors.white),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MyProfileScreen()
                                ),
                              );
                            },
                          ),

                          PopupMenuItem(
                            value: "My communities",
                            child: const Text(
                              "My Communities",
                              style: TextStyle(color: Colors.white),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CommunityPage(),
                                ),
                              );
                            },
                          ),
                          PopupMenuItem(
                            value: "Sign out",
                            child: const Text(
                              "Sign out",
                              style: TextStyle(color: Colors.white),
                            ),
                            onTap: () async {
                              final navigator = Navigator.of(context);
                              await ApiClient.instance.signOut();
                              if (!mounted) return;
                              navigator.pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                                (_) => false,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // TabBar
                TabBar(
                  controller: tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  tabs: const [
                    Tab(icon: Icon(Icons.camera_alt)),
                    Tab(text: "Chats"),
                    Tab(text: "Status"),
                    Tab(text: "Calls"),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: [
          const CameraPage(),
          const ChatPage(),
          const StatusScreen(),
          const CallListScreen(),
        ],
      ),
    );
  }
}
