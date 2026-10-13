import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voxa/services/push_notification_service.dart';
import '../test/push_notification_test.dart' as routing;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  routing.main();

  testWidgets('Firebase initialization does not prevent app startup', (
    tester,
  ) async {
    await PushNotificationService.instance.initialize();
    const expectedProject = String.fromEnvironment('FIREBASE_TEST_PROJECT');
    if (expectedProject.isNotEmpty) {
      expect(Firebase.app().options.projectId, expectedProject);
      expect(
        PushNotificationService.instance.status.value,
        'Sign in to enable notifications.',
      );
    }
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Voxa'))),
    );
    expect(find.text('Voxa'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(PushNotificationService.instance.status.value, isNotEmpty);
  });
}
