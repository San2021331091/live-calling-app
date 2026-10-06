import 'package:flutter/material.dart';
import 'package:voxa/customui/gradient_app_bar_background.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:voxa/model/call_model.dart';
import 'package:voxa/pages/individualpage.dart';
import 'package:voxa/screens/webrtc_call_screen.dart';
import 'package:voxa/services/api_client.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  List<Contact> contacts = [];
  List<Contact> filteredContacts = [];
  bool isLoading = true;
  String? loadError;
  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchContacts();
    searchController.addListener(_filterContacts);
  }

  Future<void> _fetchContacts() async {
    try {
      if (!await FlutterContacts.requestPermission()) {
        loadError = 'Allow contacts access to see your contacts.';
        return;
      }
      final allContacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
      );
      contacts = allContacts;
      filteredContacts = allContacts;
    } catch (_) {
      loadError = 'Could not load contacts.';
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _openChat(Contact contact) async {
    if (contact.phones.isEmpty) {
      _showError('This contact does not have a phone number.');
      return;
    }
    try {
      final chat = await ApiClient.instance.createDirectChat(
        phone: contact.phones.first.number,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IndividualPage(chatModel: chat)),
      );
    } on ApiException catch (exception) {
      if (mounted) _showError(exception.message);
    } catch (_) {
      if (mounted) {
        _showError('Could not start this chat. Check your connection.');
      }
    }
  }

  Future<void> _startCall(Contact contact, CallMedia media) async {
    if (contact.phones.isEmpty) {
      _showError('This contact does not have a phone number.');
      return;
    }
    try {
      final chat = await ApiClient.instance.createDirectChat(
        phone: contact.phones.first.number,
      );
      final peerId = chat.peerId;
      if (peerId == null || peerId.isEmpty) {
        _showError('This contact is not a registered Voxa user.');
        return;
      }
      final call = await ApiClient.instance.createCall(peerId: peerId, media: media);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebRtcCallScreen(
            callId: call.id,
            peerId: peerId,
            peerName: contact.displayName,
            peerAvatar: '',
            media: media,
            isIncoming: false,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _filterContacts() {
    final query = searchController.text.toLowerCase();
    setState(() {
      filteredContacts = contacts
          .where((c) => c.displayName.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Widget _buildContactTile(Contact contact) {
    return ListTile(
      leading: (contact.photo != null && contact.photo!.isNotEmpty)
          ? CircleAvatar(backgroundImage: MemoryImage(contact.photo!))
          : const CircleAvatar(backgroundColor: Color(0xFFE8F3ED), child: Icon(Icons.person, color: Color(0xFF168A62))),
      title: Text(contact.displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF17251F))),
      subtitle: contact.phones.isNotEmpty
          ? Text(contact.phones.first.number)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.message_outlined, color: Color(0xFF168A62)),
            onPressed: () => _openChat(contact),
          ),
          IconButton(
            icon: const Icon(Icons.call_outlined, color: Color(0xFF168A62)),
            onPressed: () => _startCall(contact, CallMedia.audio),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined, color: Color(0xFF168A62)),
            onPressed: () => _startCall(contact, CallMedia.video),
          ),
        ],
      ),
      onTap: () {
        print("Selected: ${contact.displayName}");
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: const Text("Contacts"),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
          ? Center(child: Text(loadError!))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search contacts",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: const Color(0xFFF0F4F1),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredContacts.length,
                    itemBuilder: (context, index) {
                      final contact = filteredContacts[index];
                      return _buildContactTile(contact);
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
