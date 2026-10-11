import 'package:flutter/material.dart';

/// The dialog owns its controller until its route has finished closing.
class TextEntryDialog extends StatefulWidget {
  const TextEntryDialog({
    super.key,
    required this.title,
    required this.label,
    this.initial = '',
    this.maxLength = 80,
  });
  final String title;
  final String label;
  final String initial;
  final int maxLength;
  @override
  State<TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<TextEntryDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate()) {
      FocusScope.of(context).unfocus();
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(color: Color(0xFF17251F)),
        decoration: InputDecoration(labelText: widget.label),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Enter ${widget.label.toLowerCase()}'
            : null,
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
