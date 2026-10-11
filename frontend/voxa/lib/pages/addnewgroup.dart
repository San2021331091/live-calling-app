import 'package:flutter/material.dart';
import 'package:voxa/customui/gradient_app_bar_background.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/model/user_model.dart';
import 'package:voxa/services/api_client.dart';

class AddNewGroup extends StatefulWidget {
  final List<UserModel> members;

  const AddNewGroup({super.key, required this.members});

  @override
  State<AddNewGroup> createState() => _AddNewGroupState();
}

class _AddNewGroupState extends State<AddNewGroup> {
  final TextEditingController _nameController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a group name.')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not create group. Check your connection.'),
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
      backgroundColor: Colors.transparent,

      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        elevation: 0,
        title: const Text(
          "New group",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
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
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Color(0xFFDCE9E1),
                  child: Icon(Icons.groups_rounded, color: Color(0xFF168A62)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: "Group name",
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFDCE4DE)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                          color: Color(0xFF168A62),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

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
                separatorBuilder: (_, _) => const SizedBox(width: 16),
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
