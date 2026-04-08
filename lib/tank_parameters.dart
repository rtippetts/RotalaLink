import 'package:flutter/material.dart';

enum ParamType {
  temperature,
  ph,
  ammonia,
  nitrite,
  nitrate,
  gh,
  kh,
  tds,
  co2,
  salinity,
  alkalinity,
  calcium,
  magnesium,
  phosphate,
}

class TankParameterSpec {
  const TankParameterSpec({
    required this.type,
    required this.label,
    required this.trackingField,
    required this.readingField,
    required this.minField,
    required this.maxField,
    required this.icon,
    required this.color,
    required this.defaultTracked,
    required this.defaultMin,
    required this.defaultMax,
    required this.decimals,
    required this.unitLabel,
    required this.editorMin,
    required this.editorMax,
    required this.sliderDivisions,
    this.isTemperature = false,
  });

  final ParamType type;
  final String label;
  final String trackingField;
  final String readingField;
  final String minField;
  final String maxField;
  final IconData icon;
  final Color color;
  final bool defaultTracked;
  final double defaultMin;
  final double defaultMax;
  final int decimals;
  final String unitLabel;
  final double editorMin;
  final double editorMax;
  final int sliderDivisions;
  final bool isTemperature;
}

const List<TankParameterSpec> kTankParameterSpecs = [
  TankParameterSpec(
    type: ParamType.temperature,
    label: 'Temperature',
    trackingField: 'tracking_temperature',
    readingField: 'temperature',
    minField: 'ideal_temp_min',
    maxField: 'ideal_temp_max',
    icon: Icons.thermostat,
    color: Color(0xFF2F80ED),
    defaultTracked: true,
    defaultMin: 32,
    defaultMax: 110,
    decimals: 1,
    unitLabel: 'F',
    editorMin: 0,
    editorMax: 110,
    sliderDivisions: 110,
    isTemperature: true,
  ),
  TankParameterSpec(
    type: ParamType.ph,
    label: 'pH',
    trackingField: 'tracking_ph',
    readingField: 'ph',
    minField: 'ideal_ph_min',
    maxField: 'ideal_ph_max',
    icon: Icons.science,
    color: Color(0xFF27AE60),
    defaultTracked: true,
    defaultMin: 0,
    defaultMax: 14,
    decimals: 2,
    unitLabel: 'pH',
    editorMin: 0,
    editorMax: 14,
    sliderDivisions: 140,
  ),
  TankParameterSpec(
    type: ParamType.ammonia,
    label: 'Ammonia',
    trackingField: 'tracking_ammonia',
    readingField: 'ammonia',
    minField: 'ideal_ammonia_min',
    maxField: 'ideal_ammonia_max',
    icon: Icons.warning_amber_rounded,
    color: Color(0xFFF2994A),
    defaultTracked: false,
    defaultMin: 0,
    defaultMax: 0.25,
    decimals: 2,
    unitLabel: 'ppm',
    editorMin: 0,
    editorMax: 8,
    sliderDivisions: 160,
  ),
  TankParameterSpec(
    type: ParamType.nitrite,
    label: 'Nitrite',
    trackingField: 'tracking_nitrite',
    readingField: 'nitrite',
    minField: 'ideal_nitrite_min',
    maxField: 'ideal_nitrite_max',
    icon: Icons.warning_rounded,
    color: Color(0xFFE74C3C),
    defaultTracked: false,
    defaultMin: 0,
    defaultMax: 0.25,
    decimals: 2,
    unitLabel: 'ppm',
    editorMin: 0,
    editorMax: 8,
    sliderDivisions: 160,
  ),
  TankParameterSpec(
    type: ParamType.nitrate,
    label: 'Nitrate',
    trackingField: 'tracking_nitrate',
    readingField: 'nitrate',
    minField: 'ideal_nitrate_min',
    maxField: 'ideal_nitrate_max',
    icon: Icons.opacity,
    color: Color(0xFFBB6BD9),
    defaultTracked: false,
    defaultMin: 0,
    defaultMax: 40,
    decimals: 1,
    unitLabel: 'ppm',
    editorMin: 0,
    editorMax: 200,
    sliderDivisions: 200,
  ),
  TankParameterSpec(
    type: ParamType.gh,
    label: 'GH',
    trackingField: 'tracking_gh',
    readingField: 'gh',
    minField: 'ideal_gh_min',
    maxField: 'ideal_gh_max',
    icon: Icons.water_drop_outlined,
    color: Color(0xFF6FCF97),
    defaultTracked: false,
    defaultMin: 4,
    defaultMax: 12,
    decimals: 1,
    unitLabel: 'dGH',
    editorMin: 0,
    editorMax: 30,
    sliderDivisions: 60,
  ),
  TankParameterSpec(
    type: ParamType.kh,
    label: 'KH',
    trackingField: 'tracking_kh',
    readingField: 'kh',
    minField: 'ideal_kh_min',
    maxField: 'ideal_kh_max',
    icon: Icons.water,
    color: Color(0xFF56CCF2),
    defaultTracked: false,
    defaultMin: 3,
    defaultMax: 10,
    decimals: 1,
    unitLabel: 'dKH',
    editorMin: 0,
    editorMax: 30,
    sliderDivisions: 60,
  ),
  TankParameterSpec(
    type: ParamType.tds,
    label: 'TDS',
    trackingField: 'tracking_tds',
    readingField: 'tds',
    minField: 'ideal_tds_min',
    maxField: 'ideal_tds_max',
    icon: Icons.bubble_chart,
    color: Color(0xFF9B51E0),
    defaultTracked: true,
    defaultMin: 0,
    defaultMax: 1500,
    decimals: 0,
    unitLabel: 'ppm',
    editorMin: 0,
    editorMax: 1500,
    sliderDivisions: 150,
  ),
  TankParameterSpec(
    type: ParamType.co2,
    label: 'CO2',
    trackingField: 'tracking_co2',
    readingField: 'co2',
    minField: 'ideal_co2_min',
    maxField: 'ideal_co2_max',
    icon: Icons.cloud_outlined,
    color: Color(0xFF00B8D9),
    defaultTracked: false,
    defaultMin: 15,
    defaultMax: 35,
    decimals: 1,
    unitLabel: 'ppm',
    editorMin: 0,
    editorMax: 60,
    sliderDivisions: 120,
  ),
  TankParameterSpec(
    type: ParamType.salinity,
    label: 'Salinity',
    trackingField: 'tracking_salinity',
    readingField: 'salinity',
    minField: 'ideal_salinity_min',
    maxField: 'ideal_salinity_max',
    icon: Icons.waves,
    color: Color(0xFF2D9CDB),
    defaultTracked: false,
    defaultMin: 1.02,
    defaultMax: 1.026,
    decimals: 3,
    unitLabel: 'sg',
    editorMin: 1.000,
    editorMax: 1.030,
    sliderDivisions: 300,
  ),
  TankParameterSpec(
    type: ParamType.alkalinity,
    label: 'Alkalinity',
    trackingField: 'tracking_alkalinity',
    readingField: 'alkalinity',
    minField: 'ideal_alkalinity_min',
    maxField: 'ideal_alkalinity_max',
    icon: Icons.tune,
    color: Color(0xFFF2C94C),
    defaultTracked: false,
    defaultMin: 7,
    defaultMax: 12,
    decimals: 1,
    unitLabel: 'dKH',
    editorMin: 0,
    editorMax: 20,
    sliderDivisions: 40,
  ),
  TankParameterSpec(
    type: ParamType.calcium,
    label: 'Calcium',
    trackingField: 'tracking_calcium',
    readingField: 'calcium',
    minField: 'ideal_calcium_min',
    maxField: 'ideal_calcium_max',
    icon: Icons.blur_on,
    color: Color(0xFFF2994A),
    defaultTracked: false,
    defaultMin: 380,
    defaultMax: 450,
    decimals: 0,
    unitLabel: 'ppm',
    editorMin: 0,
    editorMax: 600,
    sliderDivisions: 120,
  ),
  TankParameterSpec(
    type: ParamType.magnesium,
    label: 'Magnesium',
    trackingField: 'tracking_magnesium',
    readingField: 'magnesium',
    minField: 'ideal_magnesium_min',
    maxField: 'ideal_magnesium_max',
    icon: Icons.grain,
    color: Color(0xFF8E44AD),
    defaultTracked: false,
    defaultMin: 1200,
    defaultMax: 1400,
    decimals: 0,
    unitLabel: 'ppm',
    editorMin: 0,
    editorMax: 2000,
    sliderDivisions: 200,
  ),
  TankParameterSpec(
    type: ParamType.phosphate,
    label: 'Phosphate',
    trackingField: 'tracking_phosphate',
    readingField: 'phosphate',
    minField: 'ideal_phosphate_min',
    maxField: 'ideal_phosphate_max',
    icon: Icons.filter_vintage,
    color: Color(0xFFF2C94C),
    defaultTracked: false,
    defaultMin: 0,
    defaultMax: 2,
    decimals: 2,
    unitLabel: 'ppm',
    editorMin: 0,
    editorMax: 10,
    sliderDivisions: 200,
  ),
];

TankParameterSpec specFor(ParamType type) =>
    kTankParameterSpecs.firstWhere((spec) => spec.type == type);

Map<ParamType, bool> trackingMapFromRow(Map<String, dynamic> row) {
  return {
    for (final spec in kTankParameterSpecs)
      spec.type: (row[spec.trackingField] as bool?) ?? spec.defaultTracked,
  };
}

Map<ParamType, RangeValues> idealRangeMapFromRow(Map<String, dynamic> row) {
  return {
    for (final spec in kTankParameterSpecs)
      spec.type: RangeValues(
        (row[spec.minField] as num?)?.toDouble() ?? spec.defaultMin,
        (row[spec.maxField] as num?)?.toDouble() ?? spec.defaultMax,
      ),
  };
}

Map<ParamType, double?> valueMapFromReadingRow(Map<String, dynamic> row) {
  return {
    for (final spec in kTankParameterSpecs)
      spec.type: spec.isTemperature
          ? (() {
              final tempF = (row[spec.readingField] as num?)?.toDouble();
              return tempF == null ? null : (tempF - 32) * 5 / 9;
            })()
          : (row[spec.readingField] as num?)?.toDouble(),
  };
}
