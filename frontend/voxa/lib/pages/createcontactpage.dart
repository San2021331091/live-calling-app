import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CreateContactPage extends StatefulWidget {
  const CreateContactPage({super.key});

  @override
  State<CreateContactPage> createState() => _CreateContactPageState();
}

class _CreateContactPageState extends State<CreateContactPage> {
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  File? _profileImage;

  /// Open Camera
  Future<void> _openCamera() async {
    final XFile? image =
        await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() => _profileImage = File(image.path));
    }
  }

  /// Open Gallery
  Future<void> _openGallery() async {
    final XFile? image =
        await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _profileImage = File(image.path));
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
                  color: const Color(0xFF17251F),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),

      appBar: AppBar(
        elevation: 0,
        foregroundColor: const Color(0xFF17251F),
        backgroundColor: const Color(0xFFF5F7F5),
        title: const Text(
          "Create new contact",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF17251F),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // SAVE CONTACT
            },
            child: const Text(
              "SAVE",
              style: TextStyle(
                color: Color(0xFF168A62),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
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

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            /// Avatar
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFFDCE9E1),
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : null,
                    child: _profileImage == null
                        ? const Icon(
                            Icons.person,
                            size: 50,
                            color: Color(0xFF168A62),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _showImageSourcePopup,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF168A62),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            /// First Name
            _inputField(
              controller: _firstName,
              label: "First name",
              icon: Icons.person_outline,
            ),

            const SizedBox(height: 20),

            /// Last Name
            _inputField(
              controller: _lastName,
              label: "Last name",
              icon: Icons.badge_outlined,
            ),

            const SizedBox(height: 20),

            /// Phone Number
            _inputField(
              controller: _phone,
              label: "Phone number",
              icon: Icons.phone_android,
              keyboard: TextInputType.phone,
            ),

            const SizedBox(height: 40),

            const Text(
              "This contact will be saved to your device",
              style: TextStyle(
                color: Color(0xFF68776F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Custom colorful input field
  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(color: Color(0xFF17251F)),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF168A62)),
        labelText: label,
        labelStyle: TextStyle(
          color: const Color(0xFF68776F),
          fontWeight: FontWeight.w600,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDCE4DE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF168A62), width: 1.5),
        ),
      ),
    );
  }
}
