import 'package:app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Размер для человека в единицах языка интерфейса: `512 Б`, `1,5 МиБ`.
String formatSize(AppLocalizations l10n, int bytes) {
  final units = [
    l10n.sizeBytes,
    l10n.sizeKiB,
    l10n.sizeMiB,
    l10n.sizeGiB,
    l10n.sizeTiB,
  ];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final number = unit == 0
      ? NumberFormat.decimalPattern(l10n.localeName).format(bytes)
      : NumberFormat('0.0', l10n.localeName).format(value);
  return units[unit](number);
}

/// Дата и время из ISO 8601 в местном времени; `null` — `null`.
String? formatDateTime(AppLocalizations l10n, Object? iso) {
  if (iso is! String) return null;
  final time = DateTime.tryParse(iso);
  if (time == null) return null;
  return DateFormat.yMMMd(l10n.localeName).add_Hm().format(time.toLocal());
}

/// Сколько осталось, грубо: «5 минут», «2 часов» (после «около»).
String formatRemaining(AppLocalizations l10n, int ms) {
  final minutes = (ms / 60000).ceil();
  if (minutes <= 1) return l10n.lessThanMinute;
  if (minutes < 120) return l10n.durationMinutes(minutes);
  return l10n.durationHours((minutes / 60).round());
}
