import 'dart:io';
import 'package:flutter/material.dart';
import 'package:voxa/customui/gradient_app_bar_background.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voxa/model/user_model.dart';
import 'package:voxa/services/api_client.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _profileImage;

  UserModel? _profile;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await ApiClient.instance.loadCurrentUser();
      if (mounted) setState(() => _profile = profile);
    } on ApiException catch (exception) {
      if (mounted) setState(() => _error = exception.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your profile.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile({String? name, String? bio}) async {
    try {
      final profile = await ApiClient.instance.updateProfile(name: name, bio: bio);
      if (mounted) setState(() => _profile = profile);
    } on ApiException catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(exception.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update your profile.')),
        );
      }
    }
  }

  /// Pick image from camera/gallery
  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() => _profileImage = File(image.path));
    }
  }

  /// Show bottom sheet for image picker
  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _imageOption(
              icon: Icons.camera_alt,
              label: "Camera",
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            _imageOption(
              icon: Icons.photo,
              label: "Gallery",
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageOption({
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
            radius: 30,
            backgroundColor: Colors.teal,
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.teal)),
      ],
    );
  }

  /// Edit bottom sheet for any field
  void _editField(String title, String initial, Function(String) onSave) {
    final controller = TextEditingController(text: initial);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Edit $title",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                ),
                onPressed: () {
                  onSave(controller.text);
                  Navigator.pop(context);
                },
                child: const Text("SAVE",style: TextStyle(color: Colors.white),),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        elevation: 0,
        title: const Text("Profile"),
      ),

      body: ListView(
        children: [
          if (_isLoading)
            const LinearProgressIndicator()
          else if (_error != null)
            ListTile(
              title: Text(_error!),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadProfile,
              ),
            )
          else if (_profile != null) ...[
          /// HEADER
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: const BoxDecoration(color: Colors.white),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 55,
                      backgroundColor: const Color(0xFFE8F3ED),
                      backgroundImage: _profileImage != null
                          ? FileImage(_profileImage!)
                          : null,
                      child: _profileImage == null
                          ? const Icon(
                              Icons.person,
                              size: 60,
                              color: const Color(0xFF168A62),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _showImagePicker,
                        child: const CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF168A62),
                          child: Icon(
                            Icons.camera_alt,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _profile!.name,
                  style: const TextStyle(
                    color: const Color(0xFF17251F),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Tap to edit profile photo",
                  style: TextStyle(
                    color: Color(0xFF75827B),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          /// PROFILE INFO TILES
          _infoTile(
            icon: Icons.person,
            color: const Color(0xFF168A62),
            title: "Name",
            value: _profile!.name,
            onTap: () => _editField(
              'Name', _profile!.name, (value) => _saveProfile(name: value),
            ),
          ),
          _infoTile(
            icon: Icons.info,
            color: const Color(0xFF168A62),
            title: "About",
            value: _profile!.bio,
            onTap: () => _editField(
              'About', _profile!.bio, (value) => _saveProfile(bio: value),
            ),
          ),
          _infoTile(
            icon: Icons.phone,
            color: const Color(0xFF168A62),
            title: "Phone",
            value: _profile!.phone,
            enabled: false,
          ),
          ],
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Container(width: 38, height: 38, decoration: const BoxDecoration(color: Color(0xFFEAF4EE), shape: BoxShape.circle), child: Icon(icon, color: color, size: 19)),
        title: Text(title, style: const TextStyle(color: Color(0xFF75827B), fontSize: 10)),
        subtitle: Text(value, style: const TextStyle(color: Color(0xFF26362E), fontSize: 13, fontWeight: FontWeight.w600)),
        trailing: enabled ? const Icon(Icons.edit_outlined, size: 17, color: Color(0xFF87928C)) : null,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
