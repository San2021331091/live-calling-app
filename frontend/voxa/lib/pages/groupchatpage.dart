import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/model/message_model.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/services/media_upload_service.dart';
import 'package:voxa/pages/media_preview.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class GroupChatPage extends StatefulWidget {
  final ChatModel group;
  const GroupChatPage({super.key, required this.group});

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool showEmojiPicker = false;

  final List<MessageModel> messages = [];
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _isLoading = true;
  String? _chatError;

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _focusNode.dispose();
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    final chatId = widget.group.id;
    if (chatId == null) {
      setState(() {
        _isLoading = false;
        _chatError = 'Open this group from your registered chats.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _chatError = null;
    });
    try {
      _subscription?.cancel();
      await _channel?.sink.close();
      final channel = await ApiClient.instance.connectToChat(chatId);
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleSocketEvent,
        onError: (Object _) {
          if (mounted) setState(() => _chatError = 'Live connection lost.');
        },
        onDone: () {
          if (mounted) setState(() => _chatError = 'Live connection closed.');
        },
      );
      final history = await ApiClient.instance.loadMessages(chatId);
      if (!mounted) return;
      setState(() {
        for (final message in history) {
          if (!messages.any((item) => item.id == message.id)) {
            messages.add(message);
          }
        }
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _chatError = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _chatError =
              'Could not connect to this group. Check your connection.';
        });
      }
    }
  }

  void _handleSocketEvent(dynamic event) {
    try {
      final decoded = jsonDecode(event as String) as Map<String, dynamic>;
      if (decoded['type'] == 'message' &&
          decoded['message'] is Map<String, dynamic>) {
        final message = MessageModel.fromJson(
          decoded['message'] as Map<String, dynamic>,
        );
        if (mounted && !messages.any((item) => item.id == message.id)) {
          setState(() => messages.add(message));
        }
      } else if (decoded['type'] == 'error' && mounted) {
        setState(() => _chatError = decoded['error'] as String?);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _chatError = 'Received an invalid chat event.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: _greenAppBar(),
      body: Column(
        children: [
          Expanded(child: _messageList()),
          _inputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _greenAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF26362E),
      bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Color(0xFFE8ECE9))),
      title: Row(
        children: [
          const CircleAvatar(radius: 20, backgroundColor: Color(0xFFE8F3ED), child: Icon(Icons.groups_2_rounded, color: Color(0xFF168A62))),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.group.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF17251F),
                ),
              ),
              const Text(
                "Group conversation",
                style: TextStyle(fontSize: 10, color: Color(0xFF75827B)),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _showGroupCallsUnavailable,
          icon: const Icon(Icons.videocam_outlined, color: Color(0xFF168A62)),
        ),
        IconButton(
          onPressed: _showGroupCallsUnavailable,
          icon: const Icon(Icons.call_outlined, color: Color(0xFF168A62)),
        ),
      ],
    );
  }

  void _showGroupCallsUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Group calling is not supported yet; calls currently use peer-to-peer WebRTC.',
        ),
      ),
    );
  }

  Widget _messageList() {
    return Column(
      children: [
        if (_chatError != null)
          MaterialBanner(
            content: Text(_chatError!),
            actions: [
              TextButton(
                onPressed: _initializeChat,
                child: const Text('Retry'),
              ),
            ],
          ),
        Expanded(
          child: _isLoading && messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return Align(
                      alignment: msg.isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(14),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: msg.isMe ? const Color(0xFFDDF4E7) : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(msg.isMe ? 18 : 5),
                            bottomRight: Radius.circular(msg.isMe ? 5 : 18),
                          ),
                          boxShadow: const [BoxShadow(color: Color(0x0A17251F), blurRadius: 10, offset: Offset(0, 3))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!msg.isMe)
                              Text(
                                msg.sender,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF168A62),
                                ),
                              ),
                            if (!msg.isMe) const SizedBox(height: 4),
                            _messageContent(msg),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Text(
                                msg.time,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: msg.isMe
                                      ? const Color(0xFF849089)
                                      : const Color(0xFF849089),
                                ),
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
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  // Emoji Button
                  IconButton(
                    icon: const Icon(
                      Icons.emoji_emotions_outlined,
                      color: const Color(0xFF79877F),
                    ),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() {
                        showEmojiPicker = !showEmojiPicker;
                      });
                    },
                  ),

                  // TextField
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      decoration: const InputDecoration(
                        hintText: "Type a message",
                        border: InputBorder.none,
                      ),
                      onTap: () {
                        if (showEmojiPicker) {
                          setState(() {
                            showEmojiPicker = false;
                          });
                        }
                      },
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Attach Button
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: Color(0xFF168A62)),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _attachmentBottomSheet(),
                      );
                    },
                  ),

                  // Send Button
                  CircleAvatar(
                    backgroundColor: const Color(0xFF168A62),
                    child: IconButton(
                      icon: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Emoji Picker
          Offstage(
            offstage: !showEmojiPicker,
            child: SizedBox(
              height: 260,
              child: EmojiPicker(
                textEditingController: _messageController,
                config: Config(
                  checkPlatformCompatibility: true,
                  emojiViewConfig: EmojiViewConfig(
                    emojiSizeMax:
                        28 *
                        (foundation.defaultTargetPlatform ==
                                TargetPlatform.android
                            ? 1.0
                            : 1.2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentBottomSheet() {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _attachmentItem(
                Icons.insert_drive_file,
                "Document",
                Colors.indigo,
                () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf', 'doc', 'docx', 'zip'],
                  );
                  if (result != null && result.files.single.path != null) await _uploadAndSend(File(result.files.single.path!), 'document', result.files.single.name);
                },
              ),
              _attachmentItem(
                Icons.camera_alt,
                "Camera",
                Colors.pink,
                () async {
                  showModalBottomSheet(
                    context: context,
                    builder: (_) => SizedBox(
                      height: 120,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.photo),
                            title: const Text("Image"),
                            onTap: () async {
                              Navigator.pop(context);
                              final image = await _imagePicker.pickImage(
                                source: ImageSource.camera,
                              );
                              if (image != null) await _uploadAndSend(File(image.path), 'image', image.name);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.videocam),
                            title: const Text("Video"),
                            onTap: () async {
                              Navigator.pop(context);
                              final video = await _imagePicker.pickVideo(
                                source: ImageSource.camera,
                              );
                              if (video != null) await _uploadAndSend(File(video.path), 'video', video.name);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              _attachmentItem(Icons.photo, "Gallery", Colors.purple, () async {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => SizedBox(
                    height: 120,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.photo,
                            color: Colors.deepOrange,
                          ),
                          title: const Text("Image"),
                          onTap: () async {
                            Navigator.pop(context);
                            final image = await _imagePicker.pickImage(
                              source: ImageSource.gallery,
                            );
                            if (image != null) await _uploadAndSend(File(image.path), 'image', image.name);
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.videocam,
                            color: Colors.green,
                          ),
                          title: const Text("Video"),
                          onTap: () async {
                            Navigator.pop(context);
                            final video = await _imagePicker.pickVideo(
                              source: ImageSource.gallery,
                            );
                            if (video != null) await _uploadAndSend(File(video.path), 'video', video.name);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _attachmentItem(
                Icons.headphones,
                "Audio",
                Colors.orange,
                () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.audio,
                  );
                  final file = result?.files.single;
                  if (file != null && file.path != null) await _uploadAndSend(File(file.path!), 'audio', file.name);
                },
              ),
              _attachmentItem(
                Icons.location_on,
                "Location",
                Colors.green,
                () async {
                  bool serviceEnabled =
                      await Geolocator.isLocationServiceEnabled();
                  if (!serviceEnabled) return;
                  LocationPermission permission =
                      await Geolocator.checkPermission();
                  if (permission == LocationPermission.denied) {
                    permission = await Geolocator.requestPermission();
                  }
                  if (permission == LocationPermission.deniedForever) return;
                  final pos = await Geolocator.getCurrentPosition();
                  print("Location: ${pos.latitude}, ${pos.longitude}");
                },
              ),
              _attachmentItem(Icons.person, "Contact", Colors.blue, () async {
                if (!await FlutterContacts.requestPermission()) return;
                final contacts = await FlutterContacts.getContacts(
                  withProperties: true,
                );

                // Show popup to pick contact
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Select Contact"),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: contacts.length,
                        itemBuilder: (_, index) {
                          final contact = contacts[index];
                          return ListTile(
                            leading:
                                (contact.photo != null &&
                                    contact.photo!.isNotEmpty)
                                ? CircleAvatar(
                                    backgroundImage: MemoryImage(
                                      contact.photo!,
                                    ),
                                  )
                                : const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(contact.displayName),
                            onTap: () {
                              Navigator.pop(context);
                              print("Selected contact: ${contact.displayName}");
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _attachmentItem(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Color(0xFF35433C), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _messageContent(MessageModel message) {
    if (message.mediaUrl == null) return Text(message.message, style: const TextStyle(fontSize: 14, color: Color(0xFF26362E)));
    if (message.mediaType == 'image') return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(message.mediaUrl!, width: 220, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Color(0xFF75827B)))),
      if (message.message.isNotEmpty && message.message != 'Image') Text(message.message, style: const TextStyle(color: Color(0xFF26362E))),
    ]);
    return InkWell(onTap: () {
      if (message.mediaType == 'video') {
        Navigator.push(context, MaterialPageRoute(builder: (_) => MediaPreview(url: message.mediaUrl!)));
      } else {
        showDialog<void>(context: context, builder: (_) => AlertDialog(title: Text(message.mediaName ?? 'Attachment'), content: SelectableText(message.mediaUrl!)));
      }
    }, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(message.mediaType == 'video' ? Icons.play_circle : Icons.insert_drive_file, color: const Color(0xFF168A62)), const SizedBox(width: 8), Flexible(child: Text(message.mediaName ?? message.message, style: const TextStyle(color: Color(0xFF26362E))))]));
  }

  Future<void> _uploadAndSend(File file, String type, String name) async {
    final channel = _channel;
    if (channel == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat is not connected.'))); return; }
    try {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading attachment…')));
      final url = await MediaUploadService.upload(file, isVideo: type != 'image');
      await ApiClient.instance.sendMessage(channel, jsonEncode({'_voxa_media': true, 'url': url, 'type': type, 'name': name, 'caption': ''}));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attachment failed: $error')));
    }
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    final channel = _channel;
    if (content.isEmpty) return;
    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The live chat is not connected. Retry first.'),
        ),
      );
      return;
    }
    ApiClient.instance.sendMessage(channel, content);
    _messageController.clear();
  }
}
