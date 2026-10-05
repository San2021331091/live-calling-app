import 'package:flutter/material.dart';
import 'package:voxa/colors/colors.dart';
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
      'color': Colors.orangeAccent,
    },
    {
      'name': 'Work',
      'icon': Icons.work,
      'color': Colors.blueAccent,
    },
    {
      'name': 'School',
      'icon': Icons.school,
      'color': Colors.greenAccent,
    },
    {
      'name': 'Other',
      'icon': Icons.public,
      'color': Colors.purpleAccent,
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
        leading: const BackButton(color: Colors.white),
        title: const Text(
          "New Community",
          style: TextStyle(color: Colors.white),
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColor.dartTealGreen, AppColor.lightGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Select Community Type",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,color: Colors.purple),
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
