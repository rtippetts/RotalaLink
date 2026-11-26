import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aquaspec/main.dart';
import 'package:aquaspec/widgets/app_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  testWidgets(
    'Signed-out users can reach sign-in and account creation',
    (tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(find.text('Log In'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Dashboard actions work and no unfinished destinations are exposed',
    (tester) async {
      var records = 0;
      var tasks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AppScaffold(
            currentIndex: 0,
            title: 'My aquariums',
            body: const SizedBox(),
            onRecord: () => records++,
            onTasks: () => tasks++,
          ),
        ),
      );
      for (final label in ['Think Tank', 'RALA', 'Library', 'Scan RFID']) {
        expect(find.text(label), findsNothing);
      }
      await tester.tap(find.text('Record'));
      await tester.tap(find.text('Tasks'));
      expect(records, 1);
      expect(tasks, 1);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Export tank data (CSV)'), findsOneWidget);
      expect(find.text('View app walkthrough'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Dashboard actions fit a compact phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
        home: AppScaffold(
          currentIndex: 0,
          title: 'My aquariums',
          body: const SizedBox(),
          onRecord: () {},
          onTasks: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
