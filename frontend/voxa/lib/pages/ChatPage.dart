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
      floatingActionButton: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              Color.fromARGB(255, 11, 187, 17),
              Color.fromARGB(255, 16, 134, 230),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (builder) => const SelectContact()),
            ).then((_) => _loadChats());
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.chat, color: Colors.white),
        ),
      ),
      body: _isLoading && chats.isEmpty
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
              onRefresh: _loadChats,
              child: chats.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 180),
                        Center(child: Text('No chats yet. Start a conversation.')),
                      ],
                    )
                  : ListView.builder(
                      itemCount: chats.length,
                      itemBuilder: (context, index) =>
                          CustomCard(chatModel: chats[index]),
                    ),
      ),
    );
  }
}
