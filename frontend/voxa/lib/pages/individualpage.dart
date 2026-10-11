import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/model/message_model.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:voxa/screens/userprofilescreen.dart';
import 'package:voxa/model/call_model.dart';
import 'package:voxa/screens/webrtc_call_screen.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/pages/chat_tools_page.dart';
import 'package:voxa/services/chat_summary_service.dart';
import 'package:voxa/services/media_upload_service.dart';
import 'package:voxa/pages/media_preview.dart';
import 'package:voxa/screens/editimage.dart';
import 'package:voxa/media/media_result.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class IndividualPage extends StatefulWidget {
  const IndividualPage({super.key, required this.chatModel});
  final ChatModel chatModel;

  @override
  State<IndividualPage> createState() => _IndividualPageState();
}

class _IndividualPageState extends State<IndividualPage> {
  static const MethodChannel _voiceRecorder = MethodChannel(
    'com.voxa/audio_recorder',
  );
  final TextEditingController _messageController = TextEditingController();
  final List<MessageModel> messages = [];
  final ScrollController _messageScroll = ScrollController();
  bool isTyping = false;
  final FocusNode _focusNode = FocusNode();
  bool showEmojiPicker = false;
  bool _isLoading = true;
  CallMedia? _startingCallMedia;
  String? _chatError;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _chatConnected = false;
  bool _sendingText = false;
  late bool _muted;
  DateTime? _clearedBefore;
  bool _clearing = false;
  bool _isRecordingVoice = false;

  @override
  void initState() {
    super.initState();
    _muted = widget.chatModel.muted;

    _messageController.addListener(_handleMessageChanged);
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController
      ..removeListener(_handleMessageChanged)
      ..dispose();
    _focusNode.dispose();
    _messageScroll.dispose();
    if (_isRecordingVoice) {
      _voiceRecorder.invokeMethod<void>('cancel').ignore();
    }
    ApiClient.instance.chatDisconnected(_channel);
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
      ApiClient.instance.chatDisconnected(_channel);
      await _subscription?.cancel();
      await _channel?.sink.close();
      final channel = await ApiClient.instance.connectToChat(chatId);
      if (!mounted) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleSocketEvent,
        onError: (Object _) {
          ApiClient.instance.chatDisconnected(channel);
          _chatConnected = false;
          if (mounted) setState(() => _chatError = 'Live connection lost.');
        },
        onDone: () {
          ApiClient.instance.chatDisconnected(channel);
          _chatConnected = false;
          if (mounted) setState(() => _chatError = 'Live connection closed.');
        },
      );
      _chatConnected = true;
      final history = await ApiClient.instance.loadMessages(chatId);
      if (!mounted) return;
      setState(() {
        for (final message in history) {
          if (!messages.any((item) => item.id == message.id)) {
            messages.add(message);
          }
        }
        messages.sort(_compareMessages);
        _isLoading = false;
      });
      _scrollToLatest();
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

