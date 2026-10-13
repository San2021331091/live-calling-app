// ignore_for_file: file_names
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:voxa/customui/customcard.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/services/push_notification_service.dart';
import 'package:voxa/screens/selectcontact.dart';

enum ChatFilter { all, direct, groups }

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  List<ChatModel> chats = [];
  bool _isLoading = true;
  bool _fetching = false;
  String? _error;
  String _query = '';
  ChatFilter _filter = ChatFilter.all;
  Timer? _refreshTimer;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChats();
    _startRefresh();
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadChats(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadChats();
      _startRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    if (_fetching || !mounted) {
      return;
    }
    _fetching = true;
    try {
      final result = await ApiClient.instance.loadChats();
      if (mounted) {
        if (!_isLoading &&
            !PushNotificationService.instance.registered &&
            ModalRoute.of(context)?.isCurrent == true) {
          final previous = {for (final chat in chats) chat.id: chat};
          final incoming = result
              .where(
                (chat) =>
                    !chat.muted &&
                    chat.lastSenderId != ApiClient.instance.userId &&
                    chat.lastMessageAt != null &&
                    chat.lastMessageAt!.isAfter(
                      previous[chat.id]?.lastMessageAt ??
                          DateTime.now().subtract(const Duration(seconds: 10)),
                    ),
              )
              .toList();
          if (incoming.isNotEmpty) {
            final chat = incoming.first;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${chat.name}: ${chat.currentMessage ?? "New message"}',
                ),
              ),
            );
          }
        }
        setState(() {
          chats = result;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiException
              ? error.message
              : 'Could not refresh chats. Check your connection.';
        });
      }
    } finally {
      _fetching = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<ChatModel> get _visibleChats => chats.where((chat) {
    final matchesFilter = switch (_filter) {
      ChatFilter.all => true,
      ChatFilter.direct => chat.isGroup != true,
      ChatFilter.groups => chat.isGroup == true,
    };
    final query = _query.toLowerCase().trim();
    return matchesFilter &&
        (query.isEmpty ||
            chat.name.toLowerCase().contains(query) ||
            (chat.currentMessage ?? '').toLowerCase().contains(query));
  }).toList();

  @override
  Widget build(BuildContext context) {
    final visible = _visibleChats;
    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        tooltip: 'New chat',
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SelectContact()));
          if (mounted) await _loadChats();
        },
        backgroundColor: const Color(0xFF168A62),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_comment_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                for (final filter in ChatFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (filter) {
                        ChatFilter.all => 'All',
                        ChatFilter.direct => 'Direct',
                        ChatFilter.groups => 'Groups',
                      }),
                      selected: _filter == filter,
                      showCheckmark: false,
                      selectedColor: const Color(0xFFD9F4E4),
                      onSelected: (_) => setState(() => _filter = filter),
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              leading: const Icon(Icons.cloud_off_outlined),
              actions: [
                TextButton(onPressed: _loadChats, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadChats,
                    child: visible.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              const Icon(
                                Icons.forum_outlined,
                                size: 52,
                                color: Color(0xFF9BB7A9),
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  chats.isEmpty
                                      ? 'No conversations yet'
                                      : 'No matching conversations',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                  chats.isEmpty
                                      ? 'Start a chat with someone on Voxa.'
                                      : 'Try another search or filter.',
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: visible.length,
                            itemBuilder: (_, index) => CustomCard(
                              chatModel: visible[index],
                              onChanged: _loadChats,
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
