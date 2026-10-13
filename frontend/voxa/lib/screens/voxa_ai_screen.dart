import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:voxa/customui/voxa_ai_tile.dart';
import 'package:voxa/services/api_client.dart';

class VoxaAIScreen extends StatefulWidget {
  const VoxaAIScreen({super.key});
  @override
  State<VoxaAIScreen> createState() => _VoxaAIScreenState();
}

class _AIVideoScreen extends StatefulWidget {
  const _AIVideoScreen({required this.url});
  final String url;
  @override
  State<_AIVideoScreen> createState() => _AIVideoScreenState();
}

class _AIVideoScreenState extends State<_AIVideoScreen>
    with WidgetsBindingObserver {
  late final VideoPlayerController _controller;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await _controller.initialize();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load this video. Open its source instead.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_controller.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Video'),
      backgroundColor: const Color(0xFF075E54),
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: _error != null
          ? Text(_error!)
          : !_controller.value.isInitialized
          ? const CircularProgressIndicator()
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                ),
                VideoProgressIndicator(_controller, allowScrubbing: true),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _controller,
                  builder: (_, value, _) => IconButton(
                    tooltip: value.isPlaying ? 'Pause' : 'Play',
                    icon: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: () => value.isPlaying
                        ? _controller.pause()
                        : _controller.play(),
                  ),
                ),
              ],
            ),
    ),
  );
}

