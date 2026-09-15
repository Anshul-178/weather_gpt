import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:weathergpt/models/weather.dart';
import 'package:weathergpt/providers/app_state.dart';
import 'package:weathergpt/screens/settings_screen.dart';

Widget _appWithLocation() {
  return ChangeNotifierProvider(
    create: (_) {
      final app = AppState();
      app.location = const GeoLocation(
        name: 'London',
        latitude: 51.5074,
        longitude: -0.1278,
      );
      return app;
    },
    child: MaterialApp(
      home: Scaffold(body: SettingsScreen()),
    ),
  );
}

void main() {
  // The settings list grew (on-device AI section) and no longer fits the
  // default 800x600 test surface; use a tall surface so every section builds.

  testWidgets('Settings screen shows all sections', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_appWithLocation());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Activity weather score'), findsOneWidget);
    expect(find.text('On-device AI'), findsOneWidget);
    expect(find.text('Alert notifications'), findsOneWidget);
    expect(find.text('Backend URL'), findsOneWidget);
    expect(find.text('About WeatherGPT'), findsOneWidget);
    expect(find.text('Account & data'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Clear saved location'), findsOneWidget);
  });

  testWidgets('Settings screen shows not-signed-in status', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_appWithLocation());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('not signed in'), findsOneWidget);
  });

  testWidgets('Sign out button is disabled when not authenticated', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_appWithLocation());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    // Flutter wraps OutlinedButton.icon in a private subclass, so match the
    // ancestor by predicate instead of byType.
    final signOutFinder = find.ancestor(
      of: find.text('Sign out'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    );
    expect(signOutFinder, findsOneWidget);
    final signOut = tester.widget<OutlinedButton>(signOutFinder);
    expect(signOut.onPressed, isNull);
  });
}
