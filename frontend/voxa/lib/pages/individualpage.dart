import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/model/message_model.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:voxa/screens/userprofilescreen.dart';
import 'package:voxa/model/call_model.dart';
import 'package:voxa/screens/webrtc_call_screen.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/services/media_upload_service.dart';
import 'package:voxa/pages/media_preview.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class IndividualPage extends StatefulWidget {
  const IndividualPage({super.key, required this.chatModel});
  final ChatModel chatModel;

  

  @override
  State<IndividualPage> createState() => _IndividualPageState();
}

class _IndividualPageState extends State<IndividualPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<MessageModel> messages = [];
  bool isTyping = false;
  final FocusNode _focusNode = FocusNode();
  bool showEmojiPicker = false;
  bool _isLoading = true;
  String? _chatError;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  @override
  void initState() {
    super.initState();

    _messageController.addListener(_handleMessageChanged);
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController
      ..removeListener(_handleMessageChanged)
      ..dispose();
    _focusNode.dispose();
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  void _handleMessageChanged() {
    if (mounted) {
      setState(() => isTyping = _messageController.text.trim().isNotEmpty);
    }
  }

  Future<void> _initializeChat() async {
    final chatId = widget.chatModel.id;
    if (chatId == null) {
      setState(() {
        _isLoading = false;
        _chatError = 'Start this conversation from your registered contacts.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _chatError = null;
    });
    try {
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
          _chatError = 'Could not connect to the chat. Check your connection.';
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
      if (mounted) setState(() => _chatError = 'Received an invalid chat event.');
    }
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    final channel = _channel;
    if (content.isEmpty) return;
    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The live chat is not connected. Retry first.')),
      );
      return;
    }
    ApiClient.instance.sendMessage(channel, content);
    _messageController.clear();
  }

  Future<void> _startCall(CallMedia media) async {
    final peerId = widget.chatModel.peerId;
    if (widget.chatModel.isGroup == true ||
        widget.chatModel.isCommunity == true ||
        peerId == null ||
        peerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calls are available in direct chats with registered users.')),
      );
      return;
    }
    try {
      final call = await ApiClient.instance.createCall(peerId: peerId, media: media);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebRtcCallScreen(
            callId: call.id,
            peerId: peerId,
            peerName: widget.chatModel.name,
            peerAvatar: '',
            media: media,
            isIncoming: false,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      body: Column(
        children: [
          // HEADER
          Container(
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE8ECE9))),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF34433B)),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFE8F3ED),
                  child: Icon(widget.chatModel.isGroup == true ? Icons.groups_2_rounded : Icons.person_rounded, color: const Color(0xFF168A62), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.chatModel.name,
                        style: const TextStyle(
                          color: Color(0xFF17251F),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(widget.chatModel.isGroup == true ? 'Group conversation' : (widget.chatModel.peerPhone ?? 'Conversation'), style: const TextStyle(color: Color(0xFF75827B), fontSize: 10.5)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _startCall(CallMedia.video),
                      icon: const Icon(Icons.videocam_outlined, color: Color(0xFF168A62)),
                    ),
                    IconButton(
                      onPressed: () => _startCall(CallMedia.audio),
                      icon: const Icon(Icons.call_outlined, color: Color(0xFF168A62)),
                    ),
                    PopupMenuButton<String>(
                      color: Colors.white,
                      icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF536159)),
                      onSelected: (value) {
                        switch (value) {
                          case "View Contact":
                            {}
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfileScreen(
                                  name: widget.chatModel.name,
                                  status: "Hey there! I am using Voxa",
                                  lastSeen: "Last seen today at 12:00 PM",
                                  phone: "+880 1234 567890",
                                  imageUrl: "https://i.pravatar.cc/150?img=1",
                                ),
                              ),
                            );

                            break;
                          default:
                        }
                      },
                      itemBuilder: (BuildContext context) {
                        return [
                          const PopupMenuItem(
                            value: "View Contact",
                            child: Text(
                              "View Contact",
                              style: TextStyle(color: Color(0xFF26362E)),
                            ),
                          ),
                          const PopupMenuItem(
                            value: "Media, Links, and Docs",
                            child: Text(
                              "Media, Links, and Docs",
                              style: TextStyle(color: Color(0xFF26362E)),
                            ),
                          ),
                          const PopupMenuItem(
                            value: "Search",
                            child: Text(
                              "Search",
                              style: TextStyle(color: Color(0xFF26362E)),
                            ),
                          ),
                          const PopupMenuItem(
                            value: "Mute Notifications",
                            child: Text(
                              "Mute Notifications",
                              style: TextStyle(color: Color(0xFF26362E)),
                            ),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          // BODY - Chat area (Gradient Background)
          Expanded(
            child: Container(
              color: const Color(0xFFF4F7F5),
              child: Column(
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
                              horizontal: 8,
                              vertical: 10,
                            ),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              return Align(
                                alignment: message.isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width * 0.75,
                                  ),
                                  padding: const EdgeInsets.all(10),
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 5),
                                  decoration: BoxDecoration(
                                    color: message.isMe ? const Color(0xFFDDF4E7) : Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: Radius.circular(message.isMe ? 18 : 5),
                                      bottomRight: Radius.circular(message.isMe ? 5 : 18),
                                    ),
                                    boxShadow: const [BoxShadow(color: Color(0x0A17251F), blurRadius: 10, offset: Offset(0, 3))],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (widget.chatModel.isGroup == true &&
                                          !message.isMe)
                                        Text(
                                          message.sender,
                                          style: const TextStyle(
                                            color: Color(0xFF168A62),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      _messageContent(message),
                                      Align(
                                        alignment: Alignment.bottomRight,
                                        child: Text(
                                          message.time,
                                          style: const TextStyle(
                                            color: Color(0xFF849089),
                                            fontSize: 10,
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
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: Colors.white,
            child: Row(
              children: [
                // Message field
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4F1),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      children: [
                        // Emoji
                        IconButton(
                          icon: Icon(
                            Icons.emoji_emotions_outlined,
                            size: 26,
                            color: Colors.grey.shade700,
                            weight: 900,
                          ),
                          onPressed: () {
                            FocusScope.of(context).unfocus(); // hide keyboard
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
                            maxLines: 5,
                            minLines: 1,
                            decoration: const InputDecoration(
                              hintText: "Message",
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

                        // Attach
                        IconButton(
                          icon: Icon(
                            Icons.attach_file,
                            size: 26,
                            color: Colors.grey.shade700,
                            weight: 600,
                          ),
                          onPressed: () {
                            showModalBottomSheet(
                              backgroundColor: Colors.transparent,
                              context: context,
                              builder: (builder) => bottomSheet(),
                            );
                          },
                        ),

                        // Camera
                        IconButton(
                          icon: Icon(
                            Icons.camera_alt,
                            size: 26,
                            color: Colors.grey.shade700,
                            weight: 700,
                          ),
                          onPressed: () {
                            openCamera();
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Mic / Send button
                CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(0xFF168A62),
                  child: IconButton(
                    icon: Icon(
                      isTyping ? Icons.send : Icons.mic,
                      color: Colors.white,
                      size: 26,
                      weight: 700,
                    ),
                    onPressed: isTyping ? _sendMessage : null,
                  ),
                ),
              ],
            ),
          ),

          Offstage(
            offstage: !showEmojiPicker,
            child: SizedBox(
              height: 256, // fixed height solves unbounded constraint
              child: EmojiPicker(
                textEditingController: _messageController,
                onEmojiSelected: (category, emoji) {},
                onBackspacePressed: () {
                  _messageController.text = _messageController.text.characters
                      .skipLast(1)
                      .toString();
                  _messageController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _messageController.text.length),
                  );
                },
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
                  viewOrderConfig: const ViewOrderConfig(
                    top: EmojiPickerItem.categoryBar,
                    middle: EmojiPickerItem.emojiView,
                    bottom: EmojiPickerItem.searchBar,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget bottomSheet() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      height: 300,
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
                icon: Icons.insert_drive_file,
                label: "Document",
                color: const Color(0xFF6078D8),
                onTap: () {
                  Navigator.pop(context);
                  pickDocument();
                },
              ),
              _attachmentItem(
                icon: Icons.camera_alt,
                label: "Camera",
                color: const Color(0xFFDB6990),
                onTap: () {
                  Navigator.pop(context);
                  openCamera();
                },
              ),
              _attachmentItem(
                icon: Icons.photo,
                label: "Gallery",
                color: const Color(0xFF8C6CD3),
                onTap: () {
                  Navigator.pop(context);
                  pickImage();
                },
              ),
            ],
          ),

          const SizedBox(height: 30),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _attachmentItem(
                icon: Icons.headphones,
                label: "Audio",
                color: const Color(0xFFDA9654),
                onTap: () {
                  Navigator.pop(context);
                  pickAudio();
                },
              ),
              _attachmentItem(
                icon: Icons.location_on,
                label: "Location",
                color: const Color(0xFF168A62),
                onTap: () {
                  Navigator.pop(context);
                  shareLocation();
                },
              ),
              _attachmentItem(
                icon: Icons.person,
                label: "Contact",
                color: const Color(0xFF578FA8),
                onTap: () {
                  Navigator.pop(context);
                  openContactPicker();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _messageContent(MessageModel message) {
    if (message.mediaUrl == null) return Text(message.message, style: const TextStyle(color: Color(0xFF26362E)));
    if (message.mediaType == 'image') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(message.mediaUrl!, width: 220, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Color(0xFF75827B)))),
        if (message.message.isNotEmpty && message.message != 'Image') Text(message.message, style: const TextStyle(color: Color(0xFF26362E))),
      ]);
    }
    return InkWell(onTap: () {
      if (message.mediaType == 'video') {
        Navigator.push(context, MaterialPageRoute(builder: (_) => MediaPreview(url: message.mediaUrl!)));
      } else {
        showDialog<void>(context: context, builder: (_) => AlertDialog(title: Text(message.mediaName ?? 'Attachment'), content: SelectableText(message.mediaUrl!)));
      }
    }, child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(message.mediaType == 'video' ? Icons.play_circle : Icons.insert_drive_file, color: const Color(0xFF168A62)),
      const SizedBox(width: 8), Flexible(child: Text(message.mediaName ?? message.message, style: const TextStyle(color: Color(0xFF26362E)))),
    ]));
  }

  Future<void> _uploadAndSend(File file, String type, String name) async {
    final channel = _channel;
    if (channel == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat is not connected.'))); return; }
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading attachment…')));
      final url = await MediaUploadService.upload(file, isVideo: type != 'image');
      await ApiClient.instance.sendMessage(channel, jsonEncode({'_voxa_media': true, 'url': url, 'type': type, 'name': name, 'caption': ''}));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attachment failed: $error')));
    }
  }

  Widget _attachmentItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF35433C)),
          ),
        ],
      ),
    );
  }

  Future<void> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'zip'],
    );

    if (result != null) {
      final file = result.files.single;
      final path = file.path;
      if (path != null) await _uploadAndSend(File(path), 'document', file.name);
    }
  }

  final ImagePicker _imagePicker = ImagePicker();

  Future<void> pickImage() async {
    await _chooseMedia(ImageSource.gallery);
  }

  Future<void> openCamera() async {
    await _chooseMedia(ImageSource.camera);
  }

  Future<void> _chooseMedia(ImageSource source) async {
    final type = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.photo), title: const Text('Photo'), onTap: () => Navigator.pop(context, 'image')),
      ListTile(leading: const Icon(Icons.videocam), title: const Text('Video'), onTap: () => Navigator.pop(context, 'video')),
    ])));
    if (type == 'video') {
      final video = await _imagePicker.pickVideo(source: source, maxDuration: const Duration(minutes: 5));
      if (video != null) await _uploadAndSend(File(video.path), 'video', video.name);
    } else if (type == 'image') {
      final image = await _imagePicker.pickImage(source: source);
      if (image != null) await _uploadAndSend(File(image.path), 'image', image.name);
    }
  }

  Future<void> pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);

    final file = result?.files.single;
    if (file != null && file.path != null) await _uploadAndSend(File(file.path!), 'audio', file.name);
  }

  Future<void> shareLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition();
    print("Location: ${position.latitude}, ${position.longitude}");
  }

  Future<void> openContactPicker() async {
    if (!await FlutterContacts.requestPermission()) return;

    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: true,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (_, index) {
              final c = contacts[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    c.displayName.isNotEmpty ? c.displayName[0] : "?",
                  ),
                ),
                title: Text(c.displayName),
                subtitle: Text(
                  c.phones.isNotEmpty ? c.phones.first.number : "No number",
                ),
                onTap: () {
                  Navigator.pop(context);
                  print(
                    "Selected: ${c.displayName} - ${c.phones.isNotEmpty ? c.phones.first.number : 'No number'}",
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
