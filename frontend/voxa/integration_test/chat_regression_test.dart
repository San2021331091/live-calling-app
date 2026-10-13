import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voxa/customui/text_entry_dialog.dart';
import '../test/media_editor_test.dart' as media;
import '../test/appearance_test.dart' as appearance;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  media.main();
  appearance.main();

  testWidgets('Renaming while the dialog closes does not crash', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _RenameHost()));
    for (var index = 0; index < 5; index++) {
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Group $index');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Group $index'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter name'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _RenameHost extends StatefulWidget {
  const _RenameHost();
  @override
  State<_RenameHost> createState() => _RenameHostState();
}

class _RenameHostState extends State<_RenameHost> {
  String name = 'Initial group';
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text(name),
        TextButton(
          onPressed: () async {
            final renamed = await showDialog<String>(
              context: context,
              builder: (_) => TextEntryDialog(
                title: 'Edit group name',
                label: 'Name',
                initial: name,
              ),
            );
            if (mounted && renamed != null) setState(() => name = renamed);
          },
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}
