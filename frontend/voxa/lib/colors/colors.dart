import 'package:flutter/material.dart';

class AppColor {
  AppColor._();

  static const Color dartTealGreen = Color(0xFF075E54);
  static const Color tealGreen = Color(0xFF128C7E);
  static const Color lightGreen = Color(0xFF25D366);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF4FBF6), Color(0xFFFCFDFC), Color(0xFFEAF6EF)],
  );

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E704F), Color(0xFF13845A), Color(0xFF07563D)],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF9FBF9), Color(0xFFE6F3ED)],
  );
}
