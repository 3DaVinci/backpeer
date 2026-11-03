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

  /// Название продукта (С.1.2)
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
  /// **'Ключи сохранены в хранилище ключей системы — бэкап по расписанию пойдёт без пароля.'**
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

  /// No description provided for @later.
  ///
  /// In ru, this message translates to:
  /// **'Позже'**
  String get later;

  /// No description provided for @onboardKeeperTitle.
  ///
  /// In ru, this message translates to:
  /// **'Станьте хранителем'**
  String get onboardKeeperTitle;

  /// No description provided for @onboardKeeperBody.
  ///
  /// In ru, this message translates to:
  /// **'Backpeer хранит бэкапы на компьютерах участников. Отдайте часть свободного места на этом компьютере: выберите папку и сколько отдать — остальное хранитель сделает сам, в фоне.'**
  String get onboardKeeperBody;

  /// No description provided for @onboardKeeperLater.
  ///
  /// In ru, this message translates to:
  /// **'Можно и позже — в разделе «Хранитель». Папки для бэкапа выбираются следующим шагом, в разделе «Бэкап».'**
  String get onboardKeeperLater;

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

  /// No description provided for @agentStatusWaitingForPower.
  ///
  /// In ru, this message translates to:
  /// **'Ждёт питания от сети'**
  String get agentStatusWaitingForPower;

  /// No description provided for @healthTitle.
  ///
  /// In ru, this message translates to:
  /// **'Здоровье данных'**
  String get healthTitle;

  /// No description provided for @healthOk.
  ///
  /// In ru, this message translates to:
  /// **'Всё в порядке'**
  String get healthOk;

  /// No description provided for @healthOkHint.
  ///
  /// In ru, this message translates to:
  /// **'Бэкап свежий, проверка не нашла проблем.'**
  String get healthOkHint;

  /// No description provided for @healthRepairing.
  ///
  /// In ru, this message translates to:
  /// **'Ремонтируется'**
  String get healthRepairing;

  /// No description provided for @healthRepairingHint.
  ///
  /// In ru, this message translates to:
  /// **'Часть хранителей ушла, сеть восстанавливает фрагменты. Данные целы.'**
  String get healthRepairingHint;

  /// No description provided for @healthAttention.
  ///
  /// In ru, this message translates to:
  /// **'Требует внимания'**
  String get healthAttention;

  /// No description provided for @healthUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Бэкапа ещё не было'**
  String get healthUnknown;

  /// No description provided for @healthUnknownHint.
  ///
  /// In ru, this message translates to:
  /// **'Выберите папки в разделе «Бэкап» — первый бэкап начнётся сам.'**
  String get healthUnknownHint;

  /// No description provided for @healthReasonBackupFailed.
  ///
  /// In ru, this message translates to:
  /// **'Последний бэкап не удался'**
  String get healthReasonBackupFailed;

  /// No description provided for @healthReasonBackupStale.
  ///
  /// In ru, this message translates to:
  /// **'Бэкап давно не делался: компьютер был выключен или бэкап не проходит'**
  String get healthReasonBackupStale;

  /// No description provided for @healthReasonRollbackWarning.
  ///
  /// In ru, this message translates to:
  /// **'Сервер показал не все снимки — список мог быть подменён'**
  String get healthReasonRollbackWarning;

  /// No description provided for @healthReasonUnrecoverable.
  ///
  /// In ru, this message translates to:
  /// **'Часть данных нельзя восстановить'**
  String get healthReasonUnrecoverable;

  /// No description provided for @healthReasonAtRisk.
  ///
  /// In ru, this message translates to:
  /// **'У части данных почти не осталось запаса'**
  String get healthReasonAtRisk;

  /// No description provided for @healthReasonFragmentsMissing.
  ///
  /// In ru, this message translates to:
  /// **'Часть фрагментов недоступна, запас есть'**
  String get healthReasonFragmentsMissing;

  /// No description provided for @healthReasonVerifyFailed.
  ///
  /// In ru, this message translates to:
  /// **'Проверка не удалась'**
  String get healthReasonVerifyFailed;

  /// No description provided for @healthReasonNeverVerified.
  ///
  /// In ru, this message translates to:
  /// **'Бэкап ещё не проверялся'**
  String get healthReasonNeverVerified;

  /// No description provided for @lastVerify.
  ///
  /// In ru, this message translates to:
  /// **'Последняя проверка'**
  String get lastVerify;

  /// No description provided for @verifyNow.
  ///
  /// In ru, this message translates to:
  /// **'Проверить сейчас'**
  String get verifyNow;

  /// No description provided for @progressOf.
  ///
  /// In ru, this message translates to:
  /// **'{done} из {total}'**
  String progressOf(String done, String total);

  /// No description provided for @progressSpeed.
  ///
  /// In ru, this message translates to:
  /// **'{size}/с'**
  String progressSpeed(String size);

  /// No description provided for @progressEta.
  ///
  /// In ru, this message translates to:
  /// **'осталось около {time}'**
  String progressEta(String time);

  /// No description provided for @durationMinutes.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} минуты} few{{count} минут} many{{count} минут} other{{count} минуты}}'**
  String durationMinutes(int count);

  /// No description provided for @durationHours.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} часа} few{{count} часов} many{{count} часов} other{{count} часа}}'**
  String durationHours(int count);

  /// No description provided for @lessThanMinute.
  ///
  /// In ru, this message translates to:
  /// **'минуты'**
  String get lessThanMinute;

  /// No description provided for @resumedNote.
  ///
  /// In ru, this message translates to:
  /// **'Продолжение прерванного бэкапа'**
  String get resumedNote;

  /// No description provided for @estimating.
  ///
  /// In ru, this message translates to:
  /// **'Считаем объём…'**
  String get estimating;

  /// No description provided for @currentBackup.
  ///
  /// In ru, this message translates to:
  /// **'Текущий бэкап'**
  String get currentBackup;

  /// No description provided for @addFolder.
  ///
  /// In ru, this message translates to:
  /// **'Добавить папку'**
  String get addFolder;

  /// No description provided for @removeFolder.
  ///
  /// In ru, this message translates to:
  /// **'Убрать из бэкапа'**
  String get removeFolder;

  /// No description provided for @folderPickerFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть выбор папки'**
  String get folderPickerFailed;

  /// No description provided for @excludes.
  ///
  /// In ru, this message translates to:
  /// **'Исключения'**
  String get excludes;

  /// No description provided for @presetTemporary.
  ///
  /// In ru, this message translates to:
  /// **'Временные файлы'**
  String get presetTemporary;

  /// No description provided for @presetCaches.
  ///
  /// In ru, this message translates to:
  /// **'Кеши программ'**
  String get presetCaches;

  /// No description provided for @presetTrash.
  ///
  /// In ru, this message translates to:
  /// **'Корзина'**
  String get presetTrash;

  /// No description provided for @presetDevelopment.
  ///
  /// In ru, this message translates to:
  /// **'Зависимости и сборка программ'**
  String get presetDevelopment;

  /// No description provided for @customRules.
  ///
  /// In ru, this message translates to:
  /// **'Свои правила'**
  String get customRules;

  /// No description provided for @addRule.
  ///
  /// In ru, this message translates to:
  /// **'Добавить правило'**
  String get addRule;

  /// No description provided for @ruleHint.
  ///
  /// In ru, this message translates to:
  /// **'Например: *.iso или Видео/'**
  String get ruleHint;

  /// No description provided for @removeRule.
  ///
  /// In ru, this message translates to:
  /// **'Убрать правило'**
  String get removeRule;

  /// No description provided for @estimate.
  ///
  /// In ru, this message translates to:
  /// **'Оценить объём'**
  String get estimate;

  /// No description provided for @estimateHint.
  ///
  /// In ru, this message translates to:
  /// **'Посмотрите, сколько займёт бэкап, до его запуска.'**
  String get estimateHint;

  /// No description provided for @estimateResult.
  ///
  /// In ru, this message translates to:
  /// **'{files}, {size}'**
  String estimateResult(String files, String size);

  /// No description provided for @estimateExcluded.
  ///
  /// In ru, this message translates to:
  /// **'Исключено правилами: {count}'**
  String estimateExcluded(int count);

  /// No description provided for @estimateSkipped.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа или особые файлы: {count}'**
  String estimateSkipped(int count);

  /// No description provided for @estimateTruncated.
  ///
  /// In ru, this message translates to:
  /// **'Файлов очень много — подсчитана только часть.'**
  String get estimateTruncated;

  /// No description provided for @estimateNetwork.
  ///
  /// In ru, this message translates to:
  /// **'В сети займёт больше — с запасом на надёжность; одинаковые данные хранятся один раз.'**
  String get estimateNetwork;

  /// No description provided for @frequency.
  ///
  /// In ru, this message translates to:
  /// **'Как часто'**
  String get frequency;

  /// No description provided for @frequencyHourly.
  ///
  /// In ru, this message translates to:
  /// **'раз в час'**
  String get frequencyHourly;

  /// No description provided for @frequencyDaily.
  ///
  /// In ru, this message translates to:
  /// **'раз в день'**
  String get frequencyDaily;

  /// No description provided for @frequencyWeekly.
  ///
  /// In ru, this message translates to:
  /// **'раз в неделю'**
  String get frequencyWeekly;

  /// No description provided for @onlyHours.
  ///
  /// In ru, this message translates to:
  /// **'Только в заданные часы'**
  String get onlyHours;

  /// No description provided for @hoursFrom.
  ///
  /// In ru, this message translates to:
  /// **'С'**
  String get hoursFrom;

  /// No description provided for @hoursTo.
  ///
  /// In ru, this message translates to:
  /// **'До'**
  String get hoursTo;

  /// No description provided for @hourValue.
  ///
  /// In ru, this message translates to:
  /// **'{hour}:00'**
  String hourValue(int hour);

  /// No description provided for @onlyOnAc.
  ///
  /// In ru, this message translates to:
  /// **'Только от сети'**
  String get onlyOnAc;

  /// No description provided for @onlyOnAcHint.
  ///
  /// In ru, this message translates to:
  /// **'От батареи бэкап по расписанию подождёт, а начатый — остановится и продолжится от сети.'**
  String get onlyOnAcHint;

  /// No description provided for @verifySchedule.
  ///
  /// In ru, this message translates to:
  /// **'Проверка бэкапа'**
  String get verifySchedule;

  /// No description provided for @scheduleNote.
  ///
  /// In ru, this message translates to:
  /// **'Бэкап по расписанию делает фоновый агент — окно можно закрыть.'**
  String get scheduleNote;

  /// No description provided for @retention.
  ///
  /// In ru, this message translates to:
  /// **'Хранение снимков'**
  String get retention;

  /// No description provided for @keepAll.
  ///
  /// In ru, this message translates to:
  /// **'Хранить все снимки'**
  String get keepAll;

  /// No description provided for @keepLast.
  ///
  /// In ru, this message translates to:
  /// **'Последних'**
  String get keepLast;

  /// No description provided for @keepHourly.
  ///
  /// In ru, this message translates to:
  /// **'Почасовых'**
  String get keepHourly;

  /// No description provided for @keepDaily.
  ///
  /// In ru, this message translates to:
  /// **'Дневных'**
  String get keepDaily;

  /// No description provided for @keepWeekly.
  ///
  /// In ru, this message translates to:
  /// **'Недельных'**
  String get keepWeekly;

  /// No description provided for @keepMonthly.
  ///
  /// In ru, this message translates to:
  /// **'Месячных'**
  String get keepMonthly;

  /// No description provided for @retentionHint.
  ///
  /// In ru, this message translates to:
  /// **'В каждом часе, дне, неделе и месяце остаётся самый новый снимок. Лишние агент удаляет после бэкапа и освобождает место. Снимки других компьютеров не трогаются.'**
  String get retentionHint;

  /// No description provided for @retentionInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Целое число от 0; последних — хотя бы 1'**
  String get retentionInvalid;

  /// No description provided for @save.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In ru, this message translates to:
  /// **'Сохранено'**
  String get saved;

  /// No description provided for @history.
  ///
  /// In ru, this message translates to:
  /// **'История'**
  String get history;

  /// No description provided for @noHistory.
  ///
  /// In ru, this message translates to:
  /// **'Заданий ещё не было'**
  String get noHistory;

  /// No description provided for @triggerSchedule.
  ///
  /// In ru, this message translates to:
  /// **'по расписанию'**
  String get triggerSchedule;

  /// No description provided for @triggerManual.
  ///
  /// In ru, this message translates to:
  /// **'вручную'**
  String get triggerManual;

  /// No description provided for @triggerResume.
  ///
  /// In ru, this message translates to:
  /// **'продолжение'**
  String get triggerResume;

  /// No description provided for @historyContinues.
  ///
  /// In ru, this message translates to:
  /// **'продолжится с того же места'**
  String get historyContinues;

  /// No description provided for @reasonPaused.
  ///
  /// In ru, this message translates to:
  /// **'пауза'**
  String get reasonPaused;

  /// No description provided for @reasonOnBattery.
  ///
  /// In ru, this message translates to:
  /// **'переход на батарею'**
  String get reasonOnBattery;

  /// No description provided for @newData.
  ///
  /// In ru, this message translates to:
  /// **'новых данных {size}'**
  String newData(String size);

  /// No description provided for @skippedCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{пропущен {count} файл} few{пропущено {count} файла} many{пропущено {count} файлов} other{пропущено {count} файла}}'**
  String skippedCount(int count);

  /// No description provided for @details.
  ///
  /// In ru, this message translates to:
  /// **'Подробности'**
  String get details;

  /// No description provided for @skippedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пропущенные файлы'**
  String get skippedTitle;

  /// No description provided for @skippedExplain.
  ///
  /// In ru, this message translates to:
  /// **'Эти файлы не попали в снимок. Чаще всего это файлы без права чтения или изменившиеся во время чтения — следующий бэкап попробует снова.'**
  String get skippedExplain;

  /// No description provided for @skipReasonError.
  ///
  /// In ru, this message translates to:
  /// **'нет доступа или ошибка чтения'**
  String get skipReasonError;

  /// No description provided for @skipReasonSpecial.
  ///
  /// In ru, this message translates to:
  /// **'особый файл (сокет, устройство) — такие не сохраняются'**
  String get skipReasonSpecial;

  /// No description provided for @retentionResult.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{удалён {count} старый снимок} few{удалено {count} старых снимка} many{удалено {count} старых снимков} other{удалено {count} старых снимка}}'**
  String retentionResult(int count);

  /// No description provided for @freed.
  ///
  /// In ru, this message translates to:
  /// **'освобождено {size}'**
  String freed(String size);

  /// No description provided for @verifyResult.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{проверен {count} сегмент} few{проверено {count} сегмента} many{проверено {count} сегментов} other{проверено {count} сегмента}}'**
  String verifyResult(int count);

  /// No description provided for @errorText.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка: {message}'**
  String errorText(String message);

  /// No description provided for @snapshotsOnRestore.
  ///
  /// In ru, this message translates to:
  /// **'Список снимков — в разделе «Восстановление».'**
  String get snapshotsOnRestore;

  /// No description provided for @restoreOpenSnapshot.
  ///
  /// In ru, this message translates to:
  /// **'Открыть снимок'**
  String get restoreOpenSnapshot;

  /// No description provided for @browserBack.
  ///
  /// In ru, this message translates to:
  /// **'К списку снимков'**
  String get browserBack;

  /// No description provided for @browserRoot.
  ///
  /// In ru, this message translates to:
  /// **'Снимок'**
  String get browserRoot;

  /// No description provided for @searchHint.
  ///
  /// In ru, this message translates to:
  /// **'Поиск по имени: часть имени или шаблон вроде *.pdf'**
  String get searchHint;

  /// No description provided for @searchClear.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить поиск'**
  String get searchClear;

  /// No description provided for @searchResults.
  ///
  /// In ru, this message translates to:
  /// **'Найдено: {count}'**
  String searchResults(int count);

  /// No description provided for @searchTruncated.
  ///
  /// In ru, this message translates to:
  /// **'Показаны первые {count}. Уточните запрос.'**
  String searchTruncated(int count);

  /// No description provided for @searchNothing.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get searchNothing;

  /// No description provided for @folderEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Папка пуста'**
  String get folderEmpty;

  /// No description provided for @loadingItem.
  ///
  /// In ru, this message translates to:
  /// **'Загрузка…'**
  String get loadingItem;

  /// No description provided for @selectedCount.
  ///
  /// In ru, this message translates to:
  /// **'Выбрано: {count}'**
  String selectedCount(int count);

  /// No description provided for @restoreSelected.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить выбранное'**
  String get restoreSelected;

  /// No description provided for @clearSelection.
  ///
  /// In ru, this message translates to:
  /// **'Снять выделение'**
  String get clearSelection;

  /// No description provided for @fileVersions.
  ///
  /// In ru, this message translates to:
  /// **'Версии файла'**
  String get fileVersions;

  /// No description provided for @versionsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Версии «{name}»'**
  String versionsTitle(String name);

  /// No description provided for @versionChanged.
  ///
  /// In ru, this message translates to:
  /// **'изменён'**
  String get versionChanged;

  /// No description provided for @versionSame.
  ///
  /// In ru, this message translates to:
  /// **'без изменений'**
  String get versionSame;

  /// No description provided for @versionAbsent.
  ///
  /// In ru, this message translates to:
  /// **'нет в этом снимке'**
  String get versionAbsent;

  /// No description provided for @restoreThisVersion.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить'**
  String get restoreThisVersion;

  /// No description provided for @chooseFolder.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать папку'**
  String get chooseFolder;

  /// No description provided for @restoreWhat.
  ///
  /// In ru, this message translates to:
  /// **'Что: {what}'**
  String restoreWhat(String what);

  /// No description provided for @restoreWholeSnapshot.
  ///
  /// In ru, this message translates to:
  /// **'весь снимок'**
  String get restoreWholeSnapshot;

  /// No description provided for @restoreWhere.
  ///
  /// In ru, this message translates to:
  /// **'Куда'**
  String get restoreWhere;

  /// No description provided for @restoreOriginal.
  ///
  /// In ru, this message translates to:
  /// **'На исходное место'**
  String get restoreOriginal;

  /// No description provided for @restoreOriginalHint.
  ///
  /// In ru, this message translates to:
  /// **'Файлы вернутся туда, откуда были сохранены.'**
  String get restoreOriginalHint;

  /// No description provided for @restoreToFolder.
  ///
  /// In ru, this message translates to:
  /// **'В другую папку'**
  String get restoreToFolder;

  /// No description provided for @restoreExisting.
  ///
  /// In ru, this message translates to:
  /// **'Если такой файл уже есть'**
  String get restoreExisting;

  /// No description provided for @existingKeepBoth.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить оба: к имени восстановленного добавится «(восстановлено)»'**
  String get existingKeepBoth;

  /// No description provided for @existingSkip.
  ///
  /// In ru, this message translates to:
  /// **'Оставить существующий, восстановленный не записывать'**
  String get existingSkip;

  /// No description provided for @existingOverwrite.
  ///
  /// In ru, this message translates to:
  /// **'Заменить существующий восстановленным'**
  String get existingOverwrite;

  /// No description provided for @restoredSuffix.
  ///
  /// In ru, this message translates to:
  /// **'восстановлено'**
  String get restoredSuffix;

  /// No description provided for @restoreWait.
  ///
  /// In ru, this message translates to:
  /// **'Если часть хранителей не в сети'**
  String get restoreWait;

  /// No description provided for @waitNone.
  ///
  /// In ru, this message translates to:
  /// **'Не ждать — восстановить то, что доступно'**
  String get waitNone;

  /// No description provided for @waitHour.
  ///
  /// In ru, this message translates to:
  /// **'Ждать до часа'**
  String get waitHour;

  /// No description provided for @waitDay.
  ///
  /// In ru, this message translates to:
  /// **'Ждать до суток'**
  String get waitDay;

  /// No description provided for @restoreStart.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить'**
  String get restoreStart;

  /// No description provided for @restoreStarted.
  ///
  /// In ru, this message translates to:
  /// **'Восстановление началось. Ход — здесь и на «Обзоре».'**
  String get restoreStarted;

  /// No description provided for @restoreCurrent.
  ///
  /// In ru, this message translates to:
  /// **'Текущее восстановление'**
  String get restoreCurrent;

  /// No description provided for @waitingTitle.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} файл ждёт хранителей} few{{count} файла ждут хранителей} many{{count} файлов ждут хранителей} other{{count} файла ждут хранителей}}'**
  String waitingTitle(int count);

  /// No description provided for @waitingExplain.
  ///
  /// In ru, this message translates to:
  /// **'Части этих файлов лежат у хранителей, которые сейчас не в сети: доступных фрагментов меньше, чем нужно для сборки. Остальное уже восстанавливается, а эти файлы докачаются, когда хранители появятся.'**
  String get waitingExplain;

  /// No description provided for @andMore.
  ///
  /// In ru, this message translates to:
  /// **'и ещё {count}'**
  String andMore(int count);

  /// No description provided for @waitingRetry.
  ///
  /// In ru, this message translates to:
  /// **'Следующая попытка — в течение {time}'**
  String waitingRetry(String time);

  /// No description provided for @waitingLeft.
  ///
  /// In ru, this message translates to:
  /// **'Ждём ещё не дольше {time}'**
  String waitingLeft(String time);

  /// No description provided for @waitingReason.
  ///
  /// In ru, this message translates to:
  /// **'Подробности: {reason}'**
  String waitingReason(String reason);

  /// No description provided for @lastRestore.
  ///
  /// In ru, this message translates to:
  /// **'Последнее восстановление'**
  String get lastRestore;

  /// No description provided for @restoreWhen.
  ///
  /// In ru, this message translates to:
  /// **'Когда'**
  String get restoreWhen;

  /// No description provided for @restoreProblem.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка'**
  String get restoreProblem;

  /// No description provided for @restoreWhereLabel.
  ///
  /// In ru, this message translates to:
  /// **'Куда'**
  String get restoreWhereLabel;

  /// No description provided for @restoreRestored.
  ///
  /// In ru, this message translates to:
  /// **'Восстановлено'**
  String get restoreRestored;

  /// No description provided for @restoreSkippedLabel.
  ///
  /// In ru, this message translates to:
  /// **'Не тронуто существующих'**
  String get restoreSkippedLabel;

  /// No description provided for @restoreRenamedLabel.
  ///
  /// In ru, this message translates to:
  /// **'Сохранено рядом с существующими'**
  String get restoreRenamedLabel;

  /// No description provided for @restoreErrorsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Не восстановлено'**
  String get restoreErrorsLabel;

  /// No description provided for @speedUnlimited.
  ///
  /// In ru, this message translates to:
  /// **'без предела'**
  String get speedUnlimited;

  /// No description provided for @speedValue.
  ///
  /// In ru, this message translates to:
  /// **'{size}/с'**
  String speedValue(String size);

  /// No description provided for @keeperEnableTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отдать место'**
  String get keeperEnableTitle;

  /// No description provided for @keeperEditTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройки хранителя'**
  String get keeperEditTitle;

  /// No description provided for @keeperPrivacy.
  ///
  /// In ru, this message translates to:
  /// **'Фрагменты шифруются на компьютере владельца ещё до отправки. Хранитель не может их прочитать и не знает, чьи это файлы и как они называются.'**
  String get keeperPrivacy;

  /// No description provided for @keeperFolder.
  ///
  /// In ru, this message translates to:
  /// **'Папка для фрагментов'**
  String get keeperFolder;

  /// No description provided for @keeperFree.
  ///
  /// In ru, this message translates to:
  /// **'Свободно на диске: {size}'**
  String keeperFree(String size);

  /// No description provided for @keeperQuotaLabel.
  ///
  /// In ru, this message translates to:
  /// **'Сколько места отдать, ГБ'**
  String get keeperQuotaLabel;

  /// No description provided for @keeperQuotaInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Введите число гигабайт'**
  String get keeperQuotaInvalid;

  /// No description provided for @keeperQuotaTooBig.
  ///
  /// In ru, this message translates to:
  /// **'Больше, чем свободно на диске'**
  String get keeperQuotaTooBig;

  /// No description provided for @keeperQuotaMin.
  ///
  /// In ru, this message translates to:
  /// **'Сервер обычно принимает хранителей от 100 ГБ'**
  String get keeperQuotaMin;

  /// No description provided for @keeperUpload.
  ///
  /// In ru, this message translates to:
  /// **'Отдача'**
  String get keeperUpload;

  /// No description provided for @keeperDownload.
  ///
  /// In ru, this message translates to:
  /// **'Приём'**
  String get keeperDownload;

  /// No description provided for @keeperWorkHours.
  ///
  /// In ru, this message translates to:
  /// **'В рабочие часы (пн–пт, 9–18)'**
  String get keeperWorkHours;

  /// No description provided for @keeperBackgroundNote.
  ///
  /// In ru, this message translates to:
  /// **'Хранитель работает в фоне и без открытого окна.'**
  String get keeperBackgroundNote;

  /// No description provided for @keeperEnable.
  ///
  /// In ru, this message translates to:
  /// **'Стать хранителем'**
  String get keeperEnable;

  /// No description provided for @keeperEnabled.
  ///
  /// In ru, this message translates to:
  /// **'Роль хранителя включена'**
  String get keeperEnabled;

  /// No description provided for @keeperNoBinary.
  ///
  /// In ru, this message translates to:
  /// **'Настройки сохранены, но программа хранителя не найдена рядом с приложением. Запустите службу хранителя вручную.'**
  String get keeperNoBinary;

  /// No description provided for @keeperNoCoordinator.
  ///
  /// In ru, this message translates to:
  /// **'Учётная запись без сервера: хранителю негде зарегистрироваться.'**
  String get keeperNoCoordinator;

  /// No description provided for @keeperNotRunning.
  ///
  /// In ru, this message translates to:
  /// **'Роль включена, но служба хранителя не запущена.'**
  String get keeperNotRunning;

  /// No description provided for @keeperStart.
  ///
  /// In ru, this message translates to:
  /// **'Запустить'**
  String get keeperStart;

  /// No description provided for @keeperStats.
  ///
  /// In ru, this message translates to:
  /// **'Статистика'**
  String get keeperStats;

  /// No description provided for @keeperFreeQuota.
  ///
  /// In ru, this message translates to:
  /// **'Свободно из отданного'**
  String get keeperFreeQuota;

  /// No description provided for @keeperDisk.
  ///
  /// In ru, this message translates to:
  /// **'Свободно на диске'**
  String get keeperDisk;

  /// No description provided for @keeperTraffic.
  ///
  /// In ru, this message translates to:
  /// **'Трафик с запуска'**
  String get keeperTraffic;

  /// No description provided for @keeperTrafficValue.
  ///
  /// In ru, this message translates to:
  /// **'отдано {sent}, принято {received}'**
  String keeperTrafficValue(String sent, String received);

  /// No description provided for @keeperUdp.
  ///
  /// In ru, this message translates to:
  /// **'по UDP после сведения'**
  String get keeperUdp;

  /// No description provided for @keeperRelay.
  ///
  /// In ru, this message translates to:
  /// **'через relay'**
  String get keeperRelay;

  /// No description provided for @keeperNoIncoming.
  ///
  /// In ru, this message translates to:
  /// **'входящих соединений нет'**
  String get keeperNoIncoming;

  /// No description provided for @keeperPortHint.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы к этому компьютеру подключались напрямую и быстрее, откройте на роутере порт {port} (TCP и UDP) или включите на нём UPnP.'**
  String keeperPortHint(int port);

  /// No description provided for @keeperPortMappingError.
  ///
  /// In ru, this message translates to:
  /// **'Автоматически открыть порт не получилось: {error}'**
  String keeperPortMappingError(String error);

  /// No description provided for @keeperCoordinator.
  ///
  /// In ru, this message translates to:
  /// **'Как вас видит сервер'**
  String get keeperCoordinator;

  /// No description provided for @keeperNoCoordinatorShort.
  ///
  /// In ru, this message translates to:
  /// **'сервер не задан'**
  String get keeperNoCoordinatorShort;

  /// No description provided for @keeperRegistered.
  ///
  /// In ru, this message translates to:
  /// **'зарегистрирован'**
  String get keeperRegistered;

  /// No description provided for @keeperNotRegistered.
  ///
  /// In ru, this message translates to:
  /// **'не зарегистрирован: {error}'**
  String keeperNotRegistered(String error);

  /// No description provided for @keeperWaitingCoordinator.
  ///
  /// In ru, this message translates to:
  /// **'ждём ответа сервера'**
  String get keeperWaitingCoordinator;

  /// No description provided for @keeperAvailability.
  ///
  /// In ru, this message translates to:
  /// **'Доступность за 30 дней'**
  String get keeperAvailability;

  /// No description provided for @keeperReputation.
  ///
  /// In ru, this message translates to:
  /// **'Репутация'**
  String get keeperReputation;

  /// No description provided for @keeperProbation.
  ///
  /// In ru, this message translates to:
  /// **'испытательный срок до {date}'**
  String keeperProbation(String date);

  /// No description provided for @keeperAudits.
  ///
  /// In ru, this message translates to:
  /// **'Проверки хранения'**
  String get keeperAudits;

  /// No description provided for @keeperAuditsValue.
  ///
  /// In ru, this message translates to:
  /// **'пройдено {passed}, провалено {failed}'**
  String keeperAuditsValue(int passed, int failed);

  /// No description provided for @keeperExcluded.
  ///
  /// In ru, this message translates to:
  /// **'Сервер исключил этого хранителя: новых фрагментов не будет.'**
  String get keeperExcluded;

  /// No description provided for @keeperStandingSoon.
  ///
  /// In ru, this message translates to:
  /// **'Сведения появятся после следующей связи с сервером.'**
  String get keeperStandingSoon;

  /// No description provided for @keeperBarter.
  ///
  /// In ru, this message translates to:
  /// **'Баланс'**
  String get keeperBarter;

  /// No description provided for @keeperBarterSoon.
  ///
  /// In ru, this message translates to:
  /// **'Здесь появится баланс бартера: сколько места вы отдали и сколько можете хранить сами.'**
  String get keeperBarterSoon;

  /// No description provided for @keeperRole.
  ///
  /// In ru, this message translates to:
  /// **'Роль хранителя'**
  String get keeperRole;

  /// No description provided for @keeperChange.
  ///
  /// In ru, this message translates to:
  /// **'Изменить'**
  String get keeperChange;

  /// No description provided for @keeperStop.
  ///
  /// In ru, this message translates to:
  /// **'Выключить хранителя'**
  String get keeperStop;

  /// No description provided for @keeperStopConfirm.
  ///
  /// In ru, this message translates to:
  /// **'Хранитель остановится, фрагменты останутся на диске. Если он долго не вернётся, сервер восстановит эти фрагменты у других хранителей. Включить снова можно в любой момент.'**
  String get keeperStopConfirm;

  /// No description provided for @keeperLeave.
  ///
  /// In ru, this message translates to:
  /// **'Выйти из роли'**
  String get keeperLeave;

  /// No description provided for @keeperLeaveSoon.
  ///
  /// In ru, this message translates to:
  /// **'Выход с переносом фрагментов к другим хранителям и освобождением места появится в следующих версиях. Пока хранителя можно выключить.'**
  String get keeperLeaveSoon;

  /// No description provided for @trayBackupNow.
  ///
  /// In ru, this message translates to:
  /// **'Сделать бэкап сейчас'**
  String get trayBackupNow;

  /// No description provided for @trayPause.
  ///
  /// In ru, this message translates to:
  /// **'Приостановить'**
  String get trayPause;

  /// No description provided for @trayResume.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get trayResume;

  /// No description provided for @trayOpen.
  ///
  /// In ru, this message translates to:
  /// **'Открыть окно'**
  String get trayOpen;

  /// No description provided for @trayQuit.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть значок'**
  String get trayQuit;

  /// No description provided for @backgroundTitle.
  ///
  /// In ru, this message translates to:
  /// **'Фоновая работа'**
  String get backgroundTitle;

  /// No description provided for @backgroundExplain.
  ///
  /// In ru, this message translates to:
  /// **'Бэкап по расписанию и хранитель работают в фоне и после закрытия окна: это службы системы, они запускаются при входе в систему.'**
  String get backgroundExplain;

  /// No description provided for @backgroundService.
  ///
  /// In ru, this message translates to:
  /// **'Служба агента бэкапа'**
  String get backgroundService;

  /// No description provided for @serviceRunning.
  ///
  /// In ru, this message translates to:
  /// **'работает'**
  String get serviceRunning;

  /// No description provided for @serviceStopped.
  ///
  /// In ru, this message translates to:
  /// **'остановлена'**
  String get serviceStopped;

  /// No description provided for @serviceNotInstalled.
  ///
  /// In ru, this message translates to:
  /// **'не установлена'**
  String get serviceNotInstalled;

  /// No description provided for @serviceInstall.
  ///
  /// In ru, this message translates to:
  /// **'Установить службу'**
  String get serviceInstall;

  /// No description provided for @serviceRemove.
  ///
  /// In ru, this message translates to:
  /// **'Удалить службу'**
  String get serviceRemove;

  /// No description provided for @serviceRemoveConfirm.
  ///
  /// In ru, this message translates to:
  /// **'Без службы бэкап по расписанию не будет идти, пока агент не запущен вручную. Удалить службу?'**
  String get serviceRemoveConfirm;

  /// No description provided for @backgroundUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Службы системы недоступны или программа агента не найдена: агента бэкапа нужно запускать вручную.'**
  String get backgroundUnavailable;

  /// No description provided for @trayAtLogin.
  ///
  /// In ru, this message translates to:
  /// **'Значок в трее при входе в систему'**
  String get trayAtLogin;

  /// No description provided for @trayUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Значок в трее недоступен в этой среде (в GNOME нужно расширение AppIndicator). Бэкап всё равно идёт в фоне.'**
  String get trayUnavailable;

  /// No description provided for @keeperLingerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Хранитель без входа в систему'**
  String get keeperLingerTitle;

  /// No description provided for @keeperLingerOff.
  ///
  /// In ru, this message translates to:
  /// **'Сейчас хранитель работает, только пока вы вошли в систему. Чтобы он был доступен и после перезагрузки без входа, выполните в терминале команду (нужны права администратора):'**
  String get keeperLingerOff;

  /// No description provided for @copy.
  ///
  /// In ru, this message translates to:
  /// **'Копировать'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In ru, this message translates to:
  /// **'Скопировано'**
  String get copied;

  /// No description provided for @updateTitle.
  ///
  /// In ru, this message translates to:
  /// **'Обновления'**
  String get updateTitle;

  /// No description provided for @autoUpdate.
  ///
  /// In ru, this message translates to:
  /// **'Проверять обновления автоматически'**
  String get autoUpdate;

  /// No description provided for @betaChannel.
  ///
  /// In ru, this message translates to:
  /// **'Бета-канал обновлений'**
  String get betaChannel;

  /// No description provided for @crashReports.
  ///
  /// In ru, this message translates to:
  /// **'Отправлять отчёты о сбоях'**
  String get crashReports;

  /// No description provided for @crashReportsExplain.
  ///
  /// In ru, this message translates to:
  /// **'Отчёт содержит только версию, тип ошибки и очищенный от путей и ключей текст. Он помогает исправлять сбои и не содержит ваши файлы, ключи и пароли.'**
  String get crashReportsExplain;
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
