import 'dart:io';
import 'package:flutter/material.dart';
import 'package:voxa/customui/gradient_app_bar_background.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/model/user_model.dart';
import 'package:voxa/services/api_client.dart';

class AddNewGroup extends StatefulWidget {
  final List<UserModel> members;

  const AddNewGroup({
    super.key,
    required this.members,
  });

  @override
  State<AddNewGroup> createState() => _AddNewGroupState();
}

class _AddNewGroupState extends State<AddNewGroup> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  File? _groupImage;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a group name.')),
      );
      return;
    }
    setState(() => _isCreating = true);
    try {
      final group = await ApiClient.instance.createGroup(
        name: name,
        members: widget.members.map((member) => member.id).toList(),
      );
      if (mounted) Navigator.pop<ChatModel>(context, group);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create group. Check your connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  /// WhatsApp-like states
  String disappearingMessage = "Off";
  bool onlyAdminsEditInfo = false;
  bool onlyAdminsSendMessage = false;

  /// Open Camera
  Future<void> _openCamera() async {
    final XFile? image =
        await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() => _groupImage = File(image.path));
    }
  }

  /// Open Gallery
  Future<void> _openGallery() async {
    final XFile? image =
        await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _groupImage = File(image.path));
    }
  }

  /// Image Source Popup
  void _showImageSourcePopup() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Select Image Source",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF17251F)
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _imageSourceItem(
                    icon: Icons.camera_alt,
                    label: "Camera",
                    onTap: () {
                      Navigator.pop(context);
                      _openCamera();
                    },
                  ),
                  _imageSourceItem(
                    icon: Icons.photo,
                    label: "Gallery",
                    onTap: () {
                      Navigator.pop(context);
                      _openGallery();
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

  Widget _imageSourceItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFF168A62),
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }

  /// Disappearing Messages
  void _showDisappearingMessages() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Disappearing messages",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF17251F),
                ),
              ),
            ),
            _disappearOption("Off"),
            _disappearOption("24 hours"),
            _disappearOption("7 days"),
            _disappearOption("90 days"),
          ],
        );
      },
    );
  }

  Widget _disappearOption(String value) {
    return ListTile(
      title: Text(value, style: const TextStyle(color: Color(0xFF35433C))),
      trailing:
          disappearingMessage == value ? const Icon(Icons.check) : null,
      onTap: () {
        setState(() => disappearingMessage = value);
        Navigator.pop(context);
      },
    );
  }

  /// Group Permissions
  void _showGroupPermissions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Group permissions",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF17251F),
                ),
              ),
              const SizedBox(height: 16),

              const Text("Edit group info",
                  style: TextStyle(color: Color(0xFF17251F))),
              RadioListTile(
                title: const Text("All participants",
                    style: TextStyle(color: Color(0xFF35433C))),
                value: false,
                groupValue: onlyAdminsEditInfo,
                onChanged: (v) => setState(() => onlyAdminsEditInfo = v!),
              ),
              RadioListTile(
                title: const Text("Admins only",
                    style: TextStyle(color: Color(0xFF35433C))),
                value: true,
                groupValue: onlyAdminsEditInfo,
                onChanged: (v) => setState(() => onlyAdminsEditInfo = v!),
              ),

              const Divider(),

              const Text("Send messages",
                  style: TextStyle(color: Color(0xFF17251F))),
              RadioListTile(
                title: const Text("All participants",
                    style: TextStyle(color: Color(0xFF35433C))),
                value: false,
                groupValue: onlyAdminsSendMessage,
                onChanged: (v) => setState(() => onlyAdminsSendMessage = v!),
              ),
              RadioListTile(
                title: const Text("Admins only",
                    style: TextStyle(color: Color(0xFF35433C))),
                value: true,
                groupValue: onlyAdminsSendMessage,
                onChanged: (v) => setState(() => onlyAdminsSendMessage = v!),
              ),
            ],
          ),
        );
      },
    );
  }

  String get permissionSubtitle =>
      (onlyAdminsEditInfo || onlyAdminsSendMessage)
          ? "Admins only"
          : "All participants";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,

      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        elevation: 0,
        title: const Text(
          "New group",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF168A62),
        onPressed: _isCreating ? null : _createGroup,
        child: _isCreating
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.check, color: Colors.white),
      ),

      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _showImageSourcePopup,
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFFDCE9E1),
                    backgroundImage:
                        _groupImage != null ? FileImage(_groupImage!) : null,
                    child: _groupImage == null
                        ? const Icon(Icons.camera_alt, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: "Group name",
                      enabledBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: Color(0xFFDCE4DE)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: Color(0xFF168A62), width: 1.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                )
              ],
            ),

            const SizedBox(height: 24),

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                "Disappearing messages",
                style: TextStyle(color: Color(0xFF17251F)),
              ),
              subtitle: Text(disappearingMessage),
              trailing: const Icon(Icons.timer),
              onTap: _showDisappearingMessages,
            ),

            const Divider(),

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                "Group permissions",
                style: TextStyle(color: Color(0xFF17251F)),
              ),
              subtitle: Text(permissionSubtitle),
              trailing: const Icon(Icons.settings),
              onTap: _showGroupPermissions,
            ),

            const SizedBox(height: 16),

            /// MEMBERS (DYNAMIC)
            Text(
              "Members: ${widget.members.length}",
              style: const TextStyle(
                color: Color(0xFF17251F),
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.members.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  return _MemberAvatar(name: widget.members[index].name);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Member Avatar Widget
class _MemberAvatar extends StatelessWidget {
  final String name;

  const _MemberAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const CircleAvatar(
          radius: 26,
          backgroundColor: Color(0xFFE8F3ED),
          child: Icon(Icons.person, color: Color(0xFF168A62)),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF68776F),
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
