import 'package:flutter/material.dart';
import 'aqua_colors.dart';

/// A) Ocean Core (brand-first, calm)
final ColorScheme oceanCoreLight = ColorScheme(
  brightness: Brightness.light,
  primary:   AquaColors.tealCyan,    // CTA / focus
  onPrimary: Colors.white,
  secondary: AquaColors.deepBlue,    // headers / chips
  onSecondary: Colors.white,
  tertiary:  AquaColors.brightCoral, // accents (warnings/links/CTA alt)
  onTertiary: Colors.white,

  surface: Colors.white,
  onSurface: AquaColors.ink700,
  background: AquaColors.offWhite,
  onBackground: AquaColors.ink700,
  error: const Color(0xFFB00020),
  onError: Colors.white,

  outline: AquaColors.ink200,
  shadow: Colors.black12,
  scrim: Colors.black54,

  surfaceContainerHighest: AquaColors.offWhite,
  surfaceContainerHigh:    const Color(0xFFF8FAFB),
  surfaceContainer:        const Color(0xFFF6F7F9),
  surfaceContainerLow:     const Color(0xFFF1F3F5),
  surfaceContainerLowest:  Colors.white,
);

final ColorScheme oceanCoreDark = ColorScheme(
  brightness: Brightness.dark,
  primary:   AquaColors.tealCyan,
  onPrimary: Colors.white,
  secondary: AquaColors.brightCoral,
  onSecondary: Colors.white,
  tertiary:  AquaColors.mintCyan,
  onTertiary: AquaColors.deepBlue,

  surface: const Color(0xFF0E1419),   // deep slate
  onSurface: const Color(0xFFE6EDF2),
  background: const Color(0xFF0B1115),
  onBackground: const Color(0xFFE6EDF2),
  error: const Color(0xFFFF5A5A),
  onError: Colors.white,

  outline: const Color(0xFF1F2A33),
  shadow: Colors.black,
  scrim: Colors.black87,

  surfaceContainerHighest: const Color(0xFF111A21),
  surfaceContainerHigh:    const Color(0xFF10181F),
  surfaceContainer:        const Color(0xFF0F171E),
  surfaceContainerLow:     const Color(0xFF0E161C),
  surfaceContainerLowest:  const Color(0xFF0B1115),
);

/// B) Coral Accent (more energy; orange leads)
final ColorScheme coralLeadLight = oceanCoreLight.copyWith(
  primary: AquaColors.brightCoral,
  secondary: AquaColors.tealCyan,
  tertiary: AquaColors.deepBlue,
);

final ColorScheme coralLeadDark = oceanCoreDark.copyWith(
  primary: AquaColors.brightCoral,
  secondary: AquaColors.tealCyan,
  tertiary: AquaColors.mintCyan,
);

/// C) Deep Blue (cool, pro; deep blue leads)
final ColorScheme deepBlueLight = oceanCoreLight.copyWith(
  primary: AquaColors.deepBlue,
  secondary: AquaColors.tealCyan,
  tertiary: AquaColors.brightCoral,
);

final ColorScheme deepBlueDark = oceanCoreDark.copyWith(
  primary: AquaColors.deepBlue,
  secondary: AquaColors.tealCyan,
  tertiary: AquaColors.brightCoral,
);
