import 'package:flutter/material.dart';
import 'package:voxa/customui/customcard.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/screens/selectcontact.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<StatefulWidget> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  List<ChatModel> chats = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      chats = await ApiClient.instance.loadChats();
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Could not load chats. Check your connection.';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (builder) => const SelectContact()),
            ).then((_) => _loadChats());
        },
        backgroundColor: const Color(0xFF168A62),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Messages', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF17251F), letterSpacing: -0.4)),
                SizedBox(height: 4),
                Text('Your conversations, all in one place', style: TextStyle(fontSize: 11, color: Color(0xFF75827B))),
              ])),
              if (chats.isNotEmpty) Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFE6F3ED), borderRadius: BorderRadius.circular(20)),
                child: Text('${chats.length}', style: const TextStyle(color: Color(0xFF168A62), fontWeight: FontWeight.w700, fontSize: 11)),
              ),
            ]),
          ),
          Expanded(child: _isLoading && chats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && chats.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadChats,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              color: const Color(0xFF168A62),
              onRefresh: _loadChats,
              child: chats.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 95),
                        Icon(Icons.forum_outlined, size: 54, color: Colors.green.shade200),
                        const SizedBox(height: 14),
                        const Center(child: Text('Your inbox is quiet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF26362E)))),
                        const SizedBox(height: 6),
                        const Center(child: Text('Start a conversation to see it here.', style: TextStyle(fontSize: 11, color: Color(0xFF75827B)))),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 4, bottom: 90),
                      itemCount: chats.length,
                      itemBuilder: (context, index) =>
                          CustomCard(chatModel: chats[index]),
                    ),
          )),
        ],
      ),
    );
  }
}
