import 'package:flutter/material.dart';
import 'aqua_colors.dart';

const ColorScheme oceanCore = ColorScheme(
  brightness: Brightness.light,
  primary: AquaColors.lightOceanBlue,
  onPrimary: Colors.white,
  secondary: AquaColors.choralGreen,
  onSecondary: Colors.white,
  tertiary: AquaColors.seasideOrange,
  onTertiary: Colors.white,
  surface: Colors.white,
  onSurface: AquaColors.ink700,
  background: AquaColors.ink050,
  onBackground: AquaColors.ink700,
  error: Color(0xFFDC2626),
  onError: Colors.white,
  outline: AquaColors.ink200,
  shadow: Colors.black12,
  scrim: Colors.black54,
  surfaceContainerHighest: Color(0xFFF7FBFF),
  surfaceContainerHigh: Color(0xFFF9FAFB),
  surfaceContainer: Color(0xFFFAFAFA),
  surfaceContainerLow: Color(0xFFF3F4F6),
  surfaceContainerLowest: Colors.white,
);

// copyWith isn't const => use final
final ColorScheme coralReef = oceanCore.copyWith(
  primary: AquaColors.seasideOrange,
  secondary: AquaColors.lightOceanBlue,
  tertiary: AquaColors.choralGreen,
);

final ColorScheme lagoonCalm = oceanCore.copyWith(
  primary: AquaColors.choralGreen,
  secondary: AquaColors.lightOceanBlue,
  tertiary: AquaColors.seasideOrange,
);

const ColorScheme deepSeaDark = ColorScheme(
  brightness: Brightness.dark,
  primary: AquaColors.lightOceanBlue,
  onPrimary: Colors.white,
  secondary: AquaColors.seasideOrange,
  onSecondary: Colors.white,
  tertiary: AquaColors.choralGreen,
  onTertiary: Colors.white,
  surface: Color(0xFF0B1220),
  onSurface: Color(0xFFE6EDF5),
  background: Color(0xFF0B1220),
  onBackground: Color(0xFFE6EDF5),
  error: Color(0xFFFF5A5A),
  onError: Colors.white,
  outline: Color(0xFF1F2A3A),
  shadow: Colors.black,
  scrim: Colors.black87,
  surfaceContainerHighest: Color(0xFF10192B),
  surfaceContainerHigh: Color(0xFF0F1828),
  surfaceContainer: Color(0xFF0E1726),
  surfaceContainerLow: Color(0xFF0D1624),
  surfaceContainerLowest: Color(0xFF0B1220),
);
