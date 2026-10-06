import 'package:flutter/material.dart';
import 'package:voxa/pages/addnewgroup.dart';
import 'package:voxa/model/user_model.dart';
import 'package:voxa/services/api_client.dart';

class CreateGroup extends StatefulWidget {
  const CreateGroup({super.key});

  @override
  State<CreateGroup> createState() => _CreateGroupState();
}

class _CreateGroupState extends State<CreateGroup> {
  List<UserModel> contacts = [];
  bool _isLoading = true;
  String? _error;

  final Set<String> selectedUsers = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      contacts = await ApiClient.instance.loadUsers();
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Could not load Voxa accounts.';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _continue() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddNewGroup(
          members: contacts
              .where((user) => selectedUsers.contains(user.id))
              .toList(),
        ),
      ),
    );
    if (created != null && mounted) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: Color(0xFF35433C)),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("New group",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,color: Color(0xFF17251F))),
            SizedBox(height: 2),
            Text("Add participants",
                style: TextStyle(fontSize: 11, color: Color(0xFF75827B))),
          ],
        ),
        backgroundColor: const Color(0xFFF9FBF9),
      ),

      floatingActionButton: selectedUsers.isNotEmpty
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF168A62),
              onPressed: _continue,
              child: const Icon(Icons.arrow_forward, color: Colors.white),
            )
          : null,

      body: Column(
        children: [
          if (selectedUsers.isNotEmpty) _selectedUsersBar(),
          Expanded(child: _contactsList()),
        ],
      ),
    );
  }

  Widget _selectedUsersBar() {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: selectedUsers.map((name) {
          final user = contacts.firstWhere((item) => item.id == name);
          return Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                Stack(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFFE8F3ED),
                      child: Icon(Icons.person, color: Color(0xFF168A62)),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => selectedUsers.remove(user.id));
                        },
                        child: const CircleAvatar(
                          radius: 10,
                          backgroundColor: Color(0xFFDB6B6B),
                          child:
                              Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(user.name,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF35433C))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _contactsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (contacts.isEmpty) {
      return const Center(child: Text('No other Voxa accounts to add yet.'));
    }
    return ListView.builder(
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final isSelected = selectedUsers.contains(contact.id);

        return ListTile(
          leading: Stack(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFE8F3ED),
                child: Icon(Icons.person, color: Color(0xFF168A62)),
              ),
              if (isSelected)
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: Color(0xFF168A62),
                    child:
                        Icon(Icons.check, size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
          title: Text(contact.name,
              style: const TextStyle(
                  color: Color(0xFF17251F),
                  fontWeight: FontWeight.w600)),
          subtitle: Text(contact.phone,
              style: const TextStyle(
                  color: Color(0xFF75827B),
                  fontWeight: FontWeight.w600,
                  )),
          onTap: () {
            setState(() {
              isSelected
                  ? selectedUsers.remove(contact.id)
                  : selectedUsers.add(contact.id);
            });
          },
        );
      },
    );
  }
}
