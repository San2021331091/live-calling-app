import 'package:voxa/customui/avatar_photo.dart';
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
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E4D45),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0E4D45), Color(0xFF123E39)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          "Communities",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _createCommunity,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF15A26E), Color(0xFF0E4D45)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1D0F2B2A),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white24,
                  child: Icon(
                    Icons.groups_2_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Create a community",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Bring members together in one space",
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  onPressed: _createCommunity,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              "Your communities",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Color(0xFF2D3D36),
              ),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(_error!)),
                  IconButton(
                    onPressed: _loadCommunities,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            )
          else if (communities.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'No communities yet. Create your first space to get started.',
                style: TextStyle(color: Color(0xFF596A62)),
              ),
            )
          else
            ...communities.map(
              (community) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0D17251F),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AvatarPhoto(url: community.img, icon: Icons.groups),
                  title: Text(
                    community.name.isEmpty ? 'Community' : community.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF26362E),
                    ),
                  ),
                  subtitle: Text(
                    community.about ?? 'Community chat',
                    style: const TextStyle(
                      color: Color(0xFF75827B),
                      fontSize: 11,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF168A62),
                  ),
                  onTap: () => _openCommunity(community),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
