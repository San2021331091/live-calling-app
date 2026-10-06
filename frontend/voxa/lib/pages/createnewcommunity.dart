import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  File? _communityImage;
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final Set<String> selectedGroups = {}; // Track selected groups
  List<UserModel> _users = [];
  bool _isLoading = true;
  bool _isCreating = false;
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

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 80,
    );
    if (pickedFile != null) {
      setState(() {
        _communityImage = File(pickedFile.path);
      });
    }
  }

  void _showImageSourceOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                "Select Image Source",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildImageOption(
                    icon: Icons.camera_alt,
                    label: "Camera",
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  _buildImageOption(
                    icon: Icons.photo_library,
                    label: "Gallery",
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF168A62),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: Color(0xFF17251F)),
        title: const Text(
          "New Community",
          style: TextStyle(color: Color(0xFF17251F), fontWeight: FontWeight.w700),
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF5F7F5), Color(0xFFF5F7F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
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

            // Community Image
            GestureDetector(
              onTap: _showImageSourceOptions,
              child: CircleAvatar(
                radius: 60,
                backgroundColor: const Color(0xFFDCE9E1),
                backgroundImage: _communityImage != null
                    ? FileImage(_communityImage!)
                    : null,
                child: _communityImage == null
                    ? const Icon(
                        Icons.camera_alt,
                        size: 40,
                        color: Color(0xFF168A62),
                      )
                    : null,
              ),
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
                                  leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFE8F3ED),
                                  child: Icon(Icons.person, color: Color(0xFF168A62)),
                                ),
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
                onPressed: _isCreating ? null : _createCommunity,
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
