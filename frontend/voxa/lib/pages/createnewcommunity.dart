import 'package:voxa/customui/avatar_photo.dart';
import 'package:flutter/material.dart';
import 'package:voxa/customui/gradient_app_bar_background.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/model/user_model.dart';
import 'package:voxa/services/api_client.dart';

class AddCommunityInfo extends StatefulWidget {
  final String communityType;

  const AddCommunityInfo({super.key, required this.communityType});

  @override
  State<AddCommunityInfo> createState() => _AddCommunityInfoState();
}

class _AddCommunityInfoState extends State<AddCommunityInfo> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> selectedGroups = {}; // Track selected groups
  List<UserModel> _users = [];
  bool _isLoading = true;
  bool _isCreating = false;
  bool _photoBusy = false;
  String _avatarUrl = '';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      _users = await ApiClient.instance.loadUsers();
      _loadError = null;
    } on ApiException catch (error) {
      _loadError = error.message;
    } catch (_) {
      _loadError = 'Could not load Voxa users.';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createCommunity() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || selectedGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            name.isEmpty
                ? 'Enter a community name.'
                : 'Select at least one Voxa participant.',
          ),
        ),
      );
      return;
    }
    setState(() => _isCreating = true);
    try {
      final community = await ApiClient.instance.createCommunity(
        name: name,
        avatarUrl: _avatarUrl,
        type: widget.communityType,
        members: selectedGroups.toList(),
      );
      if (mounted) Navigator.pop<ChatModel>(context, community);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not create community. Check your connection.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: const Text(
          "New Community",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              "Community Type: ${widget.communityType}",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF168A62),
              ),
            ),
            const SizedBox(height: 30),

            AvatarPhotoEditor(
              url: _avatarUrl,
              radius: 48,
              icon: Icons.groups_rounded,
              enabled: !_isCreating,
              onBusyChanged: (busy) {
                if (mounted) setState(() => _photoBusy = busy);
              },
              onSave: (url) async {
                if (mounted) setState(() => _avatarUrl = url);
              },
            ),
            const SizedBox(height: 20),

            // Community Name Input
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Community Name",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(Icons.group),
              ),
            ),
            const SizedBox(height: 20),

            // List of Groups
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Select Participants",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF17251F),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _loadError != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_loadError!),
                                TextButton(
                                  onPressed: _loadUsers,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : _users.isEmpty
                        ? const Center(
                            child: Text(
                              'No other Voxa accounts to invite yet.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: _users.length,
                            itemBuilder: (context, index) {
                              final user = _users[index];
                              final isSelected = selectedGroups.contains(
                                user.id,
                              );
                              return ListTile(
                                leading: AvatarPhoto(url: user.avatarUrl),
                                title: Text(user.name),
                                subtitle: Text(user.phone),
                                trailing: Checkbox(
                                  value: isSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        selectedGroups.add(user.id);
                                      } else {
                                        selectedGroups.remove(user.id);
                                      }
                                    });
                                  },
                                ),
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      selectedGroups.remove(user.id);
                                    } else {
                                      selectedGroups.add(user.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),

            // Next Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCreating || _photoBusy ? null : _createCommunity,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF168A62),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isCreating
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Create Community",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
