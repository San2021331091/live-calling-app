import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:voxa/media/media_result.dart';
import 'package:voxa/emoji/emoji_data.dart';

class EditImage extends StatefulWidget {
  final File file;
  const EditImage({super.key, required this.file});

  @override
  State<EditImage> createState() => _EditImageState();
}

class _EditImageState extends State<EditImage> {
  double rotationAngle = 0.0;
  bool showEmojiPicker = false;
  bool showCropOverlay = false;
  bool isDrawing = false;
  List<Offset?> points = [];
  List<_TextInfo> texts = [];
  Color textColor = Colors.white;
  double textSize = 24;

  final double _captionBarHeight = 70;
  final double _emojiPickerHeight = 120;
  final TextEditingController _captionController = TextEditingController();

  void _rotateImage() => setState(() => rotationAngle += pi / 2);

  void _addTextOverlay({String text = ''}) async {
    final controller = TextEditingController(text: text);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text("Add Text", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter text",
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                texts.add(
                  _TextInfo(
                    text: controller.text,
                    offset: Offset(80, 80),
                    color: textColor,
                    size: textSize,
                  ),
                );
              }
              Navigator.pop(context);
            },
            child: const Text("Add", style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
    setState(() {});
  }

  Future<File> _exportImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final image = await decodeImageFromList(widget.file.readAsBytesSync());
    final swapsAxes =
        rotationAngle.abs() % (2 * pi) > pi / 4 &&
            rotationAngle.abs() % (2 * pi) < 3 * pi / 4 ||
        rotationAngle.abs() % (2 * pi) > 5 * pi / 4 &&
            rotationAngle.abs() % (2 * pi) < 7 * pi / 4;
    final outputWidth = swapsAxes ? image.height : image.width;
    final outputHeight = swapsAxes ? image.width : image.height;
    canvas
      ..translate(outputWidth / 2, outputHeight / 2)
      ..rotate(rotationAngle)
      ..translate(-image.width / 2, -image.height / 2)
      ..drawImage(image, Offset.zero, Paint());

    // Draw points
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }

    // Draw texts
    for (var t in texts) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(color: t.color, fontSize: t.size),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, t.offset);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(outputWidth, outputHeight);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final newFile = File('${widget.file.path}_edited.png');
    await newFile.writeAsBytes(bytes!.buffer.asUint8List());
    return newFile;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Image preview with drawing and text
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) {
                if (isDrawing) points.add(details.localPosition);
                setState(() {});
              },
              onPanEnd: (_) {
                if (isDrawing) points.add(null);
                setState(() {});
              },
              child: Transform.rotate(
                angle: rotationAngle,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(widget.file, fit: BoxFit.cover),
                    CustomPaint(painter: _DrawingPainter(points)),
                    ...texts.map((t) => _MovableText(t: t)),
                  ],
                ),
              ),
            ),
          ),

          // Crop overlay (static for now)
          if (showCropOverlay)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: MediaQuery.of(context).size.width * 0.8,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Top buttons
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _topButton(Icons.arrow_back, () => Navigator.pop(context)),
                Row(
                  children: [
                    _topButton(
                      Icons.crop,
                      () => setState(() => showCropOverlay = !showCropOverlay),
                    ),
                    _topButton(Icons.crop_rotate, _rotateImage),
                    _topButton(Icons.text_fields, _addTextOverlay),
                    _topButton(
                      Icons.edit,
                      () => setState(() => isDrawing = !isDrawing),
                    ),
                    _topButton(
                      Icons.emoji_emotions_outlined,
                      () => setState(() => showEmojiPicker = !showEmojiPicker),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Emoji picker
          if (showEmojiPicker)
            Positioned(
              bottom: _captionBarHeight,
              left: 0,
              right: 0,
              child: Container(
                height: _emojiPickerHeight,
                color: Colors.black87,
                child: GridView.builder(
                  scrollDirection: Axis.horizontal,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                  ),
                  itemCount: EmojiData.emojis.length,
                  itemBuilder: (_, i) {
                    final emoji = EmojiData.emojis[i];
                    return InkWell(
                      onTap: () {
                        _addTextOverlay(text: emoji);
                      },
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Caption bar / send
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                height: _captionBarHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: "Add a caption...",
                          hintStyle: TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: Colors.black54,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(24)),
                            borderSide: BorderSide(color: Colors.white38),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(24)),
                            borderSide: BorderSide(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                    FloatingActionButton(
                      backgroundColor: Colors.green,
                      child: const Icon(Icons.check, color: Colors.white),
                      onPressed: () async {
                        final editedFile = await _exportImage();
                        Navigator.pop(
                          context,
                          MediaResult(
                            file: editedFile,
                            isVideo: false,
                            caption: _captionController.text,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topButton(IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(icon, color: Colors.white),
    ),
  );
}

class _DrawingPainter extends CustomPainter {
  final List<Offset?> points;
  _DrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

class _TextInfo {
  final String text;
  Offset offset;
  final Color color;
  final double size;

  _TextInfo({
    required this.text,
    required this.offset,
    required this.color,
    required this.size,
  });
}

class _MovableText extends StatefulWidget {
  final _TextInfo t;
  const _MovableText({required this.t});

  @override
  State<_MovableText> createState() => _MovableTextState();
}

class _MovableTextState extends State<_MovableText> {
  late Offset position;

  @override
  void initState() {
    super.initState();
    position = widget.t.offset;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            position += details.delta;
            widget.t.offset = position;
          });
        },
        child: Text(
          widget.t.text,
          style: TextStyle(color: widget.t.color, fontSize: widget.t.size),
        ),
      ),
    );
  }
}
