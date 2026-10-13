import 'package:flutter/material.dart';
import 'package:voxa/services/api_client.dart';

class ChatPalette {
  const ChatPalette(
    this.id,
    this.name,
    this.background,
    this.bubble,
    this.header,
  );
  final String id, name;
  final Color background, bubble, header;
  static const values = [
    ChatPalette(
      'classic',
      'Classic',
      Color(0xFFEAF3F0),
      Color(0xFFDAF3E5),
      Color(0xFF0C544B),
    ),
    ChatPalette(
      'ocean',
      'Ocean',
      Color(0xFFEAF2FA),
      Color(0xFFD0E7FF),
      Color(0xFF204D79),
    ),
    ChatPalette(
      'rose',
      'Rose',
      Color(0xFFF9EDF1),
      Color(0xFFF7D6E2),
      Color(0xFF803C57),
    ),
    ChatPalette(
      'lavender',
      'Lavender',
      Color(0xFFF1EDF9),
      Color(0xFFE2D8FA),
      Color(0xFF57407F),
    ),
    ChatPalette(
      'sand',
      'Sand',
      Color(0xFFF7F1E6),
      Color(0xFFF0DFBA),
      Color(0xFF705531),
    ),
  ];
  static ChatPalette fromId(String id) =>
      values.firstWhere((value) => value.id == id, orElse: () => values.first);
}

Future<bool?> showChatThemePicker(
  BuildContext context, {
  required String chatId,
  required String personalTheme,
  required String sharedTheme,
  bool canManageShared = false,
  bool isGroup = false,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ChatThemePicker(
    chatId: chatId,
    personalTheme: personalTheme,
    sharedTheme: sharedTheme,
    canManageShared: canManageShared,
    isGroup: isGroup,
  ),
);

class _ChatThemePicker extends StatefulWidget {
  const _ChatThemePicker({
    required this.chatId,
    required this.personalTheme,
    required this.sharedTheme,
    required this.canManageShared,
    required this.isGroup,
  });
  final String chatId, personalTheme, sharedTheme;
  final bool canManageShared, isGroup;
  @override
  State<_ChatThemePicker> createState() => _ChatThemePickerState();
}

class _ChatThemePickerState extends State<_ChatThemePicker> {
  bool _shared = false, _saving = false;
  late String _selected = widget.personalTheme;
  String? _error;
  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_shared) {
        await ApiClient.instance.updateGroupAppearance(
          widget.chatId,
          theme: _selected,
        );
      } else {
        await ApiClient.instance.setChatTheme(widget.chatId, _selected);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Could not save the theme. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ChatPalette.fromId(
      _selected.isEmpty ? widget.sharedTheme : _selected,
    );
    return PopScope(
      canPop: !_saving,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chat theme',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (widget.canManageShared)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Just me')),
                    ButtonSegment(value: true, label: Text('Shared theme')),
                  ],
                  selected: {_shared},
                  onSelectionChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _shared = value.first;
                          _selected = _shared
                              ? widget.sharedTheme
                              : widget.personalTheme;
                        }),
                ),
              const SizedBox(height: 12),
              Text(
                _shared
                    ? 'Sets the default for everyone. Personal choices still take priority.'
                    : 'Changes how this chat looks only for you.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: preview.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: preview.bubble,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Message preview',
                      style: TextStyle(color: Color(0xFF26362E)),
                    ),
                  ),
                ),
              ),
              if (!_shared)
                ListTile(
                  title: Text(
                    widget.isGroup ? 'Use shared theme' : 'Use default theme',
                  ),
                  trailing: _selected.isEmpty ? const Icon(Icons.check) : null,
                  onTap: _saving ? null : () => setState(() => _selected = ''),
                ),
              for (final palette in ChatPalette.values)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: palette.bubble,
                    child: Icon(Icons.palette_outlined, color: palette.header),
                  ),
                  title: Text(palette.name),
                  trailing: _selected == palette.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: _saving
                      ? null
                      : () => setState(() => _selected = palette.id),
                ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save theme'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