class _VoxaAIScreenState extends State<VoxaAIScreen>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _turns = [];
  Timer? _timer;
  bool _loading = true, _fetching = false, _sending = false, _clearing = false;
  bool _available = false, _hasMore = false;
  String? _error, _requestId, _requestText;
  String _mode = 'chat';
  String? _requestMode;
  int _epoch = 0;
  bool get _pending =>
      _turns.any((t) => t['status'] == 'queued' || t['status'] == 'processing');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
      _startPolling();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool earlier = false}) async {
    if (_fetching || _clearing || !mounted) return;
    _fetching = true;
    final epoch = _epoch;
    try {
      final result = await ApiClient.instance.loadAIConversation(
        before: earlier && _turns.isNotEmpty
            ? (_turns.first['id'] as num).toInt()
            : null,
      );
      if (!mounted || epoch != _epoch) return;
      final incoming = (result['turns'] as List).cast<Map<String, dynamic>>();
      final merged = {for (final t in _turns) t['id']: t};
      // Empty/latest truncated history also reflects clears made on another device.
      if (!earlier && result['has_more'] != true) merged.clear();
      for (final t in incoming) {
        merged[t['id']] = t;
      }
      setState(() {
        _turns = merged.values.toList()
          ..sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));
        _available = result['available'] == true;
        if (earlier || _loading || result['has_more'] != true) {
          _hasMore = result['has_more'] == true;
        }
        _loading = false;
        _error = null;
      });
      // A timed-out POST may already have saved the message. Reconcile its ID.
      if (_requestId != null &&
          _turns.any((t) => t['client_id'] == _requestId)) {
        if (_input.text.trim() == _requestText) _input.clear();
        _requestId = null;
        _requestText = null;
      }
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _loading = false;
          _error = error is ApiException
              ? error.message
              : 'Could not load VoxaAI. Check your connection.';
        });
      }
    } finally {
      _fetching = false;
    }
  }

  String _newRequestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _pending || _clearing || !_available) {
      return;
    }
    if (_requestText != text || _requestId == null || _requestMode != _mode) {
      _requestId = _newRequestId();
      _requestText = text;
      _requestMode = _mode;
    }
    setState(() => _sending = true);
    try {
      await ApiClient.instance.sendAIMessage(text, _requestId!, mode: _mode);
      if (!mounted) return;
      if (_input.text.trim() == text) _input.clear();
      _requestId = null;
      _requestText = null;
      await _refresh();
      if (_scroll.hasClients) {
        unawaited(
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Message could not be confirmed. Your draft is still here.',
            ),
          ),
        );
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete VoxaAI conversation?'),
        content: const Text(
          'This removes your VoxaAI history from all devices signed in to this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _clearing = true;
      _epoch++;
    });
    try {
      await ApiClient.instance.clearAIConversation();
      if (mounted) {
        setState(() {
          _turns = [];
          _hasMore = false;
          _requestId = null;
          _requestText = null;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not clear history. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
    await _refresh();
  }

  Widget _welcome() => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        const VoxaAIAvatar(size: 88),
        const SizedBox(height: 20),
        const Text(
          'Hi, I’m VoxaAI',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'A little help for your next idea.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        for (final prompt in [
          'Help me write a friendly message',
          'Explain a topic in simple words',
          'Give me ideas for my day',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: () {
                _input.text = prompt;
              },
              child: Text(prompt),
            ),
          ),
      ],
    ),
  );

  Widget _bubble(String text, {required bool mine, bool copy = false}) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .86,
      ),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFFD9F4E4) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'VoxaAI',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF087C8B),
                ),
              ),
            ),
          SelectableText.rich(
            _replySpan(text),
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          if (copy)
            IconButton(
              tooltip: 'Copy response',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined, size: 17),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Response copied')),
                  );
                }
              },
            ),
        ],
      ),
    ),
  );

  TextSpan _replySpan(String text) {
    final boldPattern = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in boldPattern.allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      offset = match.end;
    }
    if (offset < text.length || spans.isEmpty) {
      spans.add(TextSpan(text: text.substring(offset)));
    }
    return TextSpan(children: spans);
  }

  String _replyText(Map<String, dynamic> turn) {
    final reply = turn['reply'] as String;
    if (turn['mode'] != 'photos' && turn['mode'] != 'videos') return reply;
    // Keep older saved media responses consistent with the current labels.
    return reply
        .replaceAll(' from Pexels.', '.')
        .replaceAll('No matching Pexels results.', 'No matching results.')
        .replaceAll(
          'Pexels search is not configured',
          'Media search is not configured',
        );
  }

  Widget _turn(Map<String, dynamic> turn) => Column(
    children: [
      _bubble(turn['prompt'] as String, mine: true),
      if (turn['mode'] != null && turn['mode'] != 'chat')
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${turn['mode']} search',
            style: const TextStyle(color: Color(0xFF55776D)),
          ),
        ),
      if (turn['status'] == 'complete')
        _bubble(_replyText(turn), mine: false, copy: true)
      else if (turn['status'] == 'failed')
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bubble(turn['error'] as String, mine: false),
            TextButton(
              onPressed: _pending || _sending
                  ? null
                  : () {
                      _input.text = turn['prompt'] as String;
                      setState(() => _mode = turn['mode'] as String? ?? 'chat');
                    },
              child: const Text('Use question again'),
            ),
          ],
        )
      else
        const Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('VoxaAI is thinking…'),
              ],
            ),
          ),
        ),
      for (final result in (turn['results'] as List? ?? []))
        _resultCard(Map<String, dynamic>.from(result as Map)),
    ],
  );

  Future<void> _openSource(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('unavailable');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the source. Please try again.'),
          ),
        );
      }
    }
  }

  Widget _resultCard(Map<String, dynamic> result) {
    final media = result['kind'] == 'photo' || result['kind'] == 'video';
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (media)
            InkWell(
              onTap: () {
                if (result['kind'] == 'video' &&
                    (result['video'] as String? ?? '').isNotEmpty) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _AIVideoScreen(url: result['video'] as String),
                    ),
                  );
                } else {
                  unawaited(_openSource(result['url'] as String));
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.network(
                    result['preview'] as String,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 100,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                  if (result['kind'] == 'video')
                    const CircleAvatar(
                      backgroundColor: Color(0xCC075E54),
                      child: Icon(Icons.play_arrow, color: Colors.white),
                    ),
                ],
              ),
            ),
          ListTile(
            title: Text(
              (result['title'] as String? ?? '').isEmpty
                  ? 'Photo'
                  : result['title'] as String,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              media
                  ? 'By ${result['credit']}'
                  : '${result['credit']} · ${Uri.tryParse(result['url'] as String)?.host ?? ''}',
            ),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openSource(result['url'] as String),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF1F7F5),
    appBar: AppBar(
      backgroundColor: const Color(0xFF075E54),
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Row(
        children: [
          VoxaAIAvatar(size: 36),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VoxaAI',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Your AI assistant',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Delete conversation',
          icon: const Icon(Icons.delete_outline),
          onPressed: _clearing || _sending ? null : _clearHistory,
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              'AI can make mistakes. Check source links for current information.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Color(0xFF55776D)),
            ),
          ),
          if (_error != null || (!_loading && !_available))
            MaterialBanner(
              content: Text(
                _error ??
                    'VoxaAI is temporarily unavailable. Your saved conversation is still here.',
              ),
              actions: [
                TextButton(
                  onPressed: () => _refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _turns.isEmpty
                ? _welcome()
                : ListView.builder(
                    reverse: true,
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _turns.length + (_hasMore ? 1 : 0),
                    itemBuilder: (_, index) {
                      if (index == _turns.length) {
                        return TextButton(
                          onPressed: () => _refresh(earlier: true),
                          child: const Text('Load earlier messages'),
                        );
                      }
                      return _turn(_turns[_turns.length - 1 - index]);
                    },
                  ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in const {
                  'chat': 'Chat',
                  'photos': 'Photos',
                  'videos': 'Videos',
                  'web': 'Web',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _mode == entry.key,
                      onSelected: _sending || _pending
                          ? null
                          : (_) => setState(() => _mode = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          if (_mode == 'web')
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Search the web for current information. Check source links and dates.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: _mode == 'chat' ? 4000 : 300,
                    decoration: InputDecoration(
                      hintText: _mode == 'chat'
                          ? 'Ask VoxaAI…'
                          : 'Search $_mode…',
                      counterText: '',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send to VoxaAI',
                  onPressed: _sending || _pending || !_available || _clearing
                      ? null
                      : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
