// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Backpeer';

  @override
  String get navOverview => 'Обзор';

  @override
  String get navBackup => 'Бэкап';

  @override
  String get navRestore => 'Восстановление';

  @override
  String get navKeeper => 'Хранитель';

  @override
  String get navSettings => 'Настройки';

  @override
  String get processAgent => 'Агент бэкапа';

  @override
  String get processNode => 'Служба хранителя';

  @override
  String linkConnecting(String process) {
    return '$process: подключение…';
  }

  @override
  String linkUnavailable(String process) {
    return '$process не запущен';
  }

  @override
  String get linkUnavailableHint =>
      'Приложение подключится само, как только процесс запустится. Данные не потеряются.';

  @override
  String get agentStatusIdle => 'Ждёт расписания';

  @override
  String get agentStatusWorking => 'Работает';

  @override
  String get agentStatusPaused => 'Пауза';

  @override
  String get agentStatusWaitingForKeys => 'Нужен пароль';

  @override
  String get agentStatusStopping => 'Останавливается';

  @override
  String get jobBackup => 'Бэкап';

  @override
  String get jobVerify => 'Проверка';

  @override
  String get jobRestore => 'Восстановление';

  @override
  String get outcomeOk => 'успешно';

  @override
  String get outcomePartial => 'с предупреждениями';

  @override
  String get outcomeFailed => 'ошибка';

  @override
  String get outcomeCancelled => 'остановлен';

  @override
  String get lastBackup => 'Последний бэкап';

  @override
  String get nextBackup => 'Следующий бэкап';

  @override
  String get never => 'ещё не было';

  @override
  String get notScheduled => 'не по расписанию';

  @override
  String get now => 'сейчас';

  @override
  String get backupNow => 'Сделать бэкап сейчас';

  @override
  String get pause => 'Пауза';

  @override
  String get resume => 'Продолжить';

  @override
  String get interruptedNote =>
      'Прошлый бэкап не закончен — он продолжится с того же места.';

  @override
  String get notConfigured => 'На этом устройстве ещё нет учётной записи.';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файла',
      many: '$count файлов',
      few: '$count файла',
      one: '$count файл',
    );
    return '$_temp0';
  }

  @override
  String jobProgress(String files, String bytes) {
    return '$files, прочитано $bytes';
  }

  @override
  String get keysRequired => 'Бэкап ждёт пароль';

  @override
  String get keysRequiredHint =>
      'Хранилище ключей системы закрыто или недоступно. Введите пароль, чтобы бэкап продолжился.';

  @override
  String get enterPassword => 'Ввести пароль';

  @override
  String get unlockTitle => 'Пароль для фоновой работы';

  @override
  String get unlockBody =>
      'Агент бэкапа откроет ключи и сохранит их в хранилище ключей системы — после перезагрузки пароль не понадобится.';

  @override
  String get password => 'Пароль';

  @override
  String get rememberKeys => 'Запомнить в хранилище ключей системы';

  @override
  String get unlock => 'Открыть';

  @override
  String get cancel => 'Отмена';

  @override
  String get wrongPassword => 'Неверный пароль';

  @override
  String get notRemembered =>
      'Сохранить ключ в системе не удалось — пароль понадобится после перезапуска.';

  @override
  String get backupFolders => 'Папки для бэкапа';

  @override
  String get noFolders => 'Папки ещё не выбраны';

  @override
  String get schedule => 'Расписание';

  @override
  String everyMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'каждые $minutes минуты',
      many: 'каждые $minutes минут',
      few: 'каждые $minutes минуты',
      one: 'каждую $minutes минуту',
    );
    return '$_temp0';
  }

  @override
  String get manualOnly => 'только вручную';

  @override
  String get comingSoon => 'Изменение — в следующей версии приложения';

  @override
  String get snapshots => 'Снимки';

  @override
  String get noSnapshots => 'Снимков пока нет';

  @override
  String get refresh => 'Обновить';

  @override
  String snapshotSummary(String files, String size) {
    return '$files · $size';
  }

  @override
  String get keeperExplain =>
      'Хранитель отдаёт место на этом компьютере. Он не видит ни содержимого, ни имён файлов — только зашифрованные фрагменты.';

  @override
  String get keeperOff => 'Роль хранителя не включена или служба не запущена.';

  @override
  String get keeperUsed => 'Занято';

  @override
  String get keeperQuota => 'Отдано места';

  @override
  String get keeperFragments => 'Фрагментов';

  @override
  String get keeperConnections => 'Соединений';

  @override
  String get keeperReachability => 'Подключение';

  @override
  String get keeperDirect => 'прямое';

  @override
  String get keeperIndirect => 'через UDP или relay';

  @override
  String get keeperUnknown => 'проверяется';

  @override
  String get keeperState => 'Состояние';

  @override
  String get nodeRunning => 'работает';

  @override
  String get nodePaused => 'пауза';

  @override
  String get nodeStopping => 'останавливается';

  @override
  String get language => 'Язык';

  @override
  String get languageSystem => 'Как в системе';

  @override
  String get theme => 'Тема';

  @override
  String get themeSystem => 'Как в системе';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get about => 'О программе';

  @override
  String version(String version) {
    return 'Версия $version';
  }

  @override
  String failed(String message) {
    return 'Не получилось: $message';
  }

  @override
  String sizeBytes(String value) {
    return '$value Б';
  }

  @override
  String sizeKiB(String value) {
    return '$value КиБ';
  }

  @override
  String sizeMiB(String value) {
    return '$value МиБ';
  }

  @override
  String sizeGiB(String value) {
    return '$value ГиБ';
  }

  @override
  String sizeTiB(String value) {
    return '$value ТиБ';
  }
}
