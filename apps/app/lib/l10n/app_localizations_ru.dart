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

  @override
  String welcomeTitle(String app) {
    return 'Добро пожаловать в $app';
  }

  @override
  String get welcomeBody =>
      'Бэкап шифруется на этом компьютере и хранится частями у других участников. Ни они, ни сервер не видят ни содержимого, ни имён файлов.';

  @override
  String get welcomeCreate => 'Создать учётную запись';

  @override
  String get welcomeCreateHint =>
      'Первый компьютер: пароль и фраза восстановления.';

  @override
  String get welcomeLogin => 'Войти по паролю';

  @override
  String get welcomeLoginHint =>
      'Учётная запись уже есть — подключить этот компьютер.';

  @override
  String get welcomeRecover => 'Восстановить по фразе';

  @override
  String get welcomeRecoverHint =>
      'Пароль забыт или вход по паролю выключен — 24 слова.';

  @override
  String get serverSection => 'Сервер';

  @override
  String get serverAddress => 'Адрес сервера';

  @override
  String get serverAddressHint =>
      'Координатор учётных записей. Пусто — без сервера: данные в папках на этом компьютере, только для проверки.';

  @override
  String get serverNone => 'Без сервера';

  @override
  String get localModeHint =>
      'Учётная запись без сервера: фрагменты бэкапа — в папках на этом компьютере. Такой режим годится только для проверки.';

  @override
  String stepOf(int step, int total) {
    return 'Шаг $step из $total';
  }

  @override
  String get createTitle => 'Имя и вход на других компьютерах';

  @override
  String get loginName => 'Имя для входа';

  @override
  String get loginNameHint =>
      '3–32 символа: латинские буквы, цифры, точка, «_» и «-».';

  @override
  String get loginNameInvalid => 'Недопустимое имя';

  @override
  String get keyCopyQuestion => 'Как входить на новом компьютере?';

  @override
  String get keyCopyOn => 'По паролю или по фразе';

  @override
  String get keyCopyOnHint =>
      'Сервер хранит копию ключа, зашифрованную вашим паролем. Удобно, но стойкость данных зависит от стойкости пароля.';

  @override
  String get keyCopyOff => 'Только по фразе восстановления';

  @override
  String get keyCopyOffHint =>
      'На сервере нет даже зашифрованной копии ключа. Новый компьютер подключается только фразой из 24 слов.';

  @override
  String get keyCopyOffWarningTitle => 'Фраза станет единственным ключом';

  @override
  String get keyCopyOffWarning =>
      'Если потерять фразу и все компьютеры с учётной записью, данные не вернуть никак: ни пароль, ни мы не помогут.';

  @override
  String get createPasswordTitle => 'Пароль';

  @override
  String get createPasswordBody =>
      'Пароль открывает ключи на этом компьютере и, если вы выбрали вход по паролю, — копию ключа на сервере.';

  @override
  String get newPassword => 'Новый пароль';

  @override
  String get repeatPassword => 'Повторите пароль';

  @override
  String get currentPassword => 'Текущий пароль';

  @override
  String get passwordsDiffer => 'Пароли не совпадают';

  @override
  String passwordAdvice(int min) {
    return 'Не короче $min символов. Лучше всего — 4–5 случайных слов.';
  }

  @override
  String passwordStrength(String rating) {
    return 'Стойкость: $rating';
  }

  @override
  String get passwordRejected => 'слабый';

  @override
  String get passwordWeak => 'средний';

  @override
  String get passwordStrong => 'стойкий';

  @override
  String passwordTooShort(int min) {
    return 'Короче $min символов';
  }

  @override
  String get passwordForbiddenCharacter =>
      'Есть управляющий или неизвестный символ';

  @override
  String get passwordTooGuessable => 'Подбирается слишком быстро';

  @override
  String get acceptWeakPassword => 'Понимаю риск, оставить этот пароль';

  @override
  String get hintCommonPassword => 'Это один из частых паролей';

  @override
  String get hintDictionaryWord => 'Словарные слова подбираются первыми';

  @override
  String get hintName => 'Имена и фамилии подбираются первыми';

  @override
  String get hintPersonalInfo => 'В пароле сведения об учётной записи';

  @override
  String get hintOtherLayout =>
      'Слово в другой раскладке не сложнее самого слова';

  @override
  String get hintSubstitution =>
      'Замены вроде @ вместо a почти не усложняют подбор';

  @override
  String get hintReversed => 'Слово задом наперёд не сложнее самого слова';

  @override
  String get hintKeyboardPattern =>
      'Соседние клавиши (qwerty, 1qaz) подбираются первыми';

  @override
  String get hintRepeat => 'Повторы почти не добавляют стойкости';

  @override
  String get hintSequence => 'Последовательности (abc, 123) предсказуемы';

  @override
  String get hintDate => 'Даты и годы предсказуемы';

  @override
  String get phraseTitle => 'Фраза восстановления';

  @override
  String get phraseBody =>
      'Эти 24 слова — единственный способ вернуть данные, если пароль забыт или компьютер потерян. Запишите их по порядку.';

  @override
  String get phraseTipsTitle => 'Как хранить фразу';

  @override
  String get phraseTips =>
      'Запишите на бумаге и храните отдельно от компьютера, лучше в двух местах. Не фотографируйте, не храните в облаке, почте и мессенджерах. Никому не сообщайте — мы её никогда не спросим.';

  @override
  String get phraseWritten => 'Фраза записана';

  @override
  String get phraseExpired =>
      'Фраза устарела (агент бэкапа перезапускался). Запишите новую.';

  @override
  String get checkTitle => 'Проверка фразы';

  @override
  String get checkBody =>
      'Введите слова с указанными номерами — так мы убедимся, что фраза записана верно.';

  @override
  String wordNumber(int number) {
    return 'Слово №$number';
  }

  @override
  String get wordWrong => 'Не то слово';

  @override
  String get createAccount => 'Создать учётную запись';

  @override
  String get createdTitle => 'Учётная запись создана';

  @override
  String get createdBody =>
      'Ключи сохранены в хранилище ключей системы — бэкап по расписанию пойдёт без пароля.';

  @override
  String get toBackup => 'Перейти к бэкапу';

  @override
  String get next => 'Далее';

  @override
  String get later => 'Позже';

  @override
  String get onboardKeeperTitle => 'Станьте хранителем';

  @override
  String get onboardKeeperBody =>
      'Backpeer хранит бэкапы на компьютерах участников. Отдайте часть свободного места на этом компьютере: выберите папку и сколько отдать — остальное хранитель сделает сам, в фоне.';

  @override
  String get onboardKeeperLater =>
      'Можно и позже — в разделе «Хранитель». Папки для бэкапа выбираются следующим шагом, в разделе «Бэкап».';

  @override
  String get back => 'Назад';

  @override
  String get done => 'Готово';

  @override
  String get close => 'Закрыть';

  @override
  String get loginBody =>
      'Нужны имя и пароль учётной записи. Если вход по паролю выключен, восстановите доступ по фразе.';

  @override
  String get signIn => 'Войти';

  @override
  String get signingIn => 'Открываем ключи и загружаем список данных…';

  @override
  String get recoverBody =>
      'Введите 24 слова фразы восстановления через пробел.';

  @override
  String get phraseField => 'Фраза восстановления';

  @override
  String phraseFieldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count слова из 24',
      many: '$count слов из 24',
      few: '$count слова из 24',
      one: '$count слово из 24',
    );
    return '$_temp0';
  }

  @override
  String get recoverPasswordBody => 'Придумайте пароль для этого компьютера.';

  @override
  String get recover => 'Восстановить';

  @override
  String get signedInTitle => 'Компьютер подключён';

  @override
  String get indexNotRestored => 'Список данных загрузится позже';

  @override
  String get latestSnapshot => 'Последний снимок';

  @override
  String snapshotFrom(String date, String host) {
    return '$date, компьютер $host';
  }

  @override
  String snapshotsTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Всего $count снимка',
      many: 'Всего $count снимков',
      few: 'Всего $count снимка',
      one: 'Всего $count снимок',
    );
    return '$_temp0';
  }

  @override
  String get rollbackCheckTitle => 'Сверьте последний снимок';

  @override
  String get rollbackCheck =>
      'Этот компьютер новый и не может сам проверить, что сервер показал все снимки. Убедитесь, что последний снимок — тот, что вы ожидаете: дата и компьютер. Если более нового снимка нет, хотя он был, не удаляйте данные на других компьютерах и сообщите нам.';

  @override
  String get rollbackWarningTitle => 'Похоже, сервер показал не все снимки';

  @override
  String get rollbackWarning =>
      'Список снимков не сходится с тем, что известно этому компьютеру: возможен откат. Не удаляйте данные на других компьютерах и сообщите нам.';

  @override
  String get restoreAllTitle => 'Восстановить данные';

  @override
  String get restoreAllBody =>
      'Файлы последнего снимка будут восстановлены в эту папку. Ход восстановления — на экране «Обзор».';

  @override
  String get restoreTarget => 'Папка для восстановления';

  @override
  String get restoredFolder => 'Восстановлено';

  @override
  String get restoreAll => 'Восстановить всё';

  @override
  String get restoreLater => 'Позже';

  @override
  String get accountSection => 'Учётная запись';

  @override
  String get thisDevice => 'Это устройство';

  @override
  String get newDeviceSignIn => 'Новое устройство';

  @override
  String get signInByPasswordOrPhrase => 'по паролю или по фразе';

  @override
  String get signInByPhraseOnly => 'только по фразе';

  @override
  String get unknown => 'неизвестно';

  @override
  String get changePassword => 'Сменить пароль';

  @override
  String get passwordChanged => 'Пароль изменён.';

  @override
  String get passwordChangedEverywhere =>
      'Пароль изменён здесь и в копии ключа на сервере.';

  @override
  String get passwordChangedKeyCopyUnknown =>
      'Пароль изменён здесь. Неизвестно, есть ли на сервере копия ключа под старым паролем, — включите или выключите копию ключа заново.';

  @override
  String get showPhrase => 'Показать фразу';

  @override
  String get showPhraseBody =>
      'Фраза восстановления даёт полный доступ к данным. Убедитесь, что экран никто не видит.';

  @override
  String get show => 'Показать';

  @override
  String get keyCopySwitch => 'Копия ключа на сервере (вход по паролю)';

  @override
  String get keyCopyEnableTitle => 'Включить вход по паролю';

  @override
  String get keyCopyDisableTitle => 'Выключить вход по паролю';

  @override
  String get enable => 'Включить';

  @override
  String get disable => 'Выключить';

  @override
  String get devicesSection => 'Устройства';

  @override
  String deviceCurrent(String id) {
    return '$id — это устройство';
  }

  @override
  String deviceAddedAt(String date) {
    return 'добавлено $date';
  }

  @override
  String deviceRevokedAt(String date) {
    return 'отозвано $date';
  }

  @override
  String get revoke => 'Отозвать';

  @override
  String get revokeTitle => 'Отозвать устройство?';

  @override
  String revokeBody(String id) {
    return 'Устройство $id сразу потеряет доступ к учётной записи и данным на сервере. Вернуть его можно только заново — по паролю или фразе.';
  }

  @override
  String get revoked => 'Устройство отозвано — доступ закрыт.';

  @override
  String get errorWeakPassword => 'Пароль слишком простой';

  @override
  String get errorPhraseNotConfirmed => 'Слова фразы не совпадают';

  @override
  String get errorBadPhrase =>
      'Фраза введена с ошибкой: проверьте слова и их порядок';

  @override
  String get errorLoginTaken => 'Это имя занято, выберите другое';

  @override
  String get errorUnauthenticated =>
      'Неверное имя или пароль, либо вход по паролю выключен — тогда восстановите доступ по фразе';

  @override
  String get errorTooManyDevices =>
      'У учётной записи уже 5 устройств: отзовите ненужное на другом устройстве';

  @override
  String get errorCurrentDevice =>
      'Это устройство нельзя отозвать с него самого';

  @override
  String get errorNoPhrase =>
      'На этом устройстве нет копии фразы: оно подключено по паролю';

  @override
  String get errorRateLimited => 'Слишком много попыток, попробуйте позже';

  @override
  String get errorUnavailable =>
      'Сервер недоступен, проверьте подключение к интернету';

  @override
  String get errorExists => 'На этом устройстве уже есть учётная запись';

  @override
  String get agentStatusWaitingForPower => 'Ждёт питания от сети';

  @override
  String get healthTitle => 'Здоровье данных';

  @override
  String get healthOk => 'Всё в порядке';

  @override
  String get healthOkHint => 'Бэкап свежий, проверка не нашла проблем.';

  @override
  String get healthRepairing => 'Ремонтируется';

  @override
  String get healthRepairingHint =>
      'Часть хранителей ушла, сеть восстанавливает фрагменты. Данные целы.';

  @override
  String get healthAttention => 'Требует внимания';

  @override
  String get healthUnknown => 'Бэкапа ещё не было';

  @override
  String get healthUnknownHint =>
      'Выберите папки в разделе «Бэкап» — первый бэкап начнётся сам.';

  @override
  String get healthReasonBackupFailed => 'Последний бэкап не удался';

  @override
  String get healthReasonBackupStale =>
      'Бэкап давно не делался: компьютер был выключен или бэкап не проходит';

  @override
  String get healthReasonRollbackWarning =>
      'Сервер показал не все снимки — список мог быть подменён';

  @override
  String get healthReasonUnrecoverable => 'Часть данных нельзя восстановить';

  @override
  String get healthReasonAtRisk => 'У части данных почти не осталось запаса';

  @override
  String get healthReasonFragmentsMissing =>
      'Часть фрагментов недоступна, запас есть';

  @override
  String get healthReasonVerifyFailed => 'Проверка не удалась';

  @override
  String get healthReasonNeverVerified => 'Бэкап ещё не проверялся';

  @override
  String get lastVerify => 'Последняя проверка';

  @override
  String get verifyNow => 'Проверить сейчас';

  @override
  String progressOf(String done, String total) {
    return '$done из $total';
  }

  @override
  String progressSpeed(String size) {
    return '$size/с';
  }

  @override
  String progressEta(String time) {
    return 'осталось около $time';
  }

  @override
  String durationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count минуты',
      many: '$count минут',
      few: '$count минут',
      one: '$count минуты',
    );
    return '$_temp0';
  }

  @override
  String durationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count часа',
      many: '$count часов',
      few: '$count часов',
      one: '$count часа',
    );
    return '$_temp0';
  }

  @override
  String get lessThanMinute => 'минуты';

  @override
  String get resumedNote => 'Продолжение прерванного бэкапа';

  @override
  String get estimating => 'Считаем объём…';

  @override
  String get currentBackup => 'Текущий бэкап';

  @override
  String get addFolder => 'Добавить папку';

  @override
  String get removeFolder => 'Убрать из бэкапа';

  @override
  String get folderPickerFailed => 'Не удалось открыть выбор папки';

  @override
  String get excludes => 'Исключения';

  @override
  String get presetTemporary => 'Временные файлы';

  @override
  String get presetCaches => 'Кеши программ';

  @override
  String get presetTrash => 'Корзина';

  @override
  String get presetDevelopment => 'Зависимости и сборка программ';

  @override
  String get customRules => 'Свои правила';

  @override
  String get addRule => 'Добавить правило';

  @override
  String get ruleHint => 'Например: *.iso или Видео/';

  @override
  String get removeRule => 'Убрать правило';

  @override
  String get estimate => 'Оценить объём';

  @override
  String get estimateHint =>
      'Посмотрите, сколько займёт бэкап, до его запуска.';

  @override
  String estimateResult(String files, String size) {
    return '$files, $size';
  }

  @override
  String estimateExcluded(int count) {
    return 'Исключено правилами: $count';
  }

  @override
  String estimateSkipped(int count) {
    return 'Нет доступа или особые файлы: $count';
  }

  @override
  String get estimateTruncated =>
      'Файлов очень много — подсчитана только часть.';

  @override
  String get estimateNetwork =>
      'В сети займёт больше — с запасом на надёжность; одинаковые данные хранятся один раз.';

  @override
  String get frequency => 'Как часто';

  @override
  String get frequencyHourly => 'раз в час';

  @override
  String get frequencyDaily => 'раз в день';

  @override
  String get frequencyWeekly => 'раз в неделю';

  @override
  String get onlyHours => 'Только в заданные часы';

  @override
  String get hoursFrom => 'С';

  @override
  String get hoursTo => 'До';

  @override
  String hourValue(int hour) {
    return '$hour:00';
  }

  @override
  String get onlyOnAc => 'Только от сети';

  @override
  String get onlyOnAcHint =>
      'От батареи бэкап по расписанию подождёт, а начатый — остановится и продолжится от сети.';

  @override
  String get verifySchedule => 'Проверка бэкапа';

  @override
  String get scheduleNote =>
      'Бэкап по расписанию делает фоновый агент — окно можно закрыть.';

  @override
  String get retention => 'Хранение снимков';

  @override
  String get keepAll => 'Хранить все снимки';

  @override
  String get keepLast => 'Последних';

  @override
  String get keepHourly => 'Почасовых';

  @override
  String get keepDaily => 'Дневных';

  @override
  String get keepWeekly => 'Недельных';

  @override
  String get keepMonthly => 'Месячных';

  @override
  String get retentionHint =>
      'В каждом часе, дне, неделе и месяце остаётся самый новый снимок. Лишние агент удаляет после бэкапа и освобождает место. Снимки других компьютеров не трогаются.';

  @override
  String get retentionInvalid => 'Целое число от 0; последних — хотя бы 1';

  @override
  String get save => 'Сохранить';

  @override
  String get saved => 'Сохранено';

  @override
  String get history => 'История';

  @override
  String get noHistory => 'Заданий ещё не было';

  @override
  String get triggerSchedule => 'по расписанию';

  @override
  String get triggerManual => 'вручную';

  @override
  String get triggerResume => 'продолжение';

  @override
  String get historyContinues => 'продолжится с того же места';

  @override
  String get reasonPaused => 'пауза';

  @override
  String get reasonOnBattery => 'переход на батарею';

  @override
  String newData(String size) {
    return 'новых данных $size';
  }

  @override
  String skippedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'пропущено $count файла',
      many: 'пропущено $count файлов',
      few: 'пропущено $count файла',
      one: 'пропущен $count файл',
    );
    return '$_temp0';
  }

  @override
  String get details => 'Подробности';

  @override
  String get skippedTitle => 'Пропущенные файлы';

  @override
  String get skippedExplain =>
      'Эти файлы не попали в снимок. Чаще всего это файлы без права чтения или изменившиеся во время чтения — следующий бэкап попробует снова.';

  @override
  String get skipReasonError => 'нет доступа или ошибка чтения';

  @override
  String get skipReasonSpecial =>
      'особый файл (сокет, устройство) — такие не сохраняются';

  @override
  String retentionResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'удалено $count старых снимка',
      many: 'удалено $count старых снимков',
      few: 'удалено $count старых снимка',
      one: 'удалён $count старый снимок',
    );
    return '$_temp0';
  }

  @override
  String freed(String size) {
    return 'освобождено $size';
  }

  @override
  String verifyResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'проверено $count сегмента',
      many: 'проверено $count сегментов',
      few: 'проверено $count сегмента',
      one: 'проверен $count сегмент',
    );
    return '$_temp0';
  }

  @override
  String errorText(String message) {
    return 'Ошибка: $message';
  }

  @override
  String get snapshotsOnRestore =>
      'Список снимков — в разделе «Восстановление».';

  @override
  String get restoreOpenSnapshot => 'Открыть снимок';

  @override
  String get browserBack => 'К списку снимков';

  @override
  String get browserRoot => 'Снимок';

  @override
  String get searchHint => 'Поиск по имени: часть имени или шаблон вроде *.pdf';

  @override
  String get searchClear => 'Сбросить поиск';

  @override
  String searchResults(int count) {
    return 'Найдено: $count';
  }

  @override
  String searchTruncated(int count) {
    return 'Показаны первые $count. Уточните запрос.';
  }

  @override
  String get searchNothing => 'Ничего не найдено';

  @override
  String get folderEmpty => 'Папка пуста';

  @override
  String get loadingItem => 'Загрузка…';

  @override
  String selectedCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get restoreSelected => 'Восстановить выбранное';

  @override
  String get clearSelection => 'Снять выделение';

  @override
  String get fileVersions => 'Версии файла';

  @override
  String versionsTitle(String name) {
    return 'Версии «$name»';
  }

  @override
  String get versionChanged => 'изменён';

  @override
  String get versionSame => 'без изменений';

  @override
  String get versionAbsent => 'нет в этом снимке';

  @override
  String get restoreThisVersion => 'Восстановить';

  @override
  String get chooseFolder => 'Выбрать папку';

  @override
  String restoreWhat(String what) {
    return 'Что: $what';
  }

  @override
  String get restoreWholeSnapshot => 'весь снимок';

  @override
  String get restoreWhere => 'Куда';

  @override
  String get restoreOriginal => 'На исходное место';

  @override
  String get restoreOriginalHint =>
      'Файлы вернутся туда, откуда были сохранены.';

  @override
  String get restoreToFolder => 'В другую папку';

  @override
  String get restoreExisting => 'Если такой файл уже есть';

  @override
  String get existingKeepBoth =>
      'Сохранить оба: к имени восстановленного добавится «(восстановлено)»';

  @override
  String get existingSkip =>
      'Оставить существующий, восстановленный не записывать';

  @override
  String get existingOverwrite => 'Заменить существующий восстановленным';

  @override
  String get restoredSuffix => 'восстановлено';

  @override
  String get restoreWait => 'Если часть хранителей не в сети';

  @override
  String get waitNone => 'Не ждать — восстановить то, что доступно';

  @override
  String get waitHour => 'Ждать до часа';

  @override
  String get waitDay => 'Ждать до суток';

  @override
  String get restoreStart => 'Восстановить';

  @override
  String get restoreStarted =>
      'Восстановление началось. Ход — здесь и на «Обзоре».';

  @override
  String get restoreCurrent => 'Текущее восстановление';

  @override
  String waitingTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файла ждут хранителей',
      many: '$count файлов ждут хранителей',
      few: '$count файла ждут хранителей',
      one: '$count файл ждёт хранителей',
    );
    return '$_temp0';
  }

  @override
  String get waitingExplain =>
      'Части этих файлов лежат у хранителей, которые сейчас не в сети: доступных фрагментов меньше, чем нужно для сборки. Остальное уже восстанавливается, а эти файлы докачаются, когда хранители появятся.';

  @override
  String andMore(int count) {
    return 'и ещё $count';
  }

  @override
  String waitingRetry(String time) {
    return 'Следующая попытка — в течение $time';
  }

  @override
  String waitingLeft(String time) {
    return 'Ждём ещё не дольше $time';
  }

  @override
  String waitingReason(String reason) {
    return 'Подробности: $reason';
  }

  @override
  String get lastRestore => 'Последнее восстановление';

  @override
  String get restoreWhen => 'Когда';

  @override
  String get restoreProblem => 'Ошибка';

  @override
  String get restoreWhereLabel => 'Куда';

  @override
  String get restoreRestored => 'Восстановлено';

  @override
  String get restoreSkippedLabel => 'Не тронуто существующих';

  @override
  String get restoreRenamedLabel => 'Сохранено рядом с существующими';

  @override
  String get restoreErrorsLabel => 'Не восстановлено';

  @override
  String get speedUnlimited => 'без предела';

  @override
  String speedValue(String size) {
    return '$size/с';
  }

  @override
  String get keeperEnableTitle => 'Отдать место';

  @override
  String get keeperEditTitle => 'Настройки хранителя';

  @override
  String get keeperPrivacy =>
      'Фрагменты шифруются на компьютере владельца ещё до отправки. Хранитель не может их прочитать и не знает, чьи это файлы и как они называются.';

  @override
  String get keeperFolder => 'Папка для фрагментов';

  @override
  String keeperFree(String size) {
    return 'Свободно на диске: $size';
  }

  @override
  String get keeperQuotaLabel => 'Сколько места отдать, ГБ';

  @override
  String get keeperQuotaInvalid => 'Введите число гигабайт';

  @override
  String get keeperQuotaTooBig => 'Больше, чем свободно на диске';

  @override
  String get keeperQuotaMin => 'Сервер обычно принимает хранителей от 100 ГБ';

  @override
  String get keeperUpload => 'Отдача';

  @override
  String get keeperDownload => 'Приём';

  @override
  String get keeperWorkHours => 'В рабочие часы (пн–пт, 9–18)';

  @override
  String get keeperBackgroundNote =>
      'Хранитель работает в фоне и без открытого окна.';

  @override
  String get keeperEnable => 'Стать хранителем';

  @override
  String get keeperEnabled => 'Роль хранителя включена';

  @override
  String get keeperNoBinary =>
      'Настройки сохранены, но программа хранителя не найдена рядом с приложением. Запустите службу хранителя вручную.';

  @override
  String get keeperNoCoordinator =>
      'Учётная запись без сервера: хранителю негде зарегистрироваться.';

  @override
  String get keeperNotRunning =>
      'Роль включена, но служба хранителя не запущена.';

  @override
  String get keeperStart => 'Запустить';

  @override
  String get keeperStats => 'Статистика';

  @override
  String get keeperFreeQuota => 'Свободно из отданного';

  @override
  String get keeperDisk => 'Свободно на диске';

  @override
  String get keeperTraffic => 'Трафик с запуска';

  @override
  String keeperTrafficValue(String sent, String received) {
    return 'отдано $sent, принято $received';
  }

  @override
  String get keeperUdp => 'по UDP после сведения';

  @override
  String get keeperRelay => 'через relay';

  @override
  String get keeperNoIncoming => 'входящих соединений нет';

  @override
  String keeperPortHint(int port) {
    return 'Чтобы к этому компьютеру подключались напрямую и быстрее, откройте на роутере порт $port (TCP и UDP) или включите на нём UPnP.';
  }

  @override
  String keeperPortMappingError(String error) {
    return 'Автоматически открыть порт не получилось: $error';
  }

  @override
  String get keeperCoordinator => 'Как вас видит сервер';

  @override
  String get keeperNoCoordinatorShort => 'сервер не задан';

  @override
  String get keeperRegistered => 'зарегистрирован';

  @override
  String keeperNotRegistered(String error) {
    return 'не зарегистрирован: $error';
  }

  @override
  String get keeperWaitingCoordinator => 'ждём ответа сервера';

  @override
  String get keeperAvailability => 'Доступность за 30 дней';

  @override
  String get keeperReputation => 'Репутация';

  @override
  String keeperProbation(String date) {
    return 'испытательный срок до $date';
  }

  @override
  String get keeperAudits => 'Проверки хранения';

  @override
  String keeperAuditsValue(int passed, int failed) {
    return 'пройдено $passed, провалено $failed';
  }

  @override
  String get keeperExcluded =>
      'Сервер исключил этого хранителя: новых фрагментов не будет.';

  @override
  String get keeperStandingSoon =>
      'Сведения появятся после следующей связи с сервером.';

  @override
  String get keeperBarter => 'Баланс';

  @override
  String get keeperBarterSoon =>
      'Здесь появится баланс бартера: сколько места вы отдали и сколько можете хранить сами.';

  @override
  String get keeperRole => 'Роль хранителя';

  @override
  String get keeperChange => 'Изменить';

  @override
  String get keeperStop => 'Выключить хранителя';

  @override
  String get keeperStopConfirm =>
      'Хранитель остановится, фрагменты останутся на диске. Если он долго не вернётся, сервер восстановит эти фрагменты у других хранителей. Включить снова можно в любой момент.';

  @override
  String get keeperLeave => 'Выйти из роли';

  @override
  String get keeperLeaveSoon =>
      'Выход с переносом фрагментов к другим хранителям и освобождением места появится в следующих версиях. Пока хранителя можно выключить.';

  @override
  String get trayBackupNow => 'Сделать бэкап сейчас';

  @override
  String get trayPause => 'Приостановить';

  @override
  String get trayResume => 'Продолжить';

  @override
  String get trayOpen => 'Открыть окно';

  @override
  String get trayQuit => 'Закрыть значок';

  @override
  String get backgroundTitle => 'Фоновая работа';

  @override
  String get backgroundExplain =>
      'Бэкап по расписанию и хранитель работают в фоне и после закрытия окна: это службы системы, они запускаются при входе в систему.';

  @override
  String get backgroundService => 'Служба агента бэкапа';

  @override
  String get serviceRunning => 'работает';

  @override
  String get serviceStopped => 'остановлена';

  @override
  String get serviceNotInstalled => 'не установлена';

  @override
  String get serviceInstall => 'Установить службу';

  @override
  String get serviceRemove => 'Удалить службу';

  @override
  String get serviceRemoveConfirm =>
      'Без службы бэкап по расписанию не будет идти, пока агент не запущен вручную. Удалить службу?';

  @override
  String get backgroundUnavailable =>
      'Службы системы недоступны или программа агента не найдена: агента бэкапа нужно запускать вручную.';

  @override
  String get trayAtLogin => 'Значок в трее при входе в систему';

  @override
  String get trayUnavailable =>
      'Значок в трее недоступен в этой среде (в GNOME нужно расширение AppIndicator). Бэкап всё равно идёт в фоне.';

  @override
  String get keeperLingerTitle => 'Хранитель без входа в систему';

  @override
  String get keeperLingerOff =>
      'Сейчас хранитель работает, только пока вы вошли в систему. Чтобы он был доступен и после перезагрузки без входа, выполните в терминале команду (нужны права администратора):';

  @override
  String get copy => 'Копировать';

  @override
  String get copied => 'Скопировано';

  @override
  String get updateTitle => 'Обновления';

  @override
  String get autoUpdate => 'Проверять обновления автоматически';

  @override
  String get betaChannel => 'Бета-канал обновлений';

  @override
  String get crashReports => 'Отправлять отчёты о сбоях';

  @override
  String get crashReportsExplain =>
      'Отчёт содержит только версию, тип ошибки и очищенный от путей и ключей текст. Он помогает исправлять сбои и не содержит ваши файлы, ключи и пароли.';
}
