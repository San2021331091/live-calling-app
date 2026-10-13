import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxa/customui/avatar_photo.dart';
import 'package:voxa/customui/chat_theme_picker.dart';

void main() {
  testWidgets('Theme picker separates personal and shared choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showChatThemePicker(
                context,
                chatId: 'test',
                personalTheme: 'rose',
                sharedTheme: 'ocean',
                isGroup: true,
                canManageShared: true,
              ),
              child: const Text('Themes'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Themes'));
    await tester.pumpAndSettle();
    expect(find.text('Use shared theme'), findsOneWidget);
    expect(
      find.text('Changes how this chat looks only for you.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Shared theme'));
    await tester.pumpAndSettle();
    expect(find.text('Use shared theme'), findsNothing);
    expect(
      find.text(
        'Sets the default for everyone. Personal choices still take priority.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Just me'));
    await tester.pumpAndSettle();
    expect(find.text('Use shared theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Members only get personal theme controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showChatThemePicker(
                context,
                chatId: 'test',
                personalTheme: '',
                sharedTheme: 'classic',
                isGroup: true,
              ),
              child: const Text('Themes'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Themes'));
    await tester.pumpAndSettle();
    expect(find.text('Shared theme'), findsNothing);
    expect(find.text('Use shared theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Photo menu allows selecting and cancelling without saving', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AvatarPhotoEditor(
            url: '',
            onSave: (_) async {
              saves++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AvatarPhotoEditor));
    await tester.pumpAndSettle();
    expect(find.text('Choose photo'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Edit current photo'), findsNothing);
    Navigator.of(tester.element(find.text('Choose photo'))).pop();
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });
}
