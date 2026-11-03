import 'package:app/src/theme/brand.dart';
import 'package:flutter/material.dart';

/// Тема Material 3 на цветах [BrandColors]; шрифт — системный, как у
/// сайта (`docs/brand/fonts.md`).
abstract final class AppTheme {
  static ThemeData light() => _build(BrandColors.light, Brightness.light);

  static ThemeData dark() => _build(BrandColors.dark, Brightness.dark);

  static ThemeData _build(BrandColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.text,
      secondary: c.accentStrong,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: brightness == Brightness.light ? c.surface : c.background,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textMuted,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.backgroundAlt,
      surfaceContainer: c.backgroundAlt,
      surfaceContainerHigh: c.surface,
      outline: c.border,
      outlineVariant: c.border,
      tertiary: c.warning,
      onTertiary: c.background,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final label = base.textTheme.labelLarge!;
    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      dividerTheme: DividerThemeData(color: c.border, space: 1),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.backgroundAlt,
        indicatorColor: c.accentSoft,
        selectedIconTheme: IconThemeData(color: c.accentStrong),
        selectedLabelTextStyle: label.copyWith(
          color: c.text,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: label.copyWith(color: c.textMuted),
      ),
      focusColor: c.focus.withValues(alpha: 0.24),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.focus, width: 2),
        ),
      ),
    );
  }
}
