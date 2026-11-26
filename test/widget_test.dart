import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquaspec/tank_detail_page.dart';
import 'package:aquaspec/tank_parameters.dart';
import 'package:aquaspec/widgets/record_tank_picker.dart';

void main() {
  testWidgets('First-time user can start adding a tank from Record', (
    tester,
  ) async {
    var adding = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordTankPicker(
            tanks: const [],
            onAddTank: () => adding = true,
          ),
        ),
      ),
    );
    expect(
      find.text('Add your first aquarium, then log its water parameters.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Add tank'));
    expect(adding, isTrue);
  });

  testWidgets('Record returns the selected tank with custom tracking intact', (
    tester,
  ) async {
    final reef = Tank(
      id: 'reef',
      name: 'Reef aquarium',
      volumeLiters: 200,
      inhabitants: 'Saltwater',
      waterType: 'saltwater',
      tracking: {ParamType.nitrate: true, ParamType.ph: false},
      idealRanges: {ParamType.nitrate: const RangeValues(5, 15)},
    );
    Tank? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<Tank>(
                    context: context,
                    builder: (_) =>
                        RecordTankPicker(tanks: [reef], onAddTank: () {}),
                  );
                },
                child: const Text('Record'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose the aquarium you tested. No device is needed.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reef aquarium'));
    await tester.pumpAndSettle();
    expect(selected, same(reef));
    expect(selected!.isTracking(ParamType.nitrate), isTrue);
    expect(selected!.isTracking(ParamType.ph), isFalse);
    expect(selected!.rangeFor(ParamType.nitrate), const RangeValues(5, 15));
  });

  testWidgets('Tank picker scrolls on a compact phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            height: 430,
            child: RecordTankPicker(
              tanks: List.generate(
                10,
                (i) => Tank(
                  id: '$i',
                  name: 'Aquarium $i',
                  volumeLiters: 100,
                  inhabitants: 'Freshwater',
                ),
              ),
              onAddTank: () {},
            ),
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Aquarium 9'),
      150,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Aquarium 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
