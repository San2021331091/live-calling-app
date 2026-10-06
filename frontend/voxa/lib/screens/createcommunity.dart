import 'package:flutter/material.dart';
import 'package:voxa/pages/createnewcommunity.dart';
import 'package:voxa/model/chatmodel.dart';

class CreateNewCommunity extends StatefulWidget {
  const CreateNewCommunity({super.key});

  @override
  State<CreateNewCommunity> createState() => _CreateNewCommunityState();
}

class _CreateNewCommunityState extends State<CreateNewCommunity> {
  final List<Map<String, dynamic>> communityTypes = [
    {
      'name': 'For Friends',
      'icon': Icons.group,
      'color': const Color(0xFF168A62),
    },
    {
      'name': 'Work',
      'icon': Icons.work,
      'color': const Color(0xFF168A62),
    },
    {
      'name': 'School',
      'icon': Icons.school,
      'color': const Color(0xFF168A62),
    },
    {
      'name': 'Other',
      'icon': Icons.public,
      'color': const Color(0xFF168A62),
    },
  ];

  Future<void> _openCommunityInfo(String type) async {
    final community = await Navigator.push<ChatModel>(
      context,
      MaterialPageRoute(
        builder: (_) => AddCommunityInfo(communityType: type),
      ),
    );
    if (community != null && mounted) Navigator.pop(context, community);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: Color(0xFF35433C)),
        title: const Text(
          "New Community",
          style: TextStyle(color: Color(0xFF17251F), fontWeight: FontWeight.w700),
        ),
        elevation: 0,
        backgroundColor: const Color(0xFFF9FBF9),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Select Community Type",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,color: Color(0xFF17251F)),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                itemCount: communityTypes.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 1.2,
                ),
                itemBuilder: (context, index) {
                  final type = communityTypes[index];
                  return GestureDetector(
                    onTap: () {
                      _openCommunityInfo(type['name'] as String);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: type['color'].withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(type['icon'], size: 50, color: type['color']),
                          const SizedBox(height: 12),
                          Text(
                            type['name'],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: type['color'].shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
