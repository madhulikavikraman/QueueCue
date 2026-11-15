import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: T.brand,
    primary: T.brand,
    onPrimary: T.onBrand,
    secondary: T.accent,
    onSecondary: T.onAccent,
    surface: T.surface,
    onSurface: T.ink,
    error: T.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: T.bg, fontFamily: T.fontBody);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.radius));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: T.ink, displayColor: T.ink).copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontSize: T.h1, fontWeight: FontWeight.w700, color: T.ink, fontFamily: T.fontDisplay),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: T.h2, fontWeight: FontWeight.w700, color: T.ink),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: T.h3, fontWeight: FontWeight.w600, color: T.ink),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: T.body, color: T.ink, height: 1.4),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: T.small, color: T.muted),
        ),
    appBarTheme: const AppBarTheme(backgroundColor: T.bg, foregroundColor: T.ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: T.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.radius), side: const BorderSide(color: T.line, width: T.border)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: shape,
        textStyle: const TextStyle(fontSize: T.body, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: shape,
        foregroundColor: T.ink,
        side: const BorderSide(color: T.ink, width: T.border),
        textStyle: const TextStyle(fontSize: T.body, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: T.brand, minimumSize: const Size(48, 44))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: T.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(T.radius), borderSide: const BorderSide(color: T.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(T.radius), borderSide: const BorderSide(color: T.line, width: T.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(T.radius), borderSide: const BorderSide(color: T.brand, width: 2)),
      labelStyle: const TextStyle(color: T.muted),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: const BorderSide(color: T.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.radius)),
      labelStyle: const TextStyle(color: T.ink, fontSize: T.small),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: T.surface,
      indicatorColor: T.accent,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: T.tiny, fontWeight: FontWeight.w600, color: T.ink)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: T.ink, contentTextStyle: TextStyle(color: T.bg)),
    dividerTheme: const DividerThemeData(color: T.line, thickness: 1),
  );
}
