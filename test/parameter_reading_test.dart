import 'package:flutter_test/flutter_test.dart';
import 'package:aquaspec/tank_parameters.dart';

void main() {
  final ph = specFor(ParamType.ph);
  final nitrate = specFor(ParamType.nitrate);
  test('Optional fields may be blank; zero is a valid measured value', () {
    expect(validateParameterReading(nitrate, ''), isNull);
    expect(validateParameterReading(nitrate, '0'), isNull);
    expect(validateParameterReading(ph, ' 7.4 '), isNull);
  });
  test(
    'Invalid and non-finite input cannot be silently discarded or saved',
    () {
      for (final input in ['abc', 'NaN', 'Infinity', '-Infinity', '1e999']) {
        expect(
          validateParameterReading(nitrate, input),
          isNotNull,
          reason: input,
        );
      }
    },
  );
  test(
    'pH respects its scale and chemical concentrations cannot be negative',
    () {
      expect(validateParameterReading(ph, '14'), isNull);
      expect(validateParameterReading(ph, '14.1'), isNotNull);
      expect(validateParameterReading(ph, '-1'), isNotNull);
      expect(validateParameterReading(nitrate, '-0.1'), isNotNull);
    },
  );
}
