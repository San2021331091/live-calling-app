import 'package:flutter/material.dart';
import 'package:voxa/model/call_model.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/pages/individualpage.dart';
import 'package:voxa/screens/webrtc_call_screen.dart';
import 'package:voxa/services/api_client.dart';

class UserProfileScreen extends StatelessWidget {
  final String name;
  final String status;
  final String lastSeen;
  final String phone;
  final String? imageUrl;

  const UserProfileScreen({
    super.key,
    required this.name,
    required this.status,
    required this.lastSeen,
    required this.phone,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          "Contact Info",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xff128C7E), Color(0xff25D366)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // HEADER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xff128C7E), Color(0xff25D366)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.white,
                  backgroundImage: imageUrl != null
                      ? NetworkImage(imageUrl!)
                      : null,
                  child: imageUrl == null
                      ? const Icon(Icons.person, size: 50, color: Colors.grey)
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  lastSeen,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ACTION BUTTONS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionButton(Icons.message, "Message", Colors.teal, () {
                  ChatModel chat = ChatModel(
                    name: name,
                    img: imageUrl!,
                    isGroup: false,
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IndividualPage(chatModel: chat),
                    ),
                  );
                }),
                _actionButton(Icons.call, "Call", Colors.green, () {
                  _startCall(context, CallMedia.audio);
                }),
                _actionButton(Icons.videocam, "Video", Colors.blue, () {
                  _startCall(context, CallMedia.video);
                }),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // INFO LIST
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _infoTile(Icons.phone, "Phone", phone),
                _infoTile(Icons.info_outline, "About", status),
                _infoTile(Icons.schedule, "Last seen", lastSeen),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startCall(BuildContext context, CallMedia media) async {
    try {
      final chat = await ApiClient.instance.createDirectChat(phone: phone);
      final peerId = chat.peerId;
      if (peerId == null || peerId.isEmpty) {
        throw const ApiException('This contact is not a registered Voxa user.');
      }
      final call = await ApiClient.instance.createCall(
        peerId: peerId,
        media: media,
      );
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebRtcCallScreen(
            callId: call.id,
            peerId: peerId,
            peerName: name,
            peerAvatar: imageUrl ?? '',
            media: media,
            isIncoming: false,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Widget _actionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _infoTile(IconData icon, String title, String value) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.teal),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.pink,
          ),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            color: Colors.deepOrange,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
