import 'package:flutter/material.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/pages/groupchatpage.dart';
import 'package:voxa/pages/individualpage.dart';

class CustomCard extends StatelessWidget {
  const CustomCard({super.key, required this.chatModel});

  final ChatModel chatModel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => chatModel.isGroup == true
                ? GroupChatPage(group: chatModel)
                : IndividualPage(chatModel: chatModel),
          ),
        );
      },
      child: Column(
        children: [
          /// Tile padding like WhatsApp
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
              leading: CircleAvatar(
                radius: 25,
                backgroundColor: const Color(0xFFE8F3ED),
                child: Icon(
                  chatModel.isGroup == true ? Icons.groups_2_rounded : Icons.person_rounded,
                  color: const Color(0xFF168A62),
                  size: 25,
                ),
              ),
              title: Text(
                chatModel.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF17251F),
                ),
              ),
              subtitle: Row(
                children: [
                  Expanded(
                    child: Text(
                      chatModel.currentMessage ?? "No messages yet",
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF75827B),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
              trailing: Text(
                chatModel.time ?? '',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF829089),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          /// 🔹 divider with padding
          const Padding(
            padding: EdgeInsets.only(left: 74, right: 18),
            child: Divider(height: 0, thickness: 0.6, color: Color(0xFFE8ECE9)),
          ),
        ],
      ),
      ),
    );
  }
}
