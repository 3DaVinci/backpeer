// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Backpeer';

  @override
  String get navOverview => 'Overview';

  @override
  String get navBackup => 'Backup';

  @override
  String get navRestore => 'Restore';

  @override
  String get navKeeper => 'Keeper';

  @override
  String get navSettings => 'Settings';

  @override
  String get processAgent => 'Backup agent';

  @override
  String get processNode => 'Keeper service';

  @override
  String linkConnecting(String process) {
    return '$process: connecting…';
  }

  @override
  String linkUnavailable(String process) {
    return '$process is not running';
  }

  @override
  String get linkUnavailableHint =>
      'The app will reconnect as soon as the service starts. No data is lost.';

  @override
  String get agentStatusIdle => 'Waiting for schedule';

  @override
  String get agentStatusWorking => 'Working';

  @override
  String get agentStatusPaused => 'Paused';

  @override
  String get agentStatusWaitingForKeys => 'Password needed';

  @override
  String get agentStatusStopping => 'Stopping';

  @override
  String get jobBackup => 'Backup';

  @override
  String get jobVerify => 'Check';

  @override
  String get jobRestore => 'Restore';

  @override
  String get outcomeOk => 'completed';

  @override
  String get outcomePartial => 'completed with warnings';

  @override
  String get outcomeFailed => 'failed';

  @override
  String get outcomeCancelled => 'stopped';

  @override
  String get lastBackup => 'Last backup';

  @override
  String get nextBackup => 'Next backup';

  @override
  String get never => 'not yet';

  @override
  String get notScheduled => 'not scheduled';

  @override
  String get now => 'now';

  @override
  String get backupNow => 'Back up now';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get interruptedNote =>
      'The previous backup did not finish — it will continue where it stopped.';

  @override
  String get notConfigured => 'There is no account on this device yet.';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '$count file',
    );
    return '$_temp0';
  }

  @override
  String jobProgress(String files, String bytes) {
    return '$files, $bytes read';
  }

  @override
  String get keysRequired => 'Backup is waiting for your password';

  @override
  String get keysRequiredHint =>
      'The system keyring is locked or unavailable. Enter your password so the backup can continue.';

  @override
  String get enterPassword => 'Enter password';

  @override
  String get unlockTitle => 'Password for background work';

  @override
  String get unlockBody =>
      'The backup agent will unlock your keys and keep them in the system keyring, so you won\'t need the password after a restart.';

  @override
  String get password => 'Password';

  @override
  String get rememberKeys => 'Remember in the system keyring';

  @override
  String get unlock => 'Unlock';

  @override
  String get cancel => 'Cancel';

  @override
  String get wrongPassword => 'Wrong password';

  @override
  String get notRemembered =>
      'Could not save the key in the system — the password will be needed after a restart.';

  @override
  String get backupFolders => 'Folders to back up';

  @override
  String get noFolders => 'No folders selected yet';

  @override
  String get schedule => 'Schedule';

  @override
  String everyMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'every $minutes minutes',
      one: 'every minute',
    );
    return '$_temp0';
  }

  @override
  String get manualOnly => 'manual only';

  @override
  String get comingSoon => 'Editing comes in the next app version';

  @override
  String get snapshots => 'Snapshots';

  @override
  String get noSnapshots => 'No snapshots yet';

  @override
  String get refresh => 'Refresh';

  @override
  String snapshotSummary(String files, String size) {
    return '$files · $size';
  }

  @override
  String get keeperExplain =>
      'A keeper gives space on this computer. It sees neither file contents nor names — only encrypted fragments.';

  @override
  String get keeperOff =>
      'The keeper role is off or the service is not running.';

  @override
  String get keeperUsed => 'Used';

  @override
  String get keeperQuota => 'Space given';

  @override
  String get keeperFragments => 'Fragments';

  @override
  String get keeperConnections => 'Connections';

  @override
  String get keeperReachability => 'Connection';

  @override
  String get keeperDirect => 'direct';

  @override
  String get keeperIndirect => 'via UDP or relay';

  @override
  String get keeperUnknown => 'checking';

  @override
  String get keeperState => 'State';

  @override
  String get nodeRunning => 'running';

  @override
  String get nodePaused => 'paused';

  @override
  String get nodeStopping => 'stopping';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System default';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get about => 'About';

  @override
  String version(String version) {
    return 'Version $version';
  }

  @override
  String failed(String message) {
    return 'Something went wrong: $message';
  }

  @override
  String sizeBytes(String value) {
    return '$value B';
  }

  @override
  String sizeKiB(String value) {
    return '$value KiB';
  }

  @override
  String sizeMiB(String value) {
    return '$value MiB';
  }

  @override
  String sizeGiB(String value) {
    return '$value GiB';
  }

  @override
  String sizeTiB(String value) {
    return '$value TiB';
  }
}
