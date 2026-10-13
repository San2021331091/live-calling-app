import 'package:voxa/customui/avatar_photo.dart';
import 'package:voxa/customui/chat_theme_picker.dart';
import 'package:voxa/customui/delete_chat_dialog.dart';
import 'package:voxa/services/attachment_actions.dart';
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
import 'package:voxa/model/call_model.dart';
import 'package:voxa/model/chatmodel.dart';
import 'package:voxa/model/message_model.dart';
import 'package:voxa/screens/webrtc_call_screen.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/pages/chat_tools_page.dart';
import 'package:voxa/customui/text_entry_dialog.dart';
import 'package:voxa/services/chat_summary_service.dart';
import 'package:voxa/services/media_upload_service.dart';
import 'package:voxa/pages/media_preview.dart';
import 'package:voxa/screens/editimage.dart';
import 'package:voxa/media/media_result.dart';
import 'package:voxa/services/chat_connection.dart';

class GroupChatPage extends StatefulWidget {
  final ChatModel group;
  final VoidCallback? onChanged;
  const GroupChatPage({super.key, required this.group, this.onChanged});

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool showEmojiPicker = false;

  final List<MessageModel> messages = [];
  final ScrollController _messageScroll = ScrollController();
  ChatConnection? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _isLoading = true;
  bool _sendingText = false;
  late bool _muted;
  late String _avatarUrl, _theme, _personalTheme, _sharedTheme;
  ChatPalette get _palette => ChatPalette.fromId(_theme);
  DateTime? _clearedBefore;
  bool _clearing = false;
  String? _chatError;
  late String _groupName;
  bool _isManagingGroup = false;

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _muted = widget.group.muted;
    _avatarUrl = widget.group.img;
    _theme = widget.group.theme;
    _personalTheme = widget.group.personalTheme;
    _sharedTheme = widget.group.sharedTheme;
    _groupName = widget.group.name;
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _focusNode.dispose();
    _messageScroll.dispose();
    ApiClient.instance.chatDisconnected(_channel);
    _subscription?.cancel();
    _channel?.close();
    super.dispose();
  }

  Future<void> _refreshAppearance() async {
    final id = widget.group.id;
    if (id == null) return;
    try {
      final appearance = await ApiClient.instance.loadChatAppearance(id);
      if (!mounted) return;
      setState(() {
        _avatarUrl = appearance['avatar_url'] as String? ?? '';
        _theme = appearance['theme'] as String? ?? 'classic';
        _personalTheme = appearance['personal_theme'] as String? ?? '';
        _sharedTheme = appearance['shared_theme'] as String? ?? 'classic';
        _groupName = appearance['name'] as String? ?? _groupName;
      });
    } catch (_) {
      /* Existing appearance remains usable; retry on reconnect. */
    }
  }

  Future<void> _chooseTheme() async {
    final id = widget.group.id;
    if (id == null) return;
    await _refreshAppearance();
    if (!mounted) return;
    final saved = await showChatThemePicker(
      context,
      chatId: id,
      personalTheme: _personalTheme,
      sharedTheme: _sharedTheme,
      isGroup: true,
      canManageShared: widget.group.isCreator,
    );
    if (saved == true) await _refreshAppearance();
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
      ApiClient.instance.chatDisconnected(_channel);
      await _subscription?.cancel();
      await _channel?.close();
      final channel = await ApiClient.instance.connectToChat(chatId);
      if (!mounted) {
        await channel.close();
        return;
      }
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleSocketEvent,
        onError: (Object _) {
          ApiClient.instance.chatDisconnected(channel);
          if (mounted) setState(() => _chatError = 'Live connection lost.');
        },
        onDone: () {
          ApiClient.instance.chatDisconnected(channel);
          if (mounted) setState(() => _chatError = 'Live connection closed.');
        },
      );
      await _refreshAppearance();
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
          _chatError =
              'Could not connect to this group. Check your connection.';
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
      if (decoded['type'] == 'appearance_changed') {
        unawaited(_refreshAppearance());
        return;
      }
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
        final message = ApiClient.instance.decodeMessage(
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
      backgroundColor: _palette.background,
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
      backgroundColor: _palette.header,
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_palette.header, _palette.header],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Row(
        children: [
          AvatarPhotoEditor(
            url: _avatarUrl,
            radius: 21,
            icon: Icons.groups_2_rounded,
            enabled: widget.group.isCreator && !_isManagingGroup,
            onSave: (url) async {
              await ApiClient.instance.updateGroupAppearance(
                widget.group.id!,
                avatarUrl: url,
              );
              if (mounted) setState(() => _avatarUrl = url);
              widget.onChanged?.call();
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _groupName.isEmpty ? 'Group' : _groupName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  "Group conversation",
                  style: TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _showSmartRecap,
          icon: const Icon(Icons.auto_awesome_outlined, color: Colors.white),
        ),
        IconButton(
          onPressed: () => _startGroupCall(CallMedia.video),
          icon: const Icon(Icons.videocam_outlined, color: Colors.white),
        ),
        IconButton(
          onPressed: () => _startGroupCall(CallMedia.audio),
          icon: const Icon(Icons.call_outlined, color: Colors.white),
        ),
        PopupMenuButton<String>(
          enabled: !_isManagingGroup,
          onSelected: (action) {
            if (action == 'theme') _chooseTheme();
            if (action == 'photo') _showGroupPhoto();
            if (action == 'edit') _editGroupName();
            if (action == 'delete') _deleteGroup();
            if (action == 'search') _openChatTools(search: true);
            if (action == 'media') _openChatTools();
            if (action == 'mute') _toggleMute();
            if (action == 'clear') _clearHistory();
            if (action == 'delete_inbox') _deleteInboxChat();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'theme', child: Text('Chat theme')),
            if (widget.group.isCreator)
              const PopupMenuItem(value: 'photo', child: Text('Edit photo')),
            const PopupMenuItem(value: 'search', child: Text('Search')),
            const PopupMenuItem(
              value: 'media',
              child: Text('Media, links and docs'),
            ),
            PopupMenuItem(
              value: 'mute',
              child: Text(
                _muted ? 'Unmute in-app alerts' : 'Mute in-app alerts',
              ),
            ),
            const PopupMenuItem(value: 'clear', child: Text('Clear history')),
            const PopupMenuItem(
              value: 'delete_inbox',
              child: Text('Delete chat'),
            ),
            if (widget.group.isCreator)
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text(
                    widget.group.isCommunity == true
                        ? 'Edit community'
                        : 'Edit group',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            if (widget.group.isCreator)
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                    widget.group.isCommunity == true
                        ? 'Delete community'
                        : 'Delete group',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _showGroupPhoto() {
    var photo = _avatarUrl;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, updateSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.group.isCommunity == true
                      ? 'Community photo'
                      : 'Group photo',
                ),
                const SizedBox(height: 16),
                AvatarPhotoEditor(
                  url: photo,
                  icon: Icons.groups_rounded,
                  onSave: (url) async {
                    await ApiClient.instance.updateGroupAppearance(
                      widget.group.id!,
                      avatarUrl: url,
                    );
                    if (mounted) {
                      setState(() => _avatarUrl = url);
                      widget.onChanged?.call();
                    }
                    if (sheetContext.mounted) updateSheet(() => photo = url);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editGroupName() async {
    if (_isManagingGroup) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TextEntryDialog(
        title: widget.group.isCommunity == true
            ? 'Edit community name'
            : 'Edit group name',
        label: 'Name',
        initial: _groupName,
      ),
    );
    if (!mounted) return;
    if (name == null || name.trim().isEmpty || name.trim() == _groupName) {
      return;
    }
    final chatId = widget.group.id;
    if (chatId == null) {
      _showGroupMessage('This group is not available.');
      return;
    }
    setState(() => _isManagingGroup = true);
    try {
      await ApiClient.instance.updateGroupName(chatId, name.trim());
      if (!mounted) return;
      setState(() => _groupName = name.trim());
      widget.onChanged?.call();
      _showGroupMessage('Group name updated.');
    } on ApiException catch (error) {
      if (mounted) _showGroupMessage(error.message);
    } catch (_) {
      if (mounted) _showGroupMessage('Could not update the group name.');
    } finally {
      if (mounted) setState(() => _isManagingGroup = false);
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          widget.group.isCommunity == true
              ? 'Delete this community?'
              : 'Delete this group?',
        ),
        content: const Text(
          'This removes the group and its message history for all members.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              widget.group.isCommunity == true
                  ? 'Delete community'
                  : 'Delete group',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final chatId = widget.group.id;
    if (chatId == null) {
      _showGroupMessage('This group is not available.');
      return;
    }
    setState(() => _isManagingGroup = true);
    try {
      await ApiClient.instance.deleteGroup(chatId);
      if (!mounted) return;
      widget.onChanged?.call();
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) _showGroupMessage(error.message);
    } catch (_) {
      if (mounted) _showGroupMessage('Could not delete the group.');
    } finally {
      if (mounted) setState(() => _isManagingGroup = false);
    }
  }

  void _showGroupMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _shareLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showGroupMessage(
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
        _showGroupMessage('Allow Voxa to access location in app settings.');
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        _showGroupMessage('Location permission was denied.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      final channel = _channel;
      if (channel == null) {
        _showGroupMessage('Connect to the chat before sharing your location.');
        return;
      }
      final mapsUrl = Uri.https('maps.google.com', '/', {
        'q': '${position.latitude},${position.longitude}',
      });
      await ApiClient.instance.sendMessage(channel, 'My location: $mapsUrl');
    } on TimeoutException {
      if (mounted) {
        _showGroupMessage(
          'Could not get a location fix. Set a location in emulator controls and retry.',
        );
      }
    } catch (error) {
      if (mounted) _showGroupMessage('Could not share location: $error');
    }
  }

  Future<void> _startGroupCall(CallMedia media) async {
    final chatId = widget.group.id;
    if (chatId == null || chatId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This group is not available for calls.')),
      );
      return;
    }

    try {
      final payload = await ApiClient.instance.startGroupCall(
        chatId: chatId,
        media: media,
      );
      final calls = payload['calls'];
      if (calls is! List || calls.isEmpty) {
        throw const ApiException('The group call could not be started.');
      }

      final participants = calls.map<GroupCallParticipant>((entry) {
        final call = entry as Map<String, dynamic>;
        final callId = call['id'] as String? ?? '';
        final peerId = call['peer_id'] as String? ?? '';
        final peerName = call['peer_name'] as String? ?? 'Participant';
        return GroupCallParticipant(
          callId: callId,
          peerId: peerId,
          peerName: peerName,
        );
      }).toList();

      final primaryParticipant = participants.firstWhere(
        (participant) =>
            participant.callId.isNotEmpty && participant.peerId.isNotEmpty,
        orElse: () => participants.first,
      );

      if (primaryParticipant.callId.isEmpty ||
          primaryParticipant.peerId.isEmpty) {
        throw const ApiException('The group call could not be started.');
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebRtcCallScreen(
            callId: primaryParticipant.callId,
            peerId: primaryParticipant.peerId,
            peerName: _groupName,
            peerAvatar: '',
            media: media,
            isIncoming: false,
            groupParticipants: participants,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not start the group call. Check your connection.',
            ),
          ),
        );
      }
    }
  }

  void _openChatTools({bool search = false}) {
    final id = widget.group.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatToolsPage(
          chatId: id,
          chatName: widget.group.name,
          search: search,
        ),
      ),
    );
  }

  Future<void> _toggleMute() async {
    final id = widget.group.id;
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
    final id = widget.group.id;
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
      chatName: _groupName.isEmpty ? 'This group' : _groupName,
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
                  controller: _messageScroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
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
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.76,
                        ),
                        decoration: BoxDecoration(
                          color: msg.isMe ? _palette.bubble : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(msg.isMe ? 18 : 6),
                            bottomRight: Radius.circular(msg.isMe ? 6 : 18),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0A17251F),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!msg.isMe)
                              Text(
                                msg.sender.isEmpty ? 'Member' : msg.sender,
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
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF849089),
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.emoji_emotions_outlined,
                      color: Color(0xFF79877F),
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
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.attach_file,
                      color: Color(0xFF168A62),
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _attachmentBottomSheet(),
                      );
                    },
                  ),
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
                pickDocument,
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
                              if (image != null) {
                                await _uploadAndSend(
                                  File(image.path),
                                  'image',
                                  image.name,
                                );
                              }
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
                              if (video != null) {
                                await _uploadAndSend(
                                  File(video.path),
                                  'video',
                                  video.name,
                                );
                              }
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
                            if (image != null) {
                              await _uploadAndSend(
                                File(image.path),
                                'image',
                                image.name,
                              );
                            }
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
                            if (video != null) {
                              await _uploadAndSend(
                                File(video.path),
                                'video',
                                video.name,
                              );
                            }
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
                  if (file != null && file.path != null) {
                    await _uploadAndSend(File(file.path!), 'audio', file.name);
                  }
                },
              ),
              _attachmentItem(
                Icons.location_on,
                "Location",
                Colors.green,
                _shareLocation,
              ),
              _attachmentItem(Icons.person, "Contact", Colors.blue, () async {
                if (!await FlutterContacts.requestPermission()) return;
                final currentContext = context;
                final contacts = await FlutterContacts.getContacts(
                  withProperties: true,
                );
                if (!mounted || !currentContext.mounted) return;

                // Show popup to pick contact
                showDialog(
                  context: currentContext,
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
                              debugPrint(
                                'Selected contact: ${contact.displayName}',
                              );
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
          Text(
            label,
            style: const TextStyle(color: Color(0xFF35433C), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _messageContent(MessageModel message) {
    if (message.mediaUrl == null) {
      return Text(
        message.message,
        style: const TextStyle(fontSize: 14, color: Color(0xFF26362E)),
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
          openAttachment(context, message.mediaUrl!);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            message.mediaType == 'video'
                ? Icons.play_circle
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

  Future<void> pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.path == null) {
        throw StateError(
          'This file cannot be read. Download it to your device first.',
        );
      }
      await _uploadAndSend(File(file.path!), 'document', file.name);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select file: $error')),
        );
      }
    }
  }

  Future<void> _deleteInboxChat() async {
    final deleted = await deleteChatFromInbox(context, widget.group.id!);
    if (deleted && mounted) Navigator.of(context).pop(true);
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

    final channel = _channel;
    if (channel == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chat is not connected.')));
      }
      return;
    }
    try {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Uploading attachment…')));
      }
      final url = await MediaUploadService.upload(
        file,
        isVideo: type != 'image',
        isDocument: type == 'document',
        fileName: name,
      );
      await ApiClient.instance.sendMessage(
        channel,
        jsonEncode({
          '_voxa_media': true,
          'url': url,
          'type': type,
          'name': name,
          'caption': caption,
        }),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Attachment failed: $error')));
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    final channel = _channel;
    if (content.isEmpty || _sendingText) return;
    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The live chat is not connected. Retry first.'),
        ),
      );
      return;
    }
    _sendingText = true;
    try {
      await ApiClient.instance.sendMessage(channel, content);
      if (mounted && _messageController.text.trim() == content) {
        _messageController.clear();
      }
    } catch (error) {
      if (mounted) _showGroupMessage('Could not send message: $error');
    } finally {
      _sendingText = false;
    }
  }
}
