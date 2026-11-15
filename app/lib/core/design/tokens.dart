import 'package:flutter/material.dart';

/// Design tokens. ALL colors, type sizes, spacing and shapes live here, so a
/// restyle is a one-folder change (core/design).
/// Contrast: every text/background pair below meets WCAG AA (4.5:1+).
class T {
  // ---- color
  static const brand = Color(0xFF990000); // cardinal; white on it = 9.7:1
  static const onBrand = Color(0xFFFFFFFF);
  static const accent = Color(0xFFFFC72C); // gold; use with ink text (12:1)
  static const onAccent = Color(0xFF1D1B16);
  static const bg = Color(0xFFFBF6EC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF3ECDD);
  static const ink = Color(0xFF1D1B16); // 15.9:1 on bg
  static const muted = Color(0xFF5C5547); // 6.9:1 on bg
  static const line = Color(0xFFD9CFBC);
  static const success = Color(0xFF1B6E3A); // 6.3:1 on white
  static const warning = Color(0xFF8A5300); // 5.6:1 on white
  static const danger = Color(0xFFB3261E); // 6.0:1 on white
  static const info = Color(0xFF1F4E8C);
  static const successBg = Color(0xFFE3F2E7);
  static const warningBg = Color(0xFFFFF1D6);
  static const dangerBg = Color(0xFFFBE4E2);
  static const infoBg = Color(0xFFE4ECF7);

  // Heat map (organizer): line length buckets.
  static const heat = [Color(0xFF2E7D4F), Color(0xFF8DB43A), Color(0xFFE0A526), Color(0xFFD9622B), Color(0xFFB3261E)];

  // ---- spacing
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0, s7 = 48.0;
  static const gutter = 16.0;
  static const maxContent = 720.0;
  static const maxWide = 1280.0;

  // ---- shape
  static const radius = 10.0;
  static const border = 1.5;
  static const shadowOffset = Offset(0, 0);

  // ---- type
  static const fontBody = null; // system font for now (styling pass later)
  static const fontDisplay = null;
  static const waitHero = 56.0; // the wait time is the largest text on the booth screen
  static const h1 = 24.0, h2 = 19.0, h3 = 16.0, body = 16.0, small = 13.5, tiny = 12.0;

  static Color fitColor(num? fit) {
    if (fit == null) return muted;
    if (fit >= 0.7) return success;
    if (fit >= 0.5) return warning;
    return danger;
  }

  static Color fitBg(num? fit) {
    if (fit == null) return surfaceAlt;
    if (fit >= 0.7) return successBg;
    if (fit >= 0.5) return warningBg;
    return dangerBg;
  }

  static Color heatFor(int line) {
    if (line <= 2) return heat[0];
    if (line <= 5) return heat[1];
    if (line <= 8) return heat[2];
    if (line <= 12) return heat[3];
    return heat[4];
  }

  static const avatarColors = {
    'fox': Color(0xFFC4561B),
    'owl': Color(0xFF6B4E9B),
    'bear': Color(0xFF7A5230),
    'cat': Color(0xFF3F6E8C),
    'frog': Color(0xFF2E7D4F),
    'panda': Color(0xFF3B3B3B),
    'koala': Color(0xFF6F7B85),
    'tiger': Color(0xFFB8650F),
    'otter': Color(0xFF8C5A3C),
    'bunny': Color(0xFFA34E7A),
  };
}
