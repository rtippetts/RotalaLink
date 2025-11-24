import 'package:flutter/material.dart';

class RotalaColors {
  // Core brand colors
  static const Color teal = Color(0xFF51A7A8);
  static const Color coral = Color(0xFFFF6F4D);
  static const Color darkBlue = Color(0xFF344C59);
  static const Color lightCyan = Color(0xFFCFF6F0);
  static const Color offWhite = Color(0xFFF4F4F4);
  static const Color charcoal = Color(0xFF2F2F2F);
  static const Color mediumGray = Color(0xFF666666);
  static const Color pureWhite = Colors.white;

  // Message colors
  static const Color info = Color(0xFF3B83E1);
  static const Color success = Color(0xFF10A170);
  static const Color warning = Color(0xFFFFB700);
  static const Color error = Color(0xFFE61744);

  // Hover (optional)
  static const Color infoHover = Color(0xFF275796);
  static const Color successHover = Color(0xFF006141);
  static const Color warningHover = Color(0xFF8C3A00);
  static const Color errorHover = Color(0xFFA3082A);
  static const Color coolGray = Color(0xFFD9D9D9);
}

class RotalaRadii {
  static const double cardRadius = 16;
  static const double buttonRadius = 12;
  static const double inputRadius = 12;
}

class RotalaShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Colors.black26,
      blurRadius: 8,
      offset: Offset(0, 3),
    ),
  ];
}

class RotalaText {
  // These assume you've loaded fonts in pubspec
  static const String titleFont = 'Quicksand';
  static const String bodyFont = 'PublicSans';

  static TextStyle title = const TextStyle(
    fontFamily: titleFont,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    fontSize: 20,
  );

  static TextStyle body = const TextStyle(
    fontFamily: bodyFont,
    fontWeight: FontWeight.w400,
    color: Colors.white,
    fontSize: 14,
  );
}

class RotalaButtons {
  static ButtonStyle primary = FilledButton.styleFrom(
    backgroundColor: RotalaColors.teal,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RotalaRadii.buttonRadius),
    ),
  );

  static ButtonStyle outline = OutlinedButton.styleFrom(
    side: const BorderSide(color: RotalaColors.coral),
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RotalaRadii.buttonRadius),
    ),
  );
}
