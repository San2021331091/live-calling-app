import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxa/screens/editimage.dart';
import 'package:voxa/emoji/emoji_data.dart';
import 'package:voxa/media/media_result.dart';

void main() {
  late Directory directory;
  late File photo;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('voxa_editor_test_');
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 64);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    photo = await File(
      '${directory.path}/photo.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  });

  tearDown(() async => directory.delete(recursive: true));

  testWidgets('Photo text and emoji appear on the editing canvas', (
    tester,
  ) async {
    MediaResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<MediaResult>(
                  MaterialPageRoute(builder: (_) => EditImage(file: photo)),
                );
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Hello Voxa');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Hello Voxa'), findsOneWidget);

    await tester.tap(find.byTooltip('Add emoji'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(EmojiData.emojis.first));
    await tester.pumpAndSettle();
    expect(find.text(EmojiData.emojis.first), findsOneWidget);
    expect(find.text('Hello Voxa'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(find.text(EmojiData.emojis.first), const Offset(70, 50));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Use edited media'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    final codec = await ui.instantiateImageCodec(
      await saved!.file.readAsBytes(),
    );
    final frame = await codec.getNextFrame();
    final pixels = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    // Original photo is blue. White text and multicolor emoji must be baked in.
    var changedPixels = 0;
    for (var offset = 0; offset < pixels!.lengthInBytes; offset += 4) {
      if (pixels.getUint8(offset) != ((Colors.blue.toARGB32() >> 16) & 255) ||
          pixels.getUint8(offset + 1) !=
              ((Colors.blue.toARGB32() >> 8) & 255) ||
          pixels.getUint8(offset + 2) != (Colors.blue.toARGB32() & 255))
        changedPixels++;
    }
    expect(changedPixels, greaterThan(10));
    frame.image.dispose();
    codec.dispose();
    await saved!.file.delete();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('Emoji data consists of actual Unicode characters', () {
    expect(EmojiData.emojis.first.runes.single, 0x1F600);
    expect(EmojiData.emojis.any((emoji) => emoji.contains('\u00f0')), isFalse);
  });
}
