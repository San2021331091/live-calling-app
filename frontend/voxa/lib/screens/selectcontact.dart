import 'package:flutter/material.dart';
import 'package:voxa/colors/colors.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/model/user_model.dart';
import 'package:voxa/pages/groupchatpage.dart';
import 'package:voxa/pages/individualpage.dart';
import 'package:voxa/pages/contactpage.dart';
import 'package:voxa/pages/createcontactpage.dart';
import 'package:voxa/screens/createcommunity.dart';
import 'package:voxa/screens/creategroup.dart';
import 'package:voxa/services/api_client.dart';

class SelectContact extends StatefulWidget {
  const SelectContact({super.key});

  @override
  State<SelectContact> createState() => _SelectContactState();
}

class _SelectContactState extends State<SelectContact> {
  List<UserModel> users = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      users = await ApiClient.instance.loadUsers();
    } on ApiException catch (exception) {
      error = exception.message;
    } catch (_) {
      error = 'Could not load Voxa users. Check your connection.';
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _openChat(UserModel user) async {
    try {
      final chat = await ApiClient.instance.createDirectChat(userId: user.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IndividualPage(chatModel: chat)),
      );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (exception) {
      if (mounted) _showError(exception.message);
    } catch (_) {
      if (mounted) _showError('Could not start this chat. Check your connection.');
    }
  }

  Future<void> _createGroup() async {
    final group = await Navigator.push<ChatModel>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroup()),
    );
    if (group == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupChatPage(group: group)),
    );
    if (mounted) Navigator.pop(context);
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
    if (mounted) Navigator.pop(context);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Select contact",
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
            SizedBox(height: 2),
            Text(
              isLoading ? 'Loading accounts...' : '${users.length} Voxa accounts',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            color: Colors.white,
            onPressed: _loadUsers,
          ),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            color: AppColor.dartTealGreen,
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              switch (value) {
                case 'invite':
                  print('Invite a friend');
                  break;
                case 'contacts':
                {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactPage()));
                }
                  break;
                case 'refresh':
                  print('Refresh');
                  break;
                case 'help':
                  print('Help');
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'invite',
                child: Text(
                  'Invite a friend',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              PopupMenuItem(
                value: 'contacts',
                child: Text('Contacts', style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: Text('Refresh', style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 'help',
                child: Text('Help', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColor.dartTealGreen, AppColor.lightGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),

      body: ListView(
        children: [
          _topTile(
            icon: Icons.group,
            title: "New group",
            onTap: _createGroup,
          ),
          _topTile(icon: Icons.person_add, title: "New contact", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateContactPage()));
          }),
          _topTile(
            icon: Icons.group_add_sharp,
            title: "New Community",
            onTap: _createCommunity,
          ),
          const Divider(),

          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            ListTile(
              title: Text(error!),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadUsers,
              ),
            )
          else if (users.isEmpty)
            const ListTile(
              title: Text('No other Voxa accounts yet'),
              subtitle: Text('Invite someone to create an account first.'),
            )
          else
            ...users.map(_userTile),
        ],
      ),
    );
  }

  Widget _topTile({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColor.lightGreen,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.red,
          ),
        ),
      ),
    );
  }

  Widget _userTile(UserModel user) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.blue,
        child: Icon(Icons.person, color: Colors.white),
      ),
      title: Text(user.name),
      subtitle: Text(user.phone),
      onTap: () => _openChat(user),
    );
  }
}
