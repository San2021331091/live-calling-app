import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/pages/groupchatpage.dart';
import 'package:voxa/pages/individualpage.dart';

class CustomCard extends StatelessWidget {
  const CustomCard({super.key, required this.chatModel});

  final ChatModel chatModel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: Colors.lightBlue,
                child: SvgPicture.asset(
                  chatModel.isGroup == true
                      ? "assets/groups.svg"
                      : "assets/persons.svg",
                  height: 34,
                  width: 34,
                ),
              ),
              title: Text(
                chatModel.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.deepOrange,
                ),
              ),
              subtitle: Row(
                children: [
                  const Icon(Icons.done_all, size: 16, color: Colors.red),
                  const SizedBox(width: 4),

                  /// Wrap the text in Expanded to prevent overflow
                  Expanded(
                    child: Text(
                      chatModel.currentMessage ?? "No messages yet",
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              trailing: Text(
                chatModel.time ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          /// 🔹 divider with padding
          const Padding(
            padding: EdgeInsets.only(left: 78, right: 12),
            child: Divider(height: 0, thickness: 0.6, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}
