import 'package:flutter/material.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/pages/groupchatpage.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/screens/createcommunity.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  List<ChatModel> communities = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCommunities();
  }

  Future<void> _loadCommunities() async {
    try {
      communities = (await ApiClient.instance.loadChats())
          .where((chat) => chat.isCommunity == true)
          .toList();
      _error = null;
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Could not load communities.';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createCommunity() async {
    final community = await Navigator.push<ChatModel>(
      context,
      MaterialPageRoute(builder: (_) => const CreateNewCommunity()),
    );
    if (community == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupChatPage(group: community)),
    );
    if (mounted) _loadCommunities();
  }

  void _openCommunity(ChatModel community) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupChatPage(group: community)),
    ).then((_) => _loadCommunities());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xff075E54),
        title: const Text(
          "My Communities",
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createCommunity,
          ),
        ],
      ),
      body: ListView(
        children: [
          // Top card: Start a Community
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0xff25D366),
                  child: Icon(Icons.add, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Start a Community",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Bring your groups together",
                        style: TextStyle(fontSize: 14, color: Colors.pink),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _createCommunity,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "Your Communities",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            ListTile(
              title: Text(_error!),
              trailing: IconButton(
                onPressed: _loadCommunities,
                icon: const Icon(Icons.refresh),
              ),
            )
          else if (communities.isEmpty)
            const ListTile(
              title: Text('No communities yet'),
              subtitle: Text('Create one and invite other Voxa users.'),
            )
          else
            ...communities.map(
              (community) => Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xff25D366),
                    radius: 24,
                    child: Icon(Icons.groups, color: Colors.white),
                  ),
                  title: Text(
                    community.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.deepOrange),
                  ),
                  subtitle: Text(
                    community.about ?? 'Community chat',
                    style: const TextStyle(color: Colors.purple,fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openCommunity(community),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


