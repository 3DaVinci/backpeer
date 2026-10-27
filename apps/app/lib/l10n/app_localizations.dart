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

  /// No description provided for @welcomeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Добро пожаловать в {app}'**
  String welcomeTitle(String app);

  /// No description provided for @welcomeBody.
  ///
  /// In ru, this message translates to:
  /// **'Бэкап шифруется на этом компьютере и хранится частями у других участников. Ни они, ни сервер не видят ни содержимого, ни имён файлов.'**
  String get welcomeBody;

  /// No description provided for @welcomeCreate.
  ///
  /// In ru, this message translates to:
  /// **'Создать учётную запись'**
  String get welcomeCreate;

  /// No description provided for @welcomeCreateHint.
  ///
  /// In ru, this message translates to:
  /// **'Первый компьютер: пароль и фраза восстановления.'**
  String get welcomeCreateHint;

  /// No description provided for @welcomeLogin.
  ///
  /// In ru, this message translates to:
  /// **'Войти по паролю'**
  String get welcomeLogin;

  /// No description provided for @welcomeLoginHint.
  ///
  /// In ru, this message translates to:
  /// **'Учётная запись уже есть — подключить этот компьютер.'**
  String get welcomeLoginHint;

  /// No description provided for @welcomeRecover.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить по фразе'**
  String get welcomeRecover;

  /// No description provided for @welcomeRecoverHint.
  ///
  /// In ru, this message translates to:
  /// **'Пароль забыт или вход по паролю выключен — 24 слова.'**
  String get welcomeRecoverHint;

  /// No description provided for @serverSection.
  ///
  /// In ru, this message translates to:
  /// **'Сервер'**
  String get serverSection;

  /// No description provided for @serverAddress.
  ///
  /// In ru, this message translates to:
  /// **'Адрес сервера'**
  String get serverAddress;

  /// No description provided for @serverAddressHint.
  ///
  /// In ru, this message translates to:
  /// **'Координатор учётных записей. Пусто — без сервера: данные в папках на этом компьютере, только для проверки.'**
  String get serverAddressHint;

  /// No description provided for @serverNone.
  ///
  /// In ru, this message translates to:
  /// **'Без сервера'**
  String get serverNone;

  /// No description provided for @localModeHint.
  ///
  /// In ru, this message translates to:
  /// **'Учётная запись без сервера: фрагменты бэкапа — в папках на этом компьютере. Такой режим годится только для проверки.'**
  String get localModeHint;

  /// No description provided for @stepOf.
  ///
  /// In ru, this message translates to:
  /// **'Шаг {step} из {total}'**
  String stepOf(int step, int total);

  /// No description provided for @createTitle.
  ///
  /// In ru, this message translates to:
  /// **'Имя и вход на других компьютерах'**
  String get createTitle;

  /// No description provided for @loginName.
  ///
  /// In ru, this message translates to:
  /// **'Имя для входа'**
  String get loginName;

  /// No description provided for @loginNameHint.
  ///
  /// In ru, this message translates to:
  /// **'3–32 символа: латинские буквы, цифры, точка, «_» и «-».'**
  String get loginNameHint;

  /// No description provided for @loginNameInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Недопустимое имя'**
  String get loginNameInvalid;

  /// No description provided for @keyCopyQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Как входить на новом компьютере?'**
  String get keyCopyQuestion;

  /// No description provided for @keyCopyOn.
  ///
  /// In ru, this message translates to:
  /// **'По паролю или по фразе'**
  String get keyCopyOn;

  /// No description provided for @keyCopyOnHint.
  ///
  /// In ru, this message translates to:
  /// **'Сервер хранит копию ключа, зашифрованную вашим паролем. Удобно, но стойкость данных зависит от стойкости пароля.'**
  String get keyCopyOnHint;

  /// No description provided for @keyCopyOff.
  ///
  /// In ru, this message translates to:
  /// **'Только по фразе восстановления'**
  String get keyCopyOff;

  /// No description provided for @keyCopyOffHint.
  ///
  /// In ru, this message translates to:
  /// **'На сервере нет даже зашифрованной копии ключа. Новый компьютер подключается только фразой из 24 слов.'**
  String get keyCopyOffHint;

  /// No description provided for @keyCopyOffWarningTitle.
  ///
  /// In ru, this message translates to:
  /// **'Фраза станет единственным ключом'**
  String get keyCopyOffWarningTitle;

  /// No description provided for @keyCopyOffWarning.
  ///
  /// In ru, this message translates to:
  /// **'Если потерять фразу и все компьютеры с учётной записью, данные не вернуть никак: ни пароль, ни мы не помогут.'**
  String get keyCopyOffWarning;

  /// No description provided for @createPasswordTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get createPasswordTitle;

  /// No description provided for @createPasswordBody.
  ///
  /// In ru, this message translates to:
  /// **'Пароль открывает ключи на этом компьютере и, если вы выбрали вход по паролю, — копию ключа на сервере.'**
  String get createPasswordBody;

  /// No description provided for @newPassword.
  ///
  /// In ru, this message translates to:
  /// **'Новый пароль'**
  String get newPassword;

  /// No description provided for @repeatPassword.
  ///
  /// In ru, this message translates to:
  /// **'Повторите пароль'**
  String get repeatPassword;

  /// No description provided for @currentPassword.
  ///
  /// In ru, this message translates to:
  /// **'Текущий пароль'**
  String get currentPassword;

  /// No description provided for @passwordsDiffer.
  ///
  /// In ru, this message translates to:
  /// **'Пароли не совпадают'**
  String get passwordsDiffer;

  /// No description provided for @passwordAdvice.
  ///
  /// In ru, this message translates to:
  /// **'Не короче {min} символов. Лучше всего — 4–5 случайных слов.'**
  String passwordAdvice(int min);

  /// No description provided for @passwordStrength.
  ///
  /// In ru, this message translates to:
  /// **'Стойкость: {rating}'**
  String passwordStrength(String rating);

  /// No description provided for @passwordRejected.
  ///
  /// In ru, this message translates to:
  /// **'слабый'**
  String get passwordRejected;

  /// No description provided for @passwordWeak.
  ///
  /// In ru, this message translates to:
  /// **'средний'**
  String get passwordWeak;

  /// No description provided for @passwordStrong.
  ///
  /// In ru, this message translates to:
  /// **'стойкий'**
  String get passwordStrong;

  /// No description provided for @passwordTooShort.
  ///
  /// In ru, this message translates to:
  /// **'Короче {min} символов'**
  String passwordTooShort(int min);

  /// No description provided for @passwordForbiddenCharacter.
  ///
  /// In ru, this message translates to:
  /// **'Есть управляющий или неизвестный символ'**
  String get passwordForbiddenCharacter;

  /// No description provided for @passwordTooGuessable.
  ///
  /// In ru, this message translates to:
  /// **'Подбирается слишком быстро'**
  String get passwordTooGuessable;

  /// No description provided for @acceptWeakPassword.
  ///
  /// In ru, this message translates to:
  /// **'Понимаю риск, оставить этот пароль'**
  String get acceptWeakPassword;

  /// No description provided for @hintCommonPassword.
  ///
  /// In ru, this message translates to:
  /// **'Это один из частых паролей'**
  String get hintCommonPassword;

  /// No description provided for @hintDictionaryWord.
  ///
  /// In ru, this message translates to:
  /// **'Словарные слова подбираются первыми'**
  String get hintDictionaryWord;

  /// No description provided for @hintName.
  ///
  /// In ru, this message translates to:
  /// **'Имена и фамилии подбираются первыми'**
  String get hintName;

  /// No description provided for @hintPersonalInfo.
  ///
  /// In ru, this message translates to:
  /// **'В пароле сведения об учётной записи'**
  String get hintPersonalInfo;

  /// No description provided for @hintOtherLayout.
  ///
  /// In ru, this message translates to:
  /// **'Слово в другой раскладке не сложнее самого слова'**
  String get hintOtherLayout;

  /// No description provided for @hintSubstitution.
  ///
  /// In ru, this message translates to:
  /// **'Замены вроде @ вместо a почти не усложняют подбор'**
  String get hintSubstitution;

  /// No description provided for @hintReversed.
  ///
  /// In ru, this message translates to:
  /// **'Слово задом наперёд не сложнее самого слова'**
  String get hintReversed;

  /// No description provided for @hintKeyboardPattern.
  ///
  /// In ru, this message translates to:
  /// **'Соседние клавиши (qwerty, 1qaz) подбираются первыми'**
  String get hintKeyboardPattern;

  /// No description provided for @hintRepeat.
  ///
  /// In ru, this message translates to:
  /// **'Повторы почти не добавляют стойкости'**
  String get hintRepeat;

  /// No description provided for @hintSequence.
  ///
  /// In ru, this message translates to:
  /// **'Последовательности (abc, 123) предсказуемы'**
  String get hintSequence;

  /// No description provided for @hintDate.
  ///
  /// In ru, this message translates to:
  /// **'Даты и годы предсказуемы'**
  String get hintDate;

  /// No description provided for @phraseTitle.
  ///
  /// In ru, this message translates to:
  /// **'Фраза восстановления'**
  String get phraseTitle;

  /// No description provided for @phraseBody.
  ///
  /// In ru, this message translates to:
  /// **'Эти 24 слова — единственный способ вернуть данные, если пароль забыт или компьютер потерян. Запишите их по порядку.'**
  String get phraseBody;

  /// No description provided for @phraseTipsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Как хранить фразу'**
  String get phraseTipsTitle;

  /// No description provided for @phraseTips.
  ///
  /// In ru, this message translates to:
  /// **'Запишите на бумаге и храните отдельно от компьютера, лучше в двух местах. Не фотографируйте, не храните в облаке, почте и мессенджерах. Никому не сообщайте — мы её никогда не спросим.'**
  String get phraseTips;

  /// No description provided for @phraseWritten.
  ///
  /// In ru, this message translates to:
  /// **'Фраза записана'**
  String get phraseWritten;

  /// No description provided for @phraseExpired.
  ///
  /// In ru, this message translates to:
  /// **'Фраза устарела (агент бэкапа перезапускался). Запишите новую.'**
  String get phraseExpired;

  /// No description provided for @checkTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверка фразы'**
  String get checkTitle;

  /// No description provided for @checkBody.
  ///
  /// In ru, this message translates to:
  /// **'Введите слова с указанными номерами — так мы убедимся, что фраза записана верно.'**
  String get checkBody;

  /// No description provided for @wordNumber.
  ///
  /// In ru, this message translates to:
  /// **'Слово №{number}'**
  String wordNumber(int number);

  /// No description provided for @wordWrong.
  ///
  /// In ru, this message translates to:
  /// **'Не то слово'**
  String get wordWrong;

  /// No description provided for @createAccount.
  ///
  /// In ru, this message translates to:
  /// **'Создать учётную запись'**
  String get createAccount;

  /// No description provided for @createdTitle.
  ///
  /// In ru, this message translates to:
  /// **'Учётная запись создана'**
  String get createdTitle;

  /// No description provided for @createdBody.
  ///
  /// In ru, this message translates to:
  /// **'Ключи сохранены в хранилище ключей системы — бэкап по расписанию пойдёт без пароля. Осталось выбрать папки для бэкапа.'**
  String get createdBody;

  /// No description provided for @toBackup.
  ///
  /// In ru, this message translates to:
  /// **'Перейти к бэкапу'**
  String get toBackup;

  /// No description provided for @next.
  ///
  /// In ru, this message translates to:
  /// **'Далее'**
  String get next;

  /// No description provided for @back.
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get back;

  /// No description provided for @done.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get done;

  /// No description provided for @close.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get close;

  /// No description provided for @loginBody.
  ///
  /// In ru, this message translates to:
  /// **'Нужны имя и пароль учётной записи. Если вход по паролю выключен, восстановите доступ по фразе.'**
  String get loginBody;

  /// No description provided for @signIn.
  ///
  /// In ru, this message translates to:
  /// **'Войти'**
  String get signIn;

  /// No description provided for @signingIn.
  ///
  /// In ru, this message translates to:
  /// **'Открываем ключи и загружаем список данных…'**
  String get signingIn;

  /// No description provided for @recoverBody.
  ///
  /// In ru, this message translates to:
  /// **'Введите 24 слова фразы восстановления через пробел.'**
  String get recoverBody;

  /// No description provided for @phraseField.
  ///
  /// In ru, this message translates to:
  /// **'Фраза восстановления'**
  String get phraseField;

  /// No description provided for @phraseFieldCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} слово из 24} few{{count} слова из 24} many{{count} слов из 24} other{{count} слова из 24}}'**
  String phraseFieldCount(int count);

  /// No description provided for @recoverPasswordBody.
  ///
  /// In ru, this message translates to:
  /// **'Придумайте пароль для этого компьютера.'**
  String get recoverPasswordBody;

  /// No description provided for @recover.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить'**
  String get recover;

  /// No description provided for @signedInTitle.
  ///
  /// In ru, this message translates to:
  /// **'Компьютер подключён'**
  String get signedInTitle;

  /// No description provided for @indexNotRestored.
  ///
  /// In ru, this message translates to:
  /// **'Список данных загрузится позже'**
  String get indexNotRestored;

  /// No description provided for @latestSnapshot.
  ///
  /// In ru, this message translates to:
  /// **'Последний снимок'**
  String get latestSnapshot;

  /// No description provided for @snapshotFrom.
  ///
  /// In ru, this message translates to:
  /// **'{date}, компьютер {host}'**
  String snapshotFrom(String date, String host);

  /// No description provided for @snapshotsTotal.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{Всего {count} снимок} few{Всего {count} снимка} many{Всего {count} снимков} other{Всего {count} снимка}}'**
  String snapshotsTotal(int count);

  /// No description provided for @rollbackCheckTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сверьте последний снимок'**
  String get rollbackCheckTitle;

  /// No description provided for @rollbackCheck.
  ///
  /// In ru, this message translates to:
  /// **'Этот компьютер новый и не может сам проверить, что сервер показал все снимки. Убедитесь, что последний снимок — тот, что вы ожидаете: дата и компьютер. Если более нового снимка нет, хотя он был, не удаляйте данные на других компьютерах и сообщите нам.'**
  String get rollbackCheck;

  /// No description provided for @rollbackWarningTitle.
  ///
  /// In ru, this message translates to:
  /// **'Похоже, сервер показал не все снимки'**
  String get rollbackWarningTitle;

  /// No description provided for @rollbackWarning.
  ///
  /// In ru, this message translates to:
  /// **'Список снимков не сходится с тем, что известно этому компьютеру: возможен откат. Не удаляйте данные на других компьютерах и сообщите нам.'**
  String get rollbackWarning;

  /// No description provided for @restoreAllTitle.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить данные'**
  String get restoreAllTitle;

  /// No description provided for @restoreAllBody.
  ///
  /// In ru, this message translates to:
  /// **'Файлы последнего снимка будут восстановлены в эту папку. Ход восстановления — на экране «Обзор».'**
  String get restoreAllBody;

  /// No description provided for @restoreTarget.
  ///
  /// In ru, this message translates to:
  /// **'Папка для восстановления'**
  String get restoreTarget;

  /// No description provided for @restoredFolder.
  ///
  /// In ru, this message translates to:
  /// **'Восстановлено'**
  String get restoredFolder;

  /// No description provided for @restoreAll.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить всё'**
  String get restoreAll;

  /// No description provided for @restoreLater.
  ///
  /// In ru, this message translates to:
  /// **'Позже'**
  String get restoreLater;

  /// No description provided for @accountSection.
  ///
  /// In ru, this message translates to:
  /// **'Учётная запись'**
  String get accountSection;

  /// No description provided for @thisDevice.
  ///
  /// In ru, this message translates to:
  /// **'Это устройство'**
  String get thisDevice;

  /// No description provided for @newDeviceSignIn.
  ///
  /// In ru, this message translates to:
  /// **'Новое устройство'**
  String get newDeviceSignIn;

  /// No description provided for @signInByPasswordOrPhrase.
  ///
  /// In ru, this message translates to:
  /// **'по паролю или по фразе'**
  String get signInByPasswordOrPhrase;

  /// No description provided for @signInByPhraseOnly.
  ///
  /// In ru, this message translates to:
  /// **'только по фразе'**
  String get signInByPhraseOnly;

  /// No description provided for @unknown.
  ///
  /// In ru, this message translates to:
  /// **'неизвестно'**
  String get unknown;

  /// No description provided for @changePassword.
  ///
  /// In ru, this message translates to:
  /// **'Сменить пароль'**
  String get changePassword;

  /// No description provided for @passwordChanged.
  ///
  /// In ru, this message translates to:
  /// **'Пароль изменён.'**
  String get passwordChanged;

  /// No description provided for @passwordChangedEverywhere.
  ///
  /// In ru, this message translates to:
  /// **'Пароль изменён здесь и в копии ключа на сервере.'**
  String get passwordChangedEverywhere;

  /// No description provided for @passwordChangedKeyCopyUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Пароль изменён здесь. Неизвестно, есть ли на сервере копия ключа под старым паролем, — включите или выключите копию ключа заново.'**
  String get passwordChangedKeyCopyUnknown;

  /// No description provided for @showPhrase.
  ///
  /// In ru, this message translates to:
  /// **'Показать фразу'**
  String get showPhrase;

  /// No description provided for @showPhraseBody.
  ///
  /// In ru, this message translates to:
  /// **'Фраза восстановления даёт полный доступ к данным. Убедитесь, что экран никто не видит.'**
  String get showPhraseBody;

  /// No description provided for @show.
  ///
  /// In ru, this message translates to:
  /// **'Показать'**
  String get show;

  /// No description provided for @keyCopySwitch.
  ///
  /// In ru, this message translates to:
  /// **'Копия ключа на сервере (вход по паролю)'**
  String get keyCopySwitch;

  /// No description provided for @keyCopyEnableTitle.
  ///
  /// In ru, this message translates to:
  /// **'Включить вход по паролю'**
  String get keyCopyEnableTitle;

  /// No description provided for @keyCopyDisableTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выключить вход по паролю'**
  String get keyCopyDisableTitle;

  /// No description provided for @enable.
  ///
  /// In ru, this message translates to:
  /// **'Включить'**
  String get enable;

  /// No description provided for @disable.
  ///
  /// In ru, this message translates to:
  /// **'Выключить'**
  String get disable;

  /// No description provided for @devicesSection.
  ///
  /// In ru, this message translates to:
  /// **'Устройства'**
  String get devicesSection;

  /// No description provided for @deviceCurrent.
  ///
  /// In ru, this message translates to:
  /// **'{id} — это устройство'**
  String deviceCurrent(String id);

  /// No description provided for @deviceAddedAt.
  ///
  /// In ru, this message translates to:
  /// **'добавлено {date}'**
  String deviceAddedAt(String date);

  /// No description provided for @deviceRevokedAt.
  ///
  /// In ru, this message translates to:
  /// **'отозвано {date}'**
  String deviceRevokedAt(String date);

  /// No description provided for @revoke.
  ///
  /// In ru, this message translates to:
  /// **'Отозвать'**
  String get revoke;

  /// No description provided for @revokeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отозвать устройство?'**
  String get revokeTitle;

  /// No description provided for @revokeBody.
  ///
  /// In ru, this message translates to:
  /// **'Устройство {id} сразу потеряет доступ к учётной записи и данным на сервере. Вернуть его можно только заново — по паролю или фразе.'**
  String revokeBody(String id);

  /// No description provided for @revoked.
  ///
  /// In ru, this message translates to:
  /// **'Устройство отозвано — доступ закрыт.'**
  String get revoked;

  /// No description provided for @errorWeakPassword.
  ///
  /// In ru, this message translates to:
  /// **'Пароль слишком простой'**
  String get errorWeakPassword;

  /// No description provided for @errorPhraseNotConfirmed.
  ///
  /// In ru, this message translates to:
  /// **'Слова фразы не совпадают'**
  String get errorPhraseNotConfirmed;

  /// No description provided for @errorBadPhrase.
  ///
  /// In ru, this message translates to:
  /// **'Фраза введена с ошибкой: проверьте слова и их порядок'**
  String get errorBadPhrase;

  /// No description provided for @errorLoginTaken.
  ///
  /// In ru, this message translates to:
  /// **'Это имя занято, выберите другое'**
  String get errorLoginTaken;

  /// No description provided for @errorUnauthenticated.
  ///
  /// In ru, this message translates to:
  /// **'Неверное имя или пароль, либо вход по паролю выключен — тогда восстановите доступ по фразе'**
  String get errorUnauthenticated;

  /// No description provided for @errorTooManyDevices.
  ///
  /// In ru, this message translates to:
  /// **'У учётной записи уже 5 устройств: отзовите ненужное на другом устройстве'**
  String get errorTooManyDevices;

  /// No description provided for @errorCurrentDevice.
  ///
  /// In ru, this message translates to:
  /// **'Это устройство нельзя отозвать с него самого'**
  String get errorCurrentDevice;

  /// No description provided for @errorNoPhrase.
  ///
  /// In ru, this message translates to:
  /// **'На этом устройстве нет копии фразы: оно подключено по паролю'**
  String get errorNoPhrase;

  /// No description provided for @errorRateLimited.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много попыток, попробуйте позже'**
  String get errorRateLimited;

  /// No description provided for @errorUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Сервер недоступен, проверьте подключение к интернету'**
  String get errorUnavailable;

  /// No description provided for @errorExists.
  ///
  /// In ru, this message translates to:
  /// **'На этом устройстве уже есть учётная запись'**
  String get errorExists;
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