  static int _compareMessages(MessageModel a, MessageModel b) {
    final order = (a.createdAt ?? DateTime(1970)).compareTo(
      b.createdAt ?? DateTime(1970),
    );
    return order != 0 ? order : (a.id ?? '').compareTo(b.id ?? '');
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _messageScroll.hasClients) {
        _messageScroll.jumpTo(_messageScroll.position.maxScrollExtent);
      }
    });
  }

  void _handleSocketEvent(dynamic event) {
    try {
      final decoded = jsonDecode(event as String) as Map<String, dynamic>;
      ApiClient.instance.handleChatEvent(_channel, decoded);
      if (decoded['type'] == 'history_cleared') {
        final cutoff = DateTime.parse(decoded['cleared_before'] as String);
        if (mounted) {
          setState(() {
            _clearedBefore = cutoff;
            messages.removeWhere(
              (message) =>
                  message.createdAt == null ||
                  !message.createdAt!.isAfter(cutoff),
            );
          });
        }
        return;
      }
      if (decoded['type'] == 'message' &&
          decoded['message'] is Map<String, dynamic>) {
        final message = MessageModel.fromJson(
          decoded['message'] as Map<String, dynamic>,
        );
        if (_clearedBefore != null &&
            message.createdAt != null &&
            !message.createdAt!.isAfter(_clearedBefore!)) {
          return;
        }
        if (mounted && !messages.any((item) => item.id == message.id)) {
          final followLatest =
              message.isMe ||
              !_messageScroll.hasClients ||
              _messageScroll.position.extentAfter < 120;
          setState(() {
            messages.add(message);
            messages.sort(_compareMessages);
          });
          if (followLatest) _scrollToLatest();
        }
      } else if (decoded['type'] == 'error' && mounted) {
        final error =
            decoded['error'] as String? ?? 'Message could not be sent.';
        setState(() => _chatError = error);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _chatError = 'Received an invalid chat event.');
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _sendingText) return;
    _sendingText = true;
    try {
      final sent = await _sendChatContent(content);
      if (sent && mounted && _messageController.text.trim() == content) {
        _messageController.clear();
      }
    } finally {
      _sendingText = false;
    }
  }

  Future<bool> _sendChatContent(String content) async {
    try {
      if (!_chatConnected) {
        await _initializeChat();
      }
      final activeChannel = _channel;
      if (!_chatConnected || activeChannel == null) {
        throw StateError(
          _chatError ??
              'The chat connection is unavailable. Retry in a moment.',
        );
      }
      await ApiClient.instance.sendMessage(activeChannel, content);
      return true;
    } catch (error) {
      if (mounted) {
        final message = 'Could not send message: $error';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
      return false;
    }
  }

  Future<void> _startVoiceRecording() async {
    try {
      await _voiceRecorder.invokeMethod<void>('start');
      if (mounted) setState(() => _isRecordingVoice = true);
    } on PlatformException catch (error) {
      if (mounted) {
        _showCallError(error.message ?? 'Microphone permission is required.');
      }
    } catch (error) {
      if (mounted) _showCallError('Could not start voice recording: $error');
    }
  }

  Future<void> _stopAndSendVoiceRecording() async {
    try {
      final path = await _voiceRecorder.invokeMethod<String>('stop');
      if (mounted) setState(() => _isRecordingVoice = false);
      if (path == null || path.isEmpty) {
        throw StateError('The recording was empty.');
      }
      await _uploadAndSend(File(path), 'audio', 'Voice message.m4a');
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _isRecordingVoice = false);
        _showCallError(
          error.message ?? 'Could not finish the voice recording.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isRecordingVoice = false);
        _showCallError('Could not send voice recording: $error');
      }
    }
  }

  Future<void> _startCall(CallMedia media) async {
    if (_startingCallMedia != null) return;
    final peerId = widget.chatModel.peerId;
    if (widget.chatModel.isGroup == true ||
        widget.chatModel.isCommunity == true ||
        peerId == null ||
        peerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This chat has no registered Voxa user to call.'),
        ),
      );
      return;
    }
    setState(() => _startingCallMedia = media);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            media == CallMedia.video
                ? 'Connecting video call…'
                : 'Connecting voice call…',
          ),
          duration: const Duration(seconds: 30),
        ),
      );
    try {
      final call = await ApiClient.instance.createCall(
        peerId: peerId,
        media: media,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
        _showCallError(error.message);
      }
    } catch (error) {
      if (mounted) {
        _showCallError('Could not start the call: $error');
      }
    } finally {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        setState(() => _startingCallMedia = null);
      }
    }
  }

  void _showCallError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openChatTools({bool search = false}) {
    final id = widget.chatModel.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatToolsPage(
          chatId: id,
          chatName: widget.chatModel.name,
          search: search,
        ),
      ),
    );
  }

  Future<void> _toggleMute() async {
    final id = widget.chatModel.id;
    if (id == null) return;
    try {
      await ApiClient.instance.setChatMuted(id, !_muted);
      if (!mounted) return;
      setState(() => _muted = !_muted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _muted ? 'In-app chat alerts muted' : 'In-app chat alerts enabled',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save mute setting: $error')),
        );
      }
    }
  }

  Future<void> _clearHistory() async {
    if (_clearing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear chat history for you?'),
        content: const Text(
          'Previous messages will be removed from your history. Other participants keep their copies. New messages will still appear.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = widget.chatModel.id;
    if (id == null) return;
    _clearing = true;
    try {
      final cutoff = await ApiClient.instance.clearChatHistory(id);
      if (!mounted) return;
      setState(() {
        _clearedBefore = cutoff;
        messages.removeWhere(
          (message) =>
              message.createdAt == null || !message.createdAt!.isAfter(cutoff),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat history cleared for you')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not clear history: $error')),
        );
      }
    } finally {
      _clearing = false;
    }
  }

  void _showSmartRecap() {
    final summary = ChatSummaryService.summarize(
      messages,
      chatName: widget.chatModel.name.isEmpty
          ? 'This chat'
          : widget.chatModel.name,
    );

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Conversation overview'),
        content: Text(summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            // HEADER
            ColoredBox(
              color: const Color(0xFF0C544B),
              child: SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0C544B), Color(0xFF113E39)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1A0F2B2A),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFE8F3ED),
                        child: Icon(
                          widget.chatModel.isGroup == true
                              ? Icons.groups_2_rounded
                              : Icons.person_rounded,
                          color: const Color(0xFF168A62),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.chatModel.name.isEmpty
                                  ? 'Conversation'
                                  : widget.chatModel.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF7AE7B2),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  widget.chatModel.isGroup == true
                                      ? 'Group conversation'
                                      : (widget.chatModel.peerPhone ??
                                            'Active now'),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Start video call',
                            onPressed: _startingCallMedia != null
                                ? null
                                : () => _startCall(CallMedia.video),
                            icon: _startingCallMedia == CallMedia.video
                                ? const SizedBox(
                                    width: 21,
                                    height: 21,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.videocam_outlined,
                                    color: Colors.white,
                                  ),
                          ),
                          IconButton(
                            tooltip: 'Start voice call',
                            onPressed: _startingCallMedia != null
                                ? null
                                : () => _startCall(CallMedia.audio),
                            icon: _startingCallMedia == CallMedia.audio
                                ? const SizedBox(
                                    width: 21,
                                    height: 21,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.call_outlined,
                                    color: Colors.white,
                                  ),
                          ),
                          PopupMenuButton<String>(
                            color: Colors.white,
                            icon: const Icon(
                              Icons.more_horiz_rounded,
                              color: Colors.white,
                            ),
                            onSelected: (value) {
                              switch (value) {
                                case "View Contact":
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => UserProfileScreen(
                                        name: widget.chatModel.name,
                                        status: '',
                                        lastSeen: '',
                                        phone: widget.chatModel.peerPhone ?? '',
                                        imageUrl: null,
                                      ),
                                    ),
                                  );
                                  break;
                                case "Conversation overview":
                                  _showSmartRecap();
                                  break;
                                case 'Media, Links, and Docs':
                                  _openChatTools();
                                  break;
                                case 'Search':
                                  _openChatTools(search: true);
                                  break;
                                case 'Mute Notifications':
                                  _toggleMute();
                                  break;
                                case 'Clear history':
                                  _clearHistory();
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
                                  value: "Conversation overview",
                                  child: Text(
                                    "Conversation overview",
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
                                PopupMenuItem(
                                  value: "Mute Notifications",
                                  child: Text(
                                    _muted
                                        ? 'Unmute in-app alerts'
                                        : 'Mute in-app alerts',
                                    style: TextStyle(color: Color(0xFF26362E)),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'Clear history',
                                  child: Text('Clear history'),
                                ),
                              ];
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // BODY - Chat area (Gradient Background)
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFF7FBF9), Color(0xFFEAF3F0)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
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
                              controller: _messageScroll,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
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
                                          MediaQuery.of(context).size.width *
                                          0.76,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: message.isMe
                                          ? const Color(0xFFDAF3E5)
                                          : Colors.white,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(18),
                                        topRight: const Radius.circular(18),
                                        bottomLeft: Radius.circular(
                                          message.isMe ? 18 : 6,
                                        ),
                                        bottomRight: Radius.circular(
                                          message.isMe ? 6 : 18,
                                        ),
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x0D17251F),
                                          blurRadius: 12,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (widget.chatModel.isGroup == true &&
                                            !message.isMe)
                                          Text(
                                            message.sender.isEmpty
                                                ? 'Member'
                                                : message.sender,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F6F3),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.emoji_emotions_outlined,
                              size: 23,
                              color: Colors.grey.shade700,
                            ),
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              setState(() {
                                showEmojiPicker = !showEmojiPicker;
                              });
                            },
                          ),
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
                          IconButton(
                            icon: Icon(
                              Icons.attach_file,
                              size: 23,
                              color: Colors.grey.shade700,
                            ),
                            onPressed: () {
                              showModalBottomSheet(
                                backgroundColor: Colors.transparent,
                                context: context,
                                builder: (builder) => bottomSheet(),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.camera_alt,
                              size: 23,
                              color: Colors.grey.shade700,
                            ),
                            onPressed: () {
                              openCamera();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF168A62),
                    child: IconButton(
                      icon: Icon(
                        _isRecordingVoice
                            ? Icons.stop
                            : (isTyping ? Icons.send : Icons.mic),
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: _isRecordingVoice
                          ? _stopAndSendVoiceRecording
                          : (isTyping ? _sendMessage : _startVoiceRecording),
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
    if (message.mediaUrl == null) {
      final location = _locationCoordinates(message.message);
      if (location != null) {
        final mapUrl =
            Uri.https('staticmap.openstreetmap.de', '/staticmap.php', {
              'center': '${location.$1},${location.$2}',
              'zoom': '15',
              'size': '560x300',
              'maptype': 'mapnik',
              'markers': '${location.$1},${location.$2},red-pushpin',
            });
        return SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  mapUrl.toString(),
                  width: 240,
                  height: 135,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 240,
                    height: 135,
                    color: const Color(0xFFE8F3ED),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.map_outlined,
                      size: 42,
                      color: Color(0xFF168A62),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.location_on, color: Color(0xFF168A62), size: 18),
                  SizedBox(width: 5),
                  Text(
                    'Shared location',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${location.$1.toStringAsFixed(5)}, ${location.$2.toStringAsFixed(5)}',
                style: const TextStyle(color: Color(0xFF64736B), fontSize: 12),
              ),
            ],
          ),
        );
      }
      return Text(
        message.message,
        style: const TextStyle(color: Color(0xFF26362E)),
      );
    }
    if (message.mediaType == 'image') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              message.mediaUrl!,
              width: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image, color: Color(0xFF75827B)),
            ),
          ),
          if (message.message.isNotEmpty && message.message != 'Image')
            Text(
              message.message,
              style: const TextStyle(color: Color(0xFF26362E)),
            ),
        ],
      );
    }
    return InkWell(
      onTap: () {
        if (message.mediaType == 'video' || message.mediaType == 'audio') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MediaPreview(
                url: message.mediaUrl!,
                isAudio: message.mediaType == 'audio',
              ),
            ),
          );
        } else {
          showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(message.mediaName ?? 'Attachment'),
              content: SelectableText(message.mediaUrl!),
            ),
          );
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            message.mediaType == 'video'
                ? Icons.play_circle
                : message.mediaType == 'audio'
                ? Icons.audiotrack
                : Icons.insert_drive_file,
            color: const Color(0xFF168A62),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.message.isNotEmpty
                  ? message.message
                  : (message.mediaName ?? 'Attachment'),
              style: const TextStyle(color: Color(0xFF26362E)),
            ),
          ),
        ],
      ),
    );
  }

  (double, double)? _locationCoordinates(String message) {
    const prefix = 'My location: ';
    if (!message.startsWith(prefix)) return null;
    final uri = Uri.tryParse(message.substring(prefix.length).trim());
    if (uri == null) return null;
    final coordinates = uri.queryParameters['q']?.split(',');
    if (coordinates == null || coordinates.length != 2) return null;
    final latitude = double.tryParse(coordinates[0]);
    final longitude = double.tryParse(coordinates[1]);
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return (latitude, longitude);
  }

  Future<void> _uploadAndSend(File file, String type, String name) async {
    var caption = '';
    if (type == 'image' || type == 'video') {
      if (!mounted) return;
      final edited = await Navigator.of(context).push<MediaResult>(
        MaterialPageRoute(
          builder: (_) => EditImage(file: file, isVideo: type == 'video'),
        ),
      );
      if (edited == null || !mounted) return;
      file = edited.file;
      caption = edited.caption;
      name = file.path.split(Platform.pathSeparator).last;
    }

    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploading attachment…')));
      final url = await MediaUploadService.upload(
        file,
        isVideo: type != 'image',
      );
      final sent = await _sendChatContent(
        jsonEncode({
          '_voxa_media': true,
          'url': url,
          'type': type,
          'name': name,
          'caption': caption,
        }),
      );
      if (!sent) {
        throw StateError('The chat server did not accept the attachment.');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Attachment failed: $error')));
      }
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
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (type == 'video') {
      final video = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 5),
      );
      if (video != null) {
        await _uploadAndSend(File(video.path), 'video', video.name);
      }
    } else if (type == 'image') {
      final image = await _imagePicker.pickImage(source: source);
      if (image != null) {
        await _uploadAndSend(File(image.path), 'image', image.name);
      }
    }
  }

  Future<void> pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);

    final file = result?.files.single;
    if (file != null && file.path != null) {
      await _uploadAndSend(File(file.path!), 'audio', file.name);
    }
  }

  Future<void> shareLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showCallError(
          'Turn on Location in the emulator settings, then try again.',
        );
        await Geolocator.openLocationSettings();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _showCallError('Allow Voxa to access location in app settings.');
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        _showCallError('Location permission was denied.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      final mapsUrl = Uri.https('maps.google.com', '/', {
        'q': '${position.latitude},${position.longitude}',
      });
      final sent = await _sendChatContent('My location: $mapsUrl');
      if (sent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Location shared.')));
      }
    } on TimeoutException {
      if (mounted) {
        _showCallError(
          'Could not get a location fix. Set a location in emulator controls and retry.',
        );
      }
    } catch (error) {
      if (mounted) _showCallError('Could not share location: $error');
    }
  }

  Future<void> openContactPicker() async {
    if (!await FlutterContacts.requestPermission()) return;

    final currentContext = context;
    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: true,
    );
    if (!mounted || !currentContext.mounted) return;

    showModalBottomSheet(
      context: currentContext,
      isScrollControlled: true,
      builder: (_) {
        return SizedBox(
          height: MediaQuery.of(currentContext).size.height * 0.7,
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
                  debugPrint(
                    'Selected: ${c.displayName} - ${c.phones.isNotEmpty ? c.phones.first.number : 'No number'}',
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
