import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// Рабочее название продукта до выбора (С.1.2)
  ///
  /// In ru, this message translates to:
  /// **'Backpeer'**
  String get appTitle;

  /// No description provided for @navOverview.
  ///
  /// In ru, this message translates to:
  /// **'Обзор'**
  String get navOverview;

  /// No description provided for @navBackup.
  ///
  /// In ru, this message translates to:
  /// **'Бэкап'**
  String get navBackup;

  /// No description provided for @navRestore.
  ///
  /// In ru, this message translates to:
  /// **'Восстановление'**
  String get navRestore;

  /// No description provided for @navKeeper.
  ///
  /// In ru, this message translates to:
  /// **'Хранитель'**
  String get navKeeper;

  /// No description provided for @navSettings.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get navSettings;

  /// No description provided for @processAgent.
  ///
  /// In ru, this message translates to:
  /// **'Агент бэкапа'**
  String get processAgent;

  /// No description provided for @processNode.
  ///
  /// In ru, this message translates to:
  /// **'Служба хранителя'**
  String get processNode;

  /// No description provided for @linkConnecting.
  ///
  /// In ru, this message translates to:
  /// **'{process}: подключение…'**
  String linkConnecting(String process);

  /// No description provided for @linkUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'{process} не запущен'**
  String linkUnavailable(String process);

  /// No description provided for @linkUnavailableHint.
  ///
  /// In ru, this message translates to:
  /// **'Приложение подключится само, как только процесс запустится. Данные не потеряются.'**
  String get linkUnavailableHint;

  /// No description provided for @agentStatusIdle.
  ///
  /// In ru, this message translates to:
  /// **'Ждёт расписания'**
  String get agentStatusIdle;

  /// No description provided for @agentStatusWorking.
  ///
  /// In ru, this message translates to:
  /// **'Работает'**
  String get agentStatusWorking;

  /// No description provided for @agentStatusPaused.
  ///
  /// In ru, this message translates to:
  /// **'Пауза'**
  String get agentStatusPaused;

  /// No description provided for @agentStatusWaitingForKeys.
  ///
  /// In ru, this message translates to:
  /// **'Нужен пароль'**
  String get agentStatusWaitingForKeys;

  /// No description provided for @agentStatusStopping.
  ///
  /// In ru, this message translates to:
  /// **'Останавливается'**
  String get agentStatusStopping;

  /// No description provided for @jobBackup.
  ///
  /// In ru, this message translates to:
  /// **'Бэкап'**
  String get jobBackup;

  /// No description provided for @jobVerify.
  ///
  /// In ru, this message translates to:
  /// **'Проверка'**
  String get jobVerify;

  /// No description provided for @jobRestore.
  ///
  /// In ru, this message translates to:
  /// **'Восстановление'**
  String get jobRestore;

  /// No description provided for @outcomeOk.
  ///
  /// In ru, this message translates to:
  /// **'успешно'**
  String get outcomeOk;

  /// No description provided for @outcomePartial.
  ///
  /// In ru, this message translates to:
  /// **'с предупреждениями'**
  String get outcomePartial;

  /// No description provided for @outcomeFailed.
  ///
  /// In ru, this message translates to:
  /// **'ошибка'**
  String get outcomeFailed;

  /// No description provided for @outcomeCancelled.
  ///
  /// In ru, this message translates to:
  /// **'остановлен'**
  String get outcomeCancelled;

  /// No description provided for @lastBackup.
  ///
  /// In ru, this message translates to:
  /// **'Последний бэкап'**
  String get lastBackup;

  /// No description provided for @nextBackup.
  ///
  /// In ru, this message translates to:
  /// **'Следующий бэкап'**
  String get nextBackup;

  /// No description provided for @never.
  ///
  /// In ru, this message translates to:
  /// **'ещё не было'**
  String get never;

  /// No description provided for @notScheduled.
  ///
  /// In ru, this message translates to:
  /// **'не по расписанию'**
  String get notScheduled;

  /// No description provided for @now.
  ///
  /// In ru, this message translates to:
  /// **'сейчас'**
  String get now;

  /// No description provided for @backupNow.
  ///
  /// In ru, this message translates to:
  /// **'Сделать бэкап сейчас'**
  String get backupNow;

  /// No description provided for @pause.
  ///
  /// In ru, this message translates to:
  /// **'Пауза'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get resume;

  /// No description provided for @interruptedNote.
  ///
  /// In ru, this message translates to:
  /// **'Прошлый бэкап не закончен — он продолжится с того же места.'**
  String get interruptedNote;

  /// No description provided for @notConfigured.
  ///
  /// In ru, this message translates to:
  /// **'На этом устройстве ещё нет учётной записи.'**
  String get notConfigured;

  /// No description provided for @filesCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} файл} few{{count} файла} many{{count} файлов} other{{count} файла}}'**
  String filesCount(int count);

  /// No description provided for @jobProgress.
  ///
  /// In ru, this message translates to:
  /// **'{files}, прочитано {bytes}'**
  String jobProgress(String files, String bytes);

  /// No description provided for @keysRequired.
  ///
  /// In ru, this message translates to:
  /// **'Бэкап ждёт пароль'**
  String get keysRequired;

  /// No description provided for @keysRequiredHint.
  ///
  /// In ru, this message translates to:
  /// **'Хранилище ключей системы закрыто или недоступно. Введите пароль, чтобы бэкап продолжился.'**
  String get keysRequiredHint;

  /// No description provided for @enterPassword.
  ///
  /// In ru, this message translates to:
  /// **'Ввести пароль'**
  String get enterPassword;

  /// No description provided for @unlockTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пароль для фоновой работы'**
  String get unlockTitle;

  /// No description provided for @unlockBody.
  ///
  /// In ru, this message translates to:
  /// **'Агент бэкапа откроет ключи и сохранит их в хранилище ключей системы — после перезагрузки пароль не понадобится.'**
  String get unlockBody;

  /// No description provided for @password.
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get password;

  /// No description provided for @rememberKeys.
  ///
  /// In ru, this message translates to:
  /// **'Запомнить в хранилище ключей системы'**
  String get rememberKeys;

  /// No description provided for @unlock.
  ///
  /// In ru, this message translates to:
  /// **'Открыть'**
  String get unlock;

  /// No description provided for @cancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancel;

  /// No description provided for @wrongPassword.
  ///
  /// In ru, this message translates to:
  /// **'Неверный пароль'**
  String get wrongPassword;

  /// No description provided for @notRemembered.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить ключ в системе не удалось — пароль понадобится после перезапуска.'**
  String get notRemembered;

  /// No description provided for @backupFolders.
  ///
  /// In ru, this message translates to:
  /// **'Папки для бэкапа'**
  String get backupFolders;

  /// No description provided for @noFolders.
  ///
  /// In ru, this message translates to:
  /// **'Папки ещё не выбраны'**
  String get noFolders;

  /// No description provided for @schedule.
  ///
  /// In ru, this message translates to:
  /// **'Расписание'**
  String get schedule;

  /// No description provided for @everyMinutes.
  ///
  /// In ru, this message translates to:
  /// **'{minutes, plural, one{каждую {minutes} минуту} few{каждые {minutes} минуты} many{каждые {minutes} минут} other{каждые {minutes} минуты}}'**
  String everyMinutes(int minutes);

  /// No description provided for @manualOnly.
  ///
  /// In ru, this message translates to:
  /// **'только вручную'**
  String get manualOnly;

  /// No description provided for @comingSoon.
  ///
  /// In ru, this message translates to:
  /// **'Изменение — в следующей версии приложения'**
  String get comingSoon;

  /// No description provided for @snapshots.
  ///
  /// In ru, this message translates to:
  /// **'Снимки'**
  String get snapshots;

  /// No description provided for @noSnapshots.
  ///
  /// In ru, this message translates to:
  /// **'Снимков пока нет'**
  String get noSnapshots;

  /// No description provided for @refresh.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get refresh;

  /// No description provided for @snapshotSummary.
  ///
  /// In ru, this message translates to:
  /// **'{files} · {size}'**
  String snapshotSummary(String files, String size);

  /// No description provided for @keeperExplain.
  ///
  /// In ru, this message translates to:
  /// **'Хранитель отдаёт место на этом компьютере. Он не видит ни содержимого, ни имён файлов — только зашифрованные фрагменты.'**
  String get keeperExplain;

  /// No description provided for @keeperOff.
  ///
  /// In ru, this message translates to:
  /// **'Роль хранителя не включена или служба не запущена.'**
  String get keeperOff;

  /// No description provided for @keeperUsed.
  ///
  /// In ru, this message translates to:
  /// **'Занято'**
  String get keeperUsed;

  /// No description provided for @keeperQuota.
  ///
  /// In ru, this message translates to:
  /// **'Отдано места'**
  String get keeperQuota;

  /// No description provided for @keeperFragments.
  ///
  /// In ru, this message translates to:
  /// **'Фрагментов'**
  String get keeperFragments;

  /// No description provided for @keeperConnections.
  ///
  /// In ru, this message translates to:
  /// **'Соединений'**
  String get keeperConnections;

  /// No description provided for @keeperReachability.
  ///
  /// In ru, this message translates to:
  /// **'Подключение'**
  String get keeperReachability;

  /// No description provided for @keeperDirect.
  ///
  /// In ru, this message translates to:
  /// **'прямое'**
  String get keeperDirect;

  /// No description provided for @keeperIndirect.
  ///
  /// In ru, this message translates to:
  /// **'через UDP или relay'**
  String get keeperIndirect;

  /// No description provided for @keeperUnknown.
  ///
  /// In ru, this message translates to:
  /// **'проверяется'**
  String get keeperUnknown;

  /// No description provided for @keeperState.
  ///
  /// In ru, this message translates to:
  /// **'Состояние'**
  String get keeperState;

  /// No description provided for @nodeRunning.
  ///
  /// In ru, this message translates to:
  /// **'работает'**
  String get nodeRunning;

  /// No description provided for @nodePaused.
  ///
  /// In ru, this message translates to:
  /// **'пауза'**
  String get nodePaused;

  /// No description provided for @nodeStopping.
  ///
  /// In ru, this message translates to:
  /// **'останавливается'**
  String get nodeStopping;

  /// No description provided for @language.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get languageSystem;

  /// No description provided for @theme.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get themeDark;

  /// No description provided for @about.
  ///
  /// In ru, this message translates to:
  /// **'О программе'**
  String get about;

  /// No description provided for @version.
  ///
  /// In ru, this message translates to:
  /// **'Версия {version}'**
  String version(String version);

  /// No description provided for @failed.
  ///
  /// In ru, this message translates to:
  /// **'Не получилось: {message}'**
  String failed(String message);

  /// No description provided for @sizeBytes.
  ///
  /// In ru, this message translates to:
  /// **'{value} Б'**
  String sizeBytes(String value);

  /// No description provided for @sizeKiB.
  ///
  /// In ru, this message translates to:
  /// **'{value} КиБ'**
  String sizeKiB(String value);

  /// No description provided for @sizeMiB.
  ///
  /// In ru, this message translates to:
  /// **'{value} МиБ'**
  String sizeMiB(String value);

  /// No description provided for @sizeGiB.
  ///
  /// In ru, this message translates to:
  /// **'{value} ГиБ'**
  String sizeGiB(String value);

  /// No description provided for @sizeTiB.
  ///
  /// In ru, this message translates to:
  /// **'{value} ТиБ'**
  String sizeTiB(String value);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
