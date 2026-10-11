import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:voxa/media/media_result.dart';
import 'package:voxa/emoji/emoji_data.dart';
import 'package:voxa/customui/text_entry_dialog.dart';

class EditImage extends StatefulWidget {
  final File file;
  final bool isVideo;
  const EditImage({super.key, required this.file, this.isVideo = false});
  @override
  State<EditImage> createState() => _EditImageState();
}

class _EditImageState extends State<EditImage> {
  static const _exporter = MethodChannel('com.voxa/media_editor');
  static const _colors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.amber,
    Colors.green,
    Colors.blue,
  ];
  final _imageKey = GlobalKey();
  final _overlayKey = GlobalKey();
  final _caption = TextEditingController();
  final _texts = <_TextOverlay>[];
  final _strokes = <_Stroke>[];
  VideoPlayerController? _video;
  Size _sourceSize = const Size(1, 1);
  Size _canvasSize = Size.zero;
  Color _color = Colors.white;
  double _textScale = .08;
  int _turns = 0;
  bool _crop = false;
  bool _drawing = false;
  bool _emoji = false;
  bool _ready = false;
  bool _saving = false;
  bool _muted = false;
  bool _seeking = false;
  String? _error;
  RangeValues _trim = const RangeValues(0, 1);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      if (widget.isVideo) {
        final video = VideoPlayerController.file(widget.file);
        _video = video;
        await video.initialize();
        if (!mounted) return;
        _sourceSize = video.value.size;
        final duration = video.value.duration.inMilliseconds.toDouble();
        if (duration <= 0) {
          throw StateError('This video has no playable duration.');
        }
        _trim = RangeValues(0, duration);
        video.addListener(_checkTrim);
      } else {
        final codec = await ui.instantiateImageCodec(
          await widget.file.readAsBytes(),
        );
        final frame = await codec.getNextFrame();
        _sourceSize = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
        frame.image.dispose();
        codec.dispose();
      }
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not open media: $error');
    }
  }

  void _checkTrim() {
    final video = _video;
    if (video == null || _seeking || !video.value.isPlaying) return;
    if (video.value.position.inMilliseconds >= _trim.end) {
      _seeking = true;
      video
          .pause()
          .then(
            (_) => video.seekTo(Duration(milliseconds: _trim.start.round())),
          )
          .whenComplete(() => _seeking = false);
    }
  }

  Future<void> _addText() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const TextEntryDialog(
        title: 'Add text',
        label: 'Text',
        maxLength: 500,
      ),
    );
    if (mounted && text != null && text.isNotEmpty) {
      setState(() {
        _texts.add(_TextOverlay(text, _color, _textScale));
        _drawing = false;
        _emoji = false;
      });
    }
  }

  Offset _normalized(Offset point) => Offset(
    (point.dx / _canvasSize.width).clamp(0.0, 1.0),
    (point.dy / _canvasSize.height).clamp(0.0, 1.0),
  );

  Future<File> _capture(GlobalKey key, String name, double pixelRatio) async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Image export failed.');
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/voxa_${DateTime.now().microsecondsSinceEpoch}_$name.png',
      );
      return file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  }

  Future<void> _save() async {
    if (!_ready || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _emoji = false;
    });
    File? overlay;
    try {
      await _video?.pause();
      final width = !widget.isVideo && _turns.isOdd
          ? _sourceSize.height
          : _sourceSize.width;
      final ratio = (math.min(width, 4096) / _canvasSize.width).clamp(1.0, 8.0);
      File output;
      if (!widget.isVideo) {
        output = await _capture(_imageKey, 'photo', ratio);
      } else {
        final duration = _video!.value.duration.inMilliseconds;
        final changed =
            _texts.isNotEmpty ||
            _strokes.isNotEmpty ||
            _muted ||
            _trim.start > 0 ||
            _trim.end.round() < duration;
        if (!changed) {
          output = widget.file;
        } else {
          if (!Platform.isAndroid) {
            throw UnsupportedError(
              'Video edit export currently requires Android.',
            );
          }
          if (_texts.isNotEmpty || _strokes.isNotEmpty) {
            overlay = await _capture(_overlayKey, 'overlay', ratio);
          }
          final path = await _exporter.invokeMethod<String>('exportVideo', {
            'input': widget.file.path,
            'overlay': overlay?.path,
            'width': _sourceSize.width.round(),
            'height': _sourceSize.height.round(),
            'startMs': _trim.start.round(),
            'endMs': _trim.end.round(),
            'mute': _muted,
          });
          if (path == null || !await File(path).exists()) {
            throw StateError('Video export did not produce a file.');
          }
          output = File(path);
        }
      }
      if (mounted) {
        Navigator.pop(
          context,
          MediaResult(
            file: output,
            isVideo: widget.isVideo,
            caption: _caption.text.trim(),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save edits: $error')));
      }
    } finally {
      if (overlay != null && await overlay.exists()) await overlay.delete();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _video?.removeListener(_checkTrim);
    _video?.dispose();
    _caption.dispose();
    super.dispose();
  }

  Widget _tool(
    String label,
    IconData icon,
    VoidCallback action, {
    bool selected = false,
  }) => IconButton(
    tooltip: label,
    onPressed: _saving || !_ready ? null : action,
    icon: Icon(icon, color: selected ? const Color(0xFF25D366) : Colors.white),
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: const Color(0xFF101916),
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (!widget.isVideo) ...[
                            _tool(
                              'Square crop',
                              Icons.crop,
                              () => setState(() => _crop = !_crop),
                              selected: _crop,
                            ),
                            _tool(
                              'Rotate',
                              Icons.rotate_right,
                              () => setState(() => _turns = (_turns + 1) % 4),
                            ),
                          ],
                          _tool('Add text', Icons.text_fields, _addText),
                          _tool(
                            'Draw',
                            Icons.edit_outlined,
                            () => setState(() {
                              _drawing = !_drawing;
                              _emoji = false;
                            }),
                            selected: _drawing,
                          ),
                          _tool(
                            'Add emoji',
                            Icons.emoji_emotions_outlined,
                            () {
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _emoji = !_emoji;
                                _drawing = false;
                              });
                            },
                            selected: _emoji,
                          ),
                          _tool(
                            'Undo',
                            Icons.undo,
                            () => setState(() {
                              if (_drawing && _strokes.isNotEmpty) {
                                _strokes.removeLast();
                              } else if (_texts.isNotEmpty) {
                                _texts.removeLast();
                              } else if (_strokes.isNotEmpty) {
                                _strokes.removeLast();
                              }
                            }),
                          ),
                          if (widget.isVideo)
                            _tool(
                              _muted ? 'Restore audio' : 'Mute video',
                              _muted ? Icons.volume_off : Icons.volume_up,
                              () {
                                setState(() => _muted = !_muted);
                                _video?.setVolume(_muted ? 0 : 1);
                              },
                              selected: _muted,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 42,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final color in _colors)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: InkWell(
                          onTap: _saving
                              ? null
                              : () => setState(() => _color = color),
                          child: Container(
                            width: 25,
                            height: 25,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == color
                                    ? const Color(0xFF25D366)
                                    : Colors.white38,
                                width: _color == color ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_ready && !_emoji && !_drawing && !_saving)
                Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Text(
                        'Text size',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        min: .04,
                        max: .18,
                        value: _textScale,
                        onChanged: (value) => setState(() {
                          _textScale = value;
                          if (_texts.isNotEmpty) _texts.last.scale = value;
                        }),
                      ),
                    ),
                  ],
                ),
              Expanded(
                child: _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                    : !_ready
                    ? const Center(child: CircularProgressIndicator())
                    : _buildCanvas(),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Saving edits...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              if (widget.isVideo && _ready) _videoControls(),
              if (_emoji)
                SizedBox(
                  height: 160,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 52,
                        ),
                    itemCount: EmojiData.emojis.length,
                    itemBuilder: (_, index) => InkWell(
                      onTap: () => setState(() {
                        _texts.add(
                          _TextOverlay(
                            EmojiData.emojis[index],
                            Colors.white,
                            .13,
                          ),
                        );
                        _emoji = false;
                      }),
                      child: Center(
                        child: Text(
                          EmojiData.emojis[index],
                          style: const TextStyle(fontSize: 30, fontFamily: ''),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _caption,
                        enabled: !_saving,
                        maxLines: 3,
                        minLines: 1,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Add a caption...',
                          hintStyle: TextStyle(color: Colors.white70),
                          fillColor: Color(0xFF26352E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      tooltip: 'Use edited media',
                      onPressed: _saving || !_ready ? null : _save,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF168A62),
                      ),
                      icon: const Icon(Icons.check, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildCanvas() => LayoutBuilder(
    builder: (context, constraints) {
      final sourceRatio = _sourceSize.width / _sourceSize.height;
      final aspectRatio = _crop
          ? 1.0
          : _turns.isOdd
          ? 1 / sourceRatio
          : sourceRatio;
      final width = math.min(
        constraints.maxWidth,
        constraints.maxHeight * aspectRatio,
      );
      final height = width / aspectRatio;
      _canvasSize = Size(width, height);
      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: ClipRect(
            child: RepaintBoundary(
              key: _imageKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.isVideo)
                    VideoPlayer(_video!)
                  else
                    RotatedBox(
                      quarterTurns: _turns,
                      child: Image.file(
                        widget.file,
                        fit: _crop ? BoxFit.cover : BoxFit.contain,
                      ),
                    ),
                  RepaintBoundary(
                    key: _overlayKey,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _drawing && !_saving
                          ? (details) => setState(
                              () => _strokes.add(
                                _Stroke(_color, [
                                  _normalized(details.localPosition),
                                ]),
                              ),
                            )
                          : null,
                      onPanUpdate: _drawing && !_saving
                          ? (details) => setState(
                              () => _strokes.last.points.add(
                                _normalized(details.localPosition),
                              ),
                            )
                          : null,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(painter: _StrokePainter(_strokes)),
                          for (final text in _texts)
                            Positioned(
                              left: text.position.dx * width,
                              top: text.position.dy * height,
                              child: GestureDetector(
                                onPanUpdate: _drawing || _saving
                                    ? null
                                    : (details) => setState(() {
                                        text.position = Offset(
                                          (text.position.dx +
                                                  details.delta.dx / width)
                                              .clamp(0.0, .9),
                                          (text.position.dy +
                                                  details.delta.dy / height)
                                              .clamp(0.0, .9),
                                        );
                                      }),
                                onDoubleTap: _saving
                                    ? null
                                    : () => setState(() => _texts.remove(text)),
                                child: Text(
                                  text.text,
                                  style: TextStyle(
                                    color: text.color,
                                    fontSize: text.scale * width,
                                    fontFamily: '',
                                    fontWeight: FontWeight.w700,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _videoControls() {
    final video = _video!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: video,
          builder: (_, value, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: value.isPlaying ? 'Pause preview' : 'Play preview',
                onPressed: _saving
                    ? null
                    : () async {
                        if (value.isPlaying) {
                          await video.pause();
                        } else {
                          final position = value.position.inMilliseconds;
                          if (position < _trim.start || position >= _trim.end) {
                            await video.seekTo(
                              Duration(milliseconds: _trim.start.round()),
                            );
                          }
                          await video.play();
                        }
                      },
                icon: Icon(
                  value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
              ),
              Text(
                '${(_trim.start / 1000).toStringAsFixed(1)}s - ${(_trim.end / 1000).toStringAsFixed(1)}s',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        RangeSlider(
          min: 0,
          max: video.value.duration.inMilliseconds.toDouble(),
          values: _trim,
          labels: RangeLabels(
            '${(_trim.start / 1000).toStringAsFixed(1)}s',
            '${(_trim.end / 1000).toStringAsFixed(1)}s',
          ),
          onChanged: _saving
              ? null
              : (value) {
                  if (value.end - value.start < 250) return;
                  setState(() => _trim = value);
                  video.pause();
                  video.seekTo(Duration(milliseconds: value.start.round()));
                },
        ),
      ],
    );
  }
}

class _TextOverlay {
  final String text;
  final Color color;
  double scale;
  Offset position = const Offset(.15, .4);
  _TextOverlay(this.text, this.color, this.scale);
}

class _Stroke {
  final Color color;
  final List<Offset> points;
  _Stroke(this.color, this.points);
}

class _StrokePainter extends CustomPainter {
  final List<_Stroke> strokes;
  _StrokePainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = size.width * .009
        ..strokeCap = StrokeCap.round;
      Offset pixel(Offset point) =>
          Offset(point.dx * size.width, point.dy * size.height);
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          pixel(stroke.points.first),
          paint.strokeWidth / 2,
          paint,
        );
      }
      for (var i = 1; i < stroke.points.length; i++) {
        canvas.drawLine(
          pixel(stroke.points[i - 1]),
          pixel(stroke.points[i]),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
