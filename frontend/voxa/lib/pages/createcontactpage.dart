import 'dart:io';

import 'package:flutter/material.dart';
import 'package:voxa/customui/gradient_app_bar_background.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voxa/model/user_model.dart';
import 'package:voxa/pages/individualpage.dart';
import 'package:voxa/services/api_client.dart';

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
  bool _isSaving = false;
  UserModel? _registeredUser;
  String? _registrationMessage;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final phoneInput = _phone.text.trim();
    final digits = phoneInput.replaceAll(RegExp(r'\D'), '');

    if (firstName.isEmpty) {
      _showMessage('Enter a first name.');
      return;
    }
    if (!RegExp(r'^[+()\-\s.0-9]+$').hasMatch(phoneInput) ||
        digits.length < 6 ||
        digits.length > 15) {
      _showMessage('Enter a valid phone number with country code.');
      return;
    }

    setState(() {
      _isSaving = true;
      _registeredUser = null;
      _registrationMessage = null;
    });

    try {
      final registeredUser = await ApiClient.instance.findUserByPhone(
        phoneInput,
      );
      if (!mounted) return;

      final hasPermission = await FlutterContacts.requestPermission();
      if (!hasPermission) {
        throw const ApiException(
          'Contacts permission is required to save this contact.',
        );
      }

      final displayName = [
        firstName,
        lastName,
      ].where((part) => part.isNotEmpty).join(' ');
      final existingContacts = await FlutterContacts.getContacts(
        withProperties: true,
      );
      final alreadySaved = existingContacts.any(
        (contact) => contact.phones.any(
          (phone) => phone.number.replaceAll(RegExp(r'\D'), '') == digits,
        ),
      );

      if (!alreadySaved) {
        await FlutterContacts.insertContact(
          Contact(
            displayName: displayName,
            name: Name(first: firstName, last: lastName),
            phones: [Phone(phoneInput)],
            photo: _profileImage == null
                ? null
                : await _profileImage!.readAsBytes(),
          ),
        );
      }
      if (!mounted) return;

      setState(() {
        _registeredUser = registeredUser;
        _registrationMessage = registeredUser?.id == ApiClient.instance.userId
            ? 'This is your Voxa account number.'
            : alreadySaved
            ? 'This contact was already saved on your device.'
            : 'Contact saved to your device.';
      });
      _showMessage(
        registeredUser == null
            ? '${_registrationMessage!} This number is not registered with Voxa yet.'
            : registeredUser.id == ApiClient.instance.userId
            ? _registrationMessage!
            : '${_registrationMessage!} $displayName is already on Voxa.',
      );
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('Could not save contact: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openChat() async {
    final user = _registeredUser;
    if (user == null) return;
    try {
      final chat = await ApiClient.instance.createDirectChat(userId: user.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IndividualPage(chatModel: chat)),
      );
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('Could not open chat: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Open Camera
  Future<void> _openCamera() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() => _profileImage = File(image.path));
    }
  }

  /// Open Gallery
  Future<void> _openGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
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
                  color: Color(0xFF17251F),
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
      backgroundColor: Colors.transparent,

      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        elevation: 0,
        title: const Text(
          "Create new contact",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveContact,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    "SAVE",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
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

            _inputField(
              controller: _firstName,
              label: "First name",
              icon: Icons.person_outline,
            ),

            const SizedBox(height: 20),

            _inputField(
              controller: _lastName,
              label: "Last name",
              icon: Icons.badge_outlined,
            ),

            const SizedBox(height: 20),

            _inputField(
              controller: _phone,
              label: "Phone number (include country code)",
              icon: Icons.phone_android,
              keyboard: TextInputType.phone,
            ),

            if (_registrationMessage != null) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F3ED),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _registrationMessage!,
                      style: const TextStyle(
                        color: Color(0xFF17251F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_registeredUser != null &&
                        _registeredUser!.id != ApiClient.instance.userId) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _openChat,
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Message on Voxa'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            const Text(
              "The number will be checked against Voxa accounts before this contact is saved to your device.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF68776F),
                fontWeight: FontWeight.w500,
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
