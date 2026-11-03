import 'package:flutter/painting.dart';

/// Цвета продукта для светлой и тёмной темы.
///
/// Единая палитра сайта и приложения — `docs/brand/colors.md` (задача С.1.4).
/// Экраны берут цвета из темы, а не отсюда.
final class BrandColors {
  const new({
    required this.background,
    required this.backgroundAlt,
    required this.surface,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.accent,
    required this.accentStrong,
    required this.accentSoft,
    required this.onAccent,
    required this.focus,
    required this.danger,
    required this.warning,
  });

  static const light = BrandColors(
    background: Color(0xFFFBFBF9),
    backgroundAlt: Color(0xFFF1F3F0),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF1A1F1C),
    textMuted: Color(0xFF59625D),
    border: Color(0xFFDDE2DE),
    accent: Color(0xFF0F6B5C),
    accentStrong: Color(0xFF0A5246),
    accentSoft: Color(0xFFDCEFEA),
    onAccent: Color(0xFFFFFFFF),
    focus: Color(0xFF1B66D1),
    danger: Color(0xFFB3261E),
    warning: Color(0xFF8A5A00),
  );

  static const dark = BrandColors(
    background: Color(0xFF111513),
    backgroundAlt: Color(0xFF171C19),
    surface: Color(0xFF1C221F),
    text: Color(0xFFE7ECE9),
    textMuted: Color(0xFFA3ADA8),
    border: Color(0xFF2D3531),
    accent: Color(0xFF4CC2A9),
    accentStrong: Color(0xFF79D6C2),
    accentSoft: Color(0xFF19332D),
    onAccent: Color(0xFF08201B),
    focus: Color(0xFF7FB0FF),
    danger: Color(0xFFF2B8B5),
    warning: Color(0xFFF0C060),
  );

  final Color background;
  final Color backgroundAlt;
  final Color surface;
  final Color text;
  final Color textMuted;
  final Color border;
  final Color accent;
  final Color accentStrong;
  final Color accentSoft;
  final Color onAccent;
  final Color focus;
  final Color danger;
  final Color warning;
}
