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
      'Ключи сохранены в хранилище ключей системы — бэкап по расписанию пойдёт без пароля. Осталось выбрать папки для бэкапа.';

  @override
  String get toBackup => 'Перейти к бэкапу';

  @override
  String get next => 'Далее';

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
}
