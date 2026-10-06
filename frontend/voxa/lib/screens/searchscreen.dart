import 'package:flutter/material.dart';
import 'package:voxa/screens/userprofilescreen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;

  // Contacts data: name + phone + info
  final List<Map<String, String>> allContacts = [
    {
      "name": "Santosh Saha",
      "phone": "+8801234567890",
      "info": "Hey there! I'm using Voxa",
    },
    {
      "name": "Rina Das",
      "phone": "+8809876543210",
      "info": "Available for calls",
    },
    {"name": "Amit Roy", "phone": "+8801122334455", "info": "Busy right now"},
    {"name": "Tina Sen", "phone": "+8805566778899", "info": "At work"},
    {"name": "John Doe", "phone": "+8806677889900", "info": "Hey there!"},
    {"name": "Jane Smith", "phone": "+8804455667788", "info": "Offline"},
  ];

  List<Map<String, String>> filteredContacts = [];

  @override
  void initState() {
    super.initState();
    filteredContacts = List.from(allContacts);

    _searchController.addListener(() {
      final query = _searchController.text.toLowerCase();
      final queryDigits = query.replaceAll(
        RegExp(r'\D'),
        '',
      ); // remove non-digits

      setState(() {
        isSearching = query.isNotEmpty;

        filteredContacts = allContacts.where((contact) {
          // Name match
          final nameMatch = contact["name"]!.toLowerCase().contains(query);

          // Phone match: remove non-digit chars from phone
          final phoneDigits = contact["phone"]!.replaceAll(RegExp(r'\D'), '');
          final phoneMatch =
              queryDigits.isNotEmpty && phoneDigits.contains(queryDigits);

          return nameMatch || phoneMatch;
        }).toList();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF9FBF9),
        foregroundColor: const Color(0xFF17251F),
        title: _buildSearchBar(),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: filteredContacts.isEmpty
            ? const Center(
                child: Text(
                  "No contacts found",
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              )
            : ListView.builder(
                itemCount: filteredContacts.length,
                itemBuilder: (_, index) {
                  final contact = filteredContacts[index];
                  return _buildContactCard(contact);
                },
              ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        color: const Color(0xFFF0F4F1),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Color(0xFF75827B)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Color(0xFF26362E)),
              decoration: const InputDecoration(
                hintText: "Search by name or phone...",
                hintStyle: TextStyle(color: Color(0xFF87928C)),
                border: InputBorder.none,
              ),
              keyboardType: TextInputType.text,
            ),
          ),
          if (isSearching)
            GestureDetector(
              onTap: () => _searchController.clear(),
              child: const Icon(Icons.close, color: Color(0xFF75827B)),
            ),
        ],
      ),
    );
  }

  Widget _buildContactCard(Map<String, String> contact) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE6F3ED),
          child: Text(
            contact["name"]![0].toUpperCase(),
            style: const TextStyle(
              color: const Color(0xFF168A62),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          contact["name"]!,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF17251F),
          ),
        ),
        subtitle: Text(
          "${contact["phone"]} ${contact["info"]}",
          style: const TextStyle(color: Color(0xFF75827B), fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF87928C), size: 15),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                  name: contact["name"]!,
                  status: contact["info"]!,
                  lastSeen: "Online",
                  phone: contact["phone"]!,
                ),
              ),
            );
          },
        ),
        onTap: () {
          print("Tapped on ${contact["name"]}");
        },
      ),
    );
  }
}
