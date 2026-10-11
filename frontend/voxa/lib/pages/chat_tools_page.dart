import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voxa/model/message_model.dart';
import 'package:voxa/pages/media_preview.dart';
import 'package:voxa/services/api_client.dart';

class ChatToolsPage extends StatefulWidget {
  const ChatToolsPage({
    super.key,
    required this.chatId,
    required this.chatName,
    this.search = false,
  });
  final String chatId;
  final String chatName;
  final bool search;
  @override
  State<ChatToolsPage> createState() => _ChatToolsPageState();
}

class _ChatToolsPageState extends State<ChatToolsPage> {
  final _query = TextEditingController();
  final _messages = <MessageModel>[];
  bool _loading = true;
  String? _error;
  int _category = 0;
  static final _links = RegExp(r'https?://[^\s<>]+');
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _messages.clear();
    });
    try {
      String? before;
      while (mounted) {
        final page = await ApiClient.instance.loadMessages(
          widget.chatId,
          beforeId: before,
        );
        if (!mounted) return;
        setState(() => _messages.addAll(page.reversed));
        if (page.length < 100) break;
        final next = page.first.id;
        if (next == null || next == before) break;
        before = next;
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      if (!Platform.isAndroid) {
        throw UnsupportedError(
          'Opening external links currently requires Android.',
        );
      }
      await const MethodChannel(
        'com.voxa/external_links',
      ).invokeMethod<void>('open', {'url': url});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open link: $error')));
      }
    }
  }

  Future<void> _openMedia(MessageModel message) async {
    final url = message.mediaUrl;
    if (url == null) return;
    if (message.mediaType == 'image') {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: InteractiveViewer(child: Image.network(url))),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    } else if (message.mediaType == 'video' || message.mediaType == 'audio') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              MediaPreview(url: url, isAudio: message.mediaType == 'audio'),
        ),
      );
    } else {
      await _openUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    final visible = _messages.where((message) {
      if (widget.search) {
        return query.isEmpty ||
            message.message.toLowerCase().contains(query) ||
            message.sender.toLowerCase().contains(query);
      }
      return switch (_category) {
        0 => {'image', 'video', 'audio'}.contains(message.mediaType),
        1 => _links.hasMatch(message.message) && message.mediaUrl == null,
        _ =>
          message.mediaUrl != null &&
              !{'image', 'video', 'audio'}.contains(message.mediaType),
      };
    }).toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C544B),
        title: Text(
          widget.search ? 'Search ${widget.chatName}' : 'Media, links and docs',
        ),
      ),
      body: Column(
        children: [
          if (widget.search)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search this conversation',
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Media')),
                  ButtonSegment(value: 1, label: Text('Links')),
                  ButtonSegment(value: 2, label: Text('Docs')),
                ],
                selected: {_category},
                onSelectionChanged: (value) =>
                    setState(() => _category = value.single),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      _loading
                          ? 'Loading conversation...'
                          : 'No matching messages',
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, index) {
                      final message = visible[index];
                      final links = _links
                          .allMatches(message.message)
                          .map((match) => match.group(0)!)
                          .toList();
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${message.sender} ? ${message.createdAt?.toLocal().toString().split('.').first ?? message.time}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              if (message.mediaUrl != null)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: message.mediaType == 'image'
                                      ? Image.network(
                                          message.mediaUrl!,
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                        )
                                      : const Icon(Icons.attach_file),
                                  title: Text(
                                    message.message.isNotEmpty
                                        ? message.message
                                        : (message.mediaName ?? 'Attachment'),
                                  ),
                                  onTap: () => _openMedia(message),
                                )
                              else
                                SelectableText(message.message),
                              for (final link in links)
                                TextButton(
                                  onPressed: () => _openUrl(link),
                                  child: Text(
                                    link,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
    );
  }
}
