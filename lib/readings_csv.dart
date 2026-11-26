import 'tank_parameters.dart';

/// Temperatures in Supabase are Fahrenheit, independent of display preferences.
/// Other parameter columns use the units defined by kTankParameterSpecs.
String buildReadingsCsv({
  required List<Map<String, dynamic>> tanks,
  required List<Map<String, dynamic>> readings,
}) {
  final tankById = {for (final tank in tanks) tank['id'].toString(): tank};
  final parameters = kTankParameterSpecs.where((spec) => !spec.isTemperature);
  final buffer = StringBuffer();
  void writeRow(List<Object?> values) {
    buffer.write(values.map(_csvCell).join(','));
    buffer.write('\r\n');
  }

  writeRow([
    'tank_name',
    'water_type',
    'volume_gallons',
    'recorded_at_utc',
    'temperature_c',
    'temperature_f',
    for (final spec in parameters) spec.readingField,
    'device_uid',
    'sync_status',
  ]);
  for (final reading in readings) {
    final tank = tankById[reading['tank_id'].toString()];
    if (tank == null) continue;
    final temperatureF = (reading['temperature'] as num?)?.toDouble();
    final timestamp = DateTime.tryParse('${reading['recorded_at'] ?? ''}');
    writeRow([
      tank['name'],
      tank['water_type'],
      tank['volume_gallons'],
      timestamp?.toUtc().toIso8601String() ?? reading['recorded_at'],
      temperatureF == null
          ? null
          : ((temperatureF - 32) * 5 / 9).toStringAsFixed(2),
      temperatureF,
      for (final spec in parameters) reading[spec.readingField],
      reading['device_uid'],
      reading['__pending'] == true ? 'pending' : 'synced',
    ]);
  }
  return buffer.toString();
}

String _csvCell(Object? value) {
  var text = value?.toString() ?? '';
  // A tank name must remain text when opened in a spreadsheet.
  if (value is String && RegExp(r'^[=+\-@\t\r]').hasMatch(text)) {
    text = "'$text";
  }
  if (text.contains(RegExp('[,"\r\n]'))) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}
