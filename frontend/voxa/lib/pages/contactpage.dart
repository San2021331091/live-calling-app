import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:voxa/pages/individualpage.dart';
import 'package:voxa/screens/videocallscreen.dart';
import 'package:voxa/screens/voicecallscreen.dart';
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
          : const CircleAvatar(child: Icon(Icons.person)),
      title: Text(contact.displayName),
      subtitle: contact.phones.isNotEmpty
          ? Text(contact.phones.first.number)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.message, color: Colors.green),
            onPressed: () => _openChat(contact),
          ),
          IconButton(
            icon: const Icon(Icons.call, color: Colors.blue),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VoiceCallScreen(
                    callerName: contact.displayName,
                    callerAvatar: "https://i.pravatar.cc/150?img=1",
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.purple),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoCallScreen(
                    callerName: contact.displayName,
                    callerAvatar: "https://i.pravatar.cc/150?img=1",
                  ),
                ),
              );
            },
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
      appBar: AppBar(
        backgroundColor: const Color(0xff075E54),
        title: const Text("Contacts", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
