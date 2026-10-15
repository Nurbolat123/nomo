import 'package:flutter/material.dart';

/// Nomo brand colors: black and white with one accent, steppe gold.
class NomoColors {
  static const black = Color(0xFF0A0A0A);
  static const white = Color(0xFFFFFFFF);
  static const gold = Color(0xFFFFC93C);
  static const ink2 = Color(0xFF5A5A5A);
  static const surfaceLight = Color(0xFFF3F3F1);
  static const lineLight = Color(0xFFE2E2DF);
  static const surfaceDark = Color(0xFF1A1A1A);
  static const lineDark = Color(0xFF2E2E2E);
  static const success = Color(0xFF1F9D55);
  static const danger = Color(0xFFD93025);
}

class NomoTheme {
  // Add Manrope (assets/fonts) and set this to 'Manrope' to match the brand book.
  static const String? fontFamily = null;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final fg = dark ? NomoColors.white : NomoColors.black;
    final bg = dark ? NomoColors.black : NomoColors.white;
    final surface = dark ? NomoColors.surfaceDark : NomoColors.surfaceLight;
    final line = dark ? NomoColors.lineDark : NomoColors.lineLight;
    final scheme = ColorScheme(
      brightness: b,
      primary: fg,
      onPrimary: bg,
      secondary: NomoColors.gold,
      onSecondary: NomoColors.black,
      error: NomoColors.danger,
      onError: NomoColors.white,
      surface: bg,
      onSurface: fg,
      surfaceContainerHighest: surface,
      outline: line,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: fontFamily, brightness: b);
    final text = base.textTheme.apply(bodyColor: fg, displayColor: fg).copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5, color: fg),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: fg),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: fg),
        );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: text,
      appBarTheme: AppBarTheme(backgroundColor: bg, foregroundColor: fg, elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
          titleTextStyle: text.titleLarge),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: fg,
          foregroundColor: bg,
          minimumSize: const Size.fromHeight(56),
          shape: shape,
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: line, width: 1.5),
          shape: shape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: fg)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      cardTheme: CardThemeData(color: surface, elevation: 0, shape: shape, margin: EdgeInsets.zero),
      dividerTheme: DividerThemeData(color: line, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bg,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: fg, contentTextStyle: TextStyle(color: bg)),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NomoColors.gold : null),
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NomoColors.black : null),
      ),
    );
  }
}
