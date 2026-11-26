import 'package:flutter_test/flutter_test.dart';
import 'package:aquaspec/readings_csv.dart';

void main() {
  final tanks = <Map<String, dynamic>>[
    {
      'id': 'reef',
      'name': 'Reef, "living room"',
      'water_type': 'saltwater',
      'volume_gallons': 40,
    },
  ];
  test('Export includes extended parameters and both temperature units', () {
    final csv = buildReadingsCsv(
      tanks: tanks,
      readings: [
        {
          'id': 'r1',
          'tank_id': 'reef',
          'recorded_at': '2026-11-25T12:00:00-07:00',
          'temperature': 77,
          'ph': 8.2,
          'nitrate': 10,
          'calcium': 420,
        },
      ],
    );
    final lines = csv.trim().split('\r\n');
    final headers = lines.first.split(',');
    expect(
      headers,
      containsAll([
        'temperature_c',
        'temperature_f',
        'nitrate',
        'calcium',
        'phosphate',
      ]),
    );
    expect(
      lines[1],
      startsWith(
        '"Reef, ""living room""",saltwater,40,2026-11-25T19:00:00.000Z,25.00,77.0,',
      ),
    );
    expect(lines[1], endsWith(',synced'));
    expect(lines[1], contains('420'));
  });
  test('Offline readings are marked pending and missing values stay empty', () {
    final csv = buildReadingsCsv(
      tanks: tanks,
      readings: [
        {'tank_id': 'reef', 'ph': 7.4, '__pending': true},
      ],
    );
    expect(csv, contains(',,7.4,'));
    expect(csv, contains(',pending\r\n'));
    expect(csv, isNot(contains('null')));
  });
  test('Export excludes readings belonging to tanks outside the selection', () {
    final csv = buildReadingsCsv(
      tanks: tanks,
      readings: [
        {'tank_id': 'another-account', 'ph': 12.345},
      ],
    );
    expect(csv.trim().split('\r\n'), hasLength(1));
  });
  test('A spreadsheet formula in a tank name is exported as text', () {
    final csv = buildReadingsCsv(
      tanks: [
        {'id': 't', 'name': '=1+1'},
      ],
      readings: [
        {'tank_id': 't'},
      ],
    );
    expect(csv, contains("'=1+1,"));
  });
}
