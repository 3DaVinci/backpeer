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

  @override
  String welcomeTitle(String app) {
    return 'Welcome to $app';
  }

  @override
  String get welcomeBody =>
      'Your backup is encrypted on this computer and stored in pieces by other participants. Neither they nor the server can see file contents or names.';

  @override
  String get welcomeCreate => 'Create an account';

  @override
  String get welcomeCreateHint =>
      'First computer: a password and a recovery phrase.';

  @override
  String get welcomeLogin => 'Sign in with password';

  @override
  String get welcomeLoginHint =>
      'You already have an account — add this computer.';

  @override
  String get welcomeRecover => 'Recover with phrase';

  @override
  String get welcomeRecoverHint =>
      'Forgot the password or password sign-in is off — use the 24 words.';

  @override
  String get serverSection => 'Server';

  @override
  String get serverAddress => 'Server address';

  @override
  String get serverAddressHint =>
      'The account coordinator. Empty — no server: data stays in folders on this computer, for testing only.';

  @override
  String get serverNone => 'No server';

  @override
  String get localModeHint =>
      'Account without a server: backup fragments go to folders on this computer. Use this mode for testing only.';

  @override
  String stepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get createTitle => 'Name and sign-in on other computers';

  @override
  String get loginName => 'Sign-in name';

  @override
  String get loginNameHint =>
      '3–32 characters: Latin letters, digits, dot, “_” and “-”.';

  @override
  String get loginNameInvalid => 'Invalid name';

  @override
  String get keyCopyQuestion => 'How will you sign in on a new computer?';

  @override
  String get keyCopyOn => 'With password or phrase';

  @override
  String get keyCopyOnHint =>
      'The server keeps a copy of your key encrypted with your password. Convenient, but your data is only as strong as your password.';

  @override
  String get keyCopyOff => 'Recovery phrase only';

  @override
  String get keyCopyOffHint =>
      'The server holds no copy of your key, not even an encrypted one. A new computer can only be added with the 24-word phrase.';

  @override
  String get keyCopyOffWarningTitle => 'The phrase will be the only key';

  @override
  String get keyCopyOffWarning =>
      'If you lose the phrase and every computer with this account, the data is gone for good: neither the password nor we can help.';

  @override
  String get createPasswordTitle => 'Password';

  @override
  String get createPasswordBody =>
      'The password unlocks the keys on this computer and, if you chose password sign-in, the key copy on the server.';

  @override
  String get newPassword => 'New password';

  @override
  String get repeatPassword => 'Repeat password';

  @override
  String get currentPassword => 'Current password';

  @override
  String get passwordsDiffer => 'Passwords don\'t match';

  @override
  String passwordAdvice(int min) {
    return 'At least $min characters. Best: 4–5 random words.';
  }

  @override
  String passwordStrength(String rating) {
    return 'Strength: $rating';
  }

  @override
  String get passwordRejected => 'weak';

  @override
  String get passwordWeak => 'fair';

  @override
  String get passwordStrong => 'strong';

  @override
  String passwordTooShort(int min) {
    return 'Shorter than $min characters';
  }

  @override
  String get passwordForbiddenCharacter =>
      'Contains a control or unknown character';

  @override
  String get passwordTooGuessable => 'Too easy to guess';

  @override
  String get acceptWeakPassword => 'I understand the risk, keep this password';

  @override
  String get hintCommonPassword => 'This is a common password';

  @override
  String get hintDictionaryWord => 'Dictionary words are guessed first';

  @override
  String get hintName => 'Names and surnames are guessed first';

  @override
  String get hintPersonalInfo => 'The password contains account details';

  @override
  String get hintOtherLayout =>
      'A word typed in another keyboard layout is no harder than the word';

  @override
  String get hintSubstitution => 'Substitutions like @ for a barely help';

  @override
  String get hintReversed => 'A reversed word is no harder than the word';

  @override
  String get hintKeyboardPattern =>
      'Adjacent keys (qwerty, 1qaz) are guessed first';

  @override
  String get hintRepeat => 'Repeats add little strength';

  @override
  String get hintSequence => 'Sequences (abc, 123) are predictable';

  @override
  String get hintDate => 'Dates and years are predictable';

  @override
  String get phraseTitle => 'Recovery phrase';

  @override
  String get phraseBody =>
      'These 24 words are the only way to get your data back if you forget the password or lose the computer. Write them down in order.';

  @override
  String get phraseTipsTitle => 'How to keep the phrase';

  @override
  String get phraseTips =>
      'Write it on paper and keep it away from the computer, ideally in two places. Don\'t take photos or keep it in cloud storage, email or messengers. Never share it — we will never ask for it.';

  @override
  String get phraseWritten => 'I have written down the phrase';

  @override
  String get phraseExpired =>
      'The phrase has expired (the backup agent restarted). Write down the new one.';

  @override
  String get checkTitle => 'Check the phrase';

  @override
  String get checkBody =>
      'Enter the words with these numbers to make sure the phrase was written down correctly.';

  @override
  String wordNumber(int number) {
    return 'Word #$number';
  }

  @override
  String get wordWrong => 'Wrong word';

  @override
  String get createAccount => 'Create account';

  @override
  String get createdTitle => 'Account created';

  @override
  String get createdBody =>
      'The keys are saved in the system keychain, so scheduled backups run without the password.';

  @override
  String get toBackup => 'Go to backup';

  @override
  String get next => 'Next';

  @override
  String get later => 'Later';

  @override
  String get onboardKeeperTitle => 'Become a keeper';

  @override
  String get onboardKeeperBody =>
      'Backpeer stores backups on participants’ computers. Share some free space on this computer: choose a folder and how much to share — the keeper does the rest in the background.';

  @override
  String get onboardKeeperLater =>
      'You can also do it later on the Keeper screen. Folders to back up are chosen next, on the Backup screen.';

  @override
  String get back => 'Back';

  @override
  String get done => 'Done';

  @override
  String get close => 'Close';

  @override
  String get loginBody =>
      'Enter the account name and password. If password sign-in is off, recover access with the phrase.';

  @override
  String get signIn => 'Sign in';

  @override
  String get signingIn => 'Unlocking keys and loading the data list…';

  @override
  String get recoverBody =>
      'Enter the 24 words of the recovery phrase separated by spaces.';

  @override
  String get phraseField => 'Recovery phrase';

  @override
  String phraseFieldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words of 24',
      one: '$count word of 24',
    );
    return '$_temp0';
  }

  @override
  String get recoverPasswordBody => 'Choose a password for this computer.';

  @override
  String get recover => 'Recover';

  @override
  String get signedInTitle => 'Computer connected';

  @override
  String get indexNotRestored => 'The data list will load later';

  @override
  String get latestSnapshot => 'Latest snapshot';

  @override
  String snapshotFrom(String date, String host) {
    return '$date, computer $host';
  }

  @override
  String snapshotsTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snapshots in total',
      one: '$count snapshot in total',
    );
    return '$_temp0';
  }

  @override
  String get rollbackCheckTitle => 'Check the latest snapshot';

  @override
  String get rollbackCheck =>
      'This computer is new and cannot check by itself that the server showed every snapshot. Make sure the latest snapshot is the one you expect: date and computer. If a newer snapshot is missing, don\'t delete data on other computers and let us know.';

  @override
  String get rollbackWarningTitle => 'The server may be hiding snapshots';

  @override
  String get rollbackWarning =>
      'The snapshot list doesn\'t match what this computer knows: a rollback is possible. Don\'t delete data on other computers and let us know.';

  @override
  String get restoreAllTitle => 'Restore your data';

  @override
  String get restoreAllBody =>
      'Files from the latest snapshot will be restored to this folder. Progress is shown on the Overview screen.';

  @override
  String get restoreTarget => 'Restore to folder';

  @override
  String get restoredFolder => 'Restored';

  @override
  String get restoreAll => 'Restore everything';

  @override
  String get restoreLater => 'Later';

  @override
  String get accountSection => 'Account';

  @override
  String get thisDevice => 'This device';

  @override
  String get newDeviceSignIn => 'New device';

  @override
  String get signInByPasswordOrPhrase => 'with password or phrase';

  @override
  String get signInByPhraseOnly => 'phrase only';

  @override
  String get unknown => 'unknown';

  @override
  String get changePassword => 'Change password';

  @override
  String get passwordChanged => 'Password changed.';

  @override
  String get passwordChangedEverywhere =>
      'Password changed here and in the key copy on the server.';

  @override
  String get passwordChangedKeyCopyUnknown =>
      'Password changed here. It is unknown whether the server holds a key copy under the old password — turn the key copy on or off again.';

  @override
  String get showPhrase => 'Show phrase';

  @override
  String get showPhraseBody =>
      'The recovery phrase gives full access to your data. Make sure nobody can see your screen.';

  @override
  String get show => 'Show';

  @override
  String get keyCopySwitch => 'Key copy on the server (password sign-in)';

  @override
  String get keyCopyEnableTitle => 'Turn on password sign-in';

  @override
  String get keyCopyDisableTitle => 'Turn off password sign-in';

  @override
  String get enable => 'Turn on';

  @override
  String get disable => 'Turn off';

  @override
  String get devicesSection => 'Devices';

  @override
  String deviceCurrent(String id) {
    return '$id — this device';
  }

  @override
  String deviceAddedAt(String date) {
    return 'added $date';
  }

  @override
  String deviceRevokedAt(String date) {
    return 'revoked $date';
  }

  @override
  String get revoke => 'Revoke';

  @override
  String get revokeTitle => 'Revoke device?';

  @override
  String revokeBody(String id) {
    return 'Device $id will immediately lose access to the account and data on the server. It can only come back by signing in again with the password or phrase.';
  }

  @override
  String get revoked => 'Device revoked — access closed.';

  @override
  String get errorWeakPassword => 'The password is too weak';

  @override
  String get errorPhraseNotConfirmed => 'The phrase words don\'t match';

  @override
  String get errorBadPhrase =>
      'The phrase has an error: check the words and their order';

  @override
  String get errorLoginTaken => 'This name is taken, choose another';

  @override
  String get errorUnauthenticated =>
      'Wrong name or password, or password sign-in is off — then recover with the phrase';

  @override
  String get errorTooManyDevices =>
      'The account already has 5 devices: revoke one from another device';

  @override
  String get errorCurrentDevice => 'This device can\'t revoke itself';

  @override
  String get errorNoPhrase =>
      'This device has no copy of the phrase: it was added with the password';

  @override
  String get errorRateLimited => 'Too many attempts, try again later';

  @override
  String get errorUnavailable =>
      'The server is unavailable, check your internet connection';

  @override
  String get errorExists => 'This device already has an account';

  @override
  String get agentStatusWaitingForPower => 'Waiting for AC power';

  @override
  String get healthTitle => 'Data health';

  @override
  String get healthOk => 'All good';

  @override
  String get healthOkHint =>
      'The backup is fresh and the check found no problems.';

  @override
  String get healthRepairing => 'Repairing';

  @override
  String get healthRepairingHint =>
      'Some keepers left; the network is rebuilding fragments. Your data is intact.';

  @override
  String get healthAttention => 'Needs attention';

  @override
  String get healthUnknown => 'No backup yet';

  @override
  String get healthUnknownHint =>
      'Choose folders under Backup — the first backup will start by itself.';

  @override
  String get healthReasonBackupFailed => 'The last backup failed';

  @override
  String get healthReasonBackupStale =>
      'No backup for a long time: the computer was off or backups are failing';

  @override
  String get healthReasonRollbackWarning =>
      'The server did not show all snapshots — the list may have been tampered with';

  @override
  String get healthReasonUnrecoverable => 'Some data cannot be restored';

  @override
  String get healthReasonAtRisk => 'Some data has almost no redundancy left';

  @override
  String get healthReasonFragmentsMissing =>
      'Some fragments are unavailable; there is enough redundancy';

  @override
  String get healthReasonVerifyFailed => 'The check failed';

  @override
  String get healthReasonNeverVerified => 'The backup has not been checked yet';

  @override
  String get lastVerify => 'Last check';

  @override
  String get verifyNow => 'Check now';

  @override
  String progressOf(String done, String total) {
    return '$done of $total';
  }

  @override
  String progressSpeed(String size) {
    return '$size/s';
  }

  @override
  String progressReadSpeed(String size) {
    return 'reading $size/s';
  }

  @override
  String progressStoreSpeed(String size) {
    return 'sending $size/s';
  }

  @override
  String progressEta(String time) {
    return 'about $time left';
  }

  @override
  String durationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '$count minute',
    );
    return '$_temp0';
  }

  @override
  String durationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '$count hour',
    );
    return '$_temp0';
  }

  @override
  String get lessThanMinute => 'a minute';

  @override
  String get resumedNote => 'Continuing an interrupted backup';

  @override
  String get estimating => 'Estimating size…';

  @override
  String get currentBackup => 'Current backup';

  @override
  String get backupFolderNow => 'Back up this folder';

  @override
  String backupPaths(String paths) {
    return 'Folders: $paths';
  }

  @override
  String progressPercent(int percent) {
    return '$percent%';
  }

  @override
  String progressElapsed(String time) {
    return 'about $time elapsed';
  }

  @override
  String get verifyStagePreparing => 'Collecting the list of segments…';

  @override
  String get verifyStageChecking => 'Checking that fragments are on the hosts';

  @override
  String get verifyStageReading => 'Reading and checking fragments';

  @override
  String get verifyStageAssembling => 'Assembling segments from fragments';

  @override
  String get verifyStageDone => 'Check complete';

  @override
  String verifySegments(int done, int total) {
    return 'Segments: $done of $total';
  }

  @override
  String verifyFragments(int done, int total) {
    return 'fragments: $done of $total';
  }

  @override
  String verifyCurrentSegment(int segment, int total) {
    return 'segment $segment of $total';
  }

  @override
  String verifyCurrentFragment(int fragment, int total) {
    return 'fragment $fragment of $total';
  }

  @override
  String get verifyWaitingNode => 'waiting for a host…';

  @override
  String verifyProblems(int count) {
    return 'problems: $count';
  }

  @override
  String backupReading(String path) {
    return 'Reading: $path';
  }

  @override
  String get backupReadingFiles => 'Reading files';

  @override
  String get backupStoring => 'Sending data to hosts';

  @override
  String backupStoringSegments(int count) {
    return 'Sending data to hosts (segments: $count)';
  }

  @override
  String get backupCleaning => 'Cleaning up old snapshots';

  @override
  String get deleteSnapshot => 'Delete snapshot';

  @override
  String get deleteSnapshotTitle => 'Delete this snapshot?';

  @override
  String deleteSnapshotNote(String date) {
    return 'The snapshot from $date and its data will be deleted from the hosts. It cannot be restored.';
  }

  @override
  String get deleteBackup => 'Delete backup data';

  @override
  String get deleteAllSnapshots => 'Delete all snapshots of this computer';

  @override
  String get deleteAllSnapshotsTitle =>
      'Delete all snapshots of this computer?';

  @override
  String get deleteAllSnapshotsNote =>
      'All snapshots of this computer and their data on the hosts will be deleted. They cannot be restored.';

  @override
  String get deleteStarted => 'Deletion started';

  @override
  String get jobForget => 'Deleting snapshots';

  @override
  String get networkSection => 'Network';

  @override
  String get networkLimitsHint =>
      'Speed limit for backup, verification and restore over the network on this computer. The keeper has its own limits on the Keeper screen.';

  @override
  String get networkUpload => 'Upload';

  @override
  String get networkDownload => 'Download';

  @override
  String get keeperSpeedLimits => 'Speed limits';

  @override
  String get deleteBackupHint =>
      'All snapshots of this computer and their data on the hosts are deleted permanently. Snapshots of other computers of the account are not touched.';

  @override
  String forgetSnapshotsDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snapshots deleted',
      one: '$count snapshot deleted',
    );
    return '$_temp0';
  }

  @override
  String get forgetStagePreparing => 'Preparing: reading the snapshot list';

  @override
  String get forgetStageForgetting => 'Deleting snapshots';

  @override
  String get forgetStageReading => 'Checking the remaining snapshots';

  @override
  String get forgetStageScanning =>
      'Finding segments that are no longer needed';

  @override
  String get forgetStageRewriting => 'Removing references to unneeded segments';

  @override
  String get forgetStageCleaning => 'Preparing to delete data';

  @override
  String get forgetStageDeleting => 'Deleting fragments from hosts';

  @override
  String get forgetStageDone => 'Deletion complete';

  @override
  String forgetSnapshotsProgress(int done, int total) {
    return 'Snapshots: $done of $total';
  }

  @override
  String forgetSegmentsProgress(int done, int total) {
    return 'Segments: $done of $total';
  }

  @override
  String forgetFragmentsDeleted(int count) {
    return 'Fragments deleted: $count';
  }

  @override
  String forgetErrors(int count) {
    return 'Fragments not deleted: $count';
  }

  @override
  String forgetCurrentSnapshot(String date) {
    return 'snapshot from $date';
  }

  @override
  String get addFolder => 'Add folder';

  @override
  String get removeFolder => 'Remove from backup';

  @override
  String get folderPickerFailed => 'Could not open the folder picker';

  @override
  String get excludes => 'Exclusions';

  @override
  String get presetTemporary => 'Temporary files';

  @override
  String get presetCaches => 'Application caches';

  @override
  String get presetTrash => 'Trash';

  @override
  String get presetDevelopment => 'Dependencies and build output';

  @override
  String get customRules => 'Custom rules';

  @override
  String get addRule => 'Add rule';

  @override
  String get ruleHint => 'For example: *.iso or Videos/';

  @override
  String get removeRule => 'Remove rule';

  @override
  String get estimate => 'Estimate size';

  @override
  String get estimateHint => 'See how big the backup will be before it runs.';

  @override
  String estimateResult(String files, String size) {
    return '$files, $size';
  }

  @override
  String estimateExcluded(int count) {
    return 'Excluded by rules: $count';
  }

  @override
  String estimateSkipped(int count) {
    return 'No access or special files: $count';
  }

  @override
  String get estimateTruncated =>
      'There are too many files — only part was counted.';

  @override
  String get estimateNetwork =>
      'It takes more space in the network — with redundancy for reliability; identical data is stored once.';

  @override
  String get frequency => 'How often';

  @override
  String get frequencyHourly => 'every hour';

  @override
  String get frequencyDaily => 'once a day';

  @override
  String get frequencyWeekly => 'once a week';

  @override
  String get onlyHours => 'Only during set hours';

  @override
  String get hoursFrom => 'From';

  @override
  String get hoursTo => 'To';

  @override
  String hourValue(int hour) {
    return '$hour:00';
  }

  @override
  String get onlyOnAc => 'Only on AC power';

  @override
  String get onlyOnAcHint =>
      'On battery, scheduled backups wait, and a running one stops and continues on AC power.';

  @override
  String get verifySchedule => 'Backup check';

  @override
  String get scheduleNote =>
      'Scheduled backups are run by the background agent — you can close this window.';

  @override
  String get retention => 'Snapshot retention';

  @override
  String get keepAll => 'Keep all snapshots';

  @override
  String get keepLast => 'Latest';

  @override
  String get keepHourly => 'Hourly';

  @override
  String get keepDaily => 'Daily';

  @override
  String get keepWeekly => 'Weekly';

  @override
  String get keepMonthly => 'Monthly';

  @override
  String get retentionHint =>
      'The newest snapshot of each hour, day, week and month is kept. The agent removes the rest after a backup and frees the space. Other computers\' snapshots are not touched.';

  @override
  String get retentionInvalid => 'A whole number from 0; at least 1 latest';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved';

  @override
  String get history => 'History';

  @override
  String get noHistory => 'No jobs yet';

  @override
  String get triggerSchedule => 'scheduled';

  @override
  String get triggerManual => 'manual';

  @override
  String get triggerResume => 'continued';

  @override
  String get historyContinues => 'will continue where it stopped';

  @override
  String get reasonPaused => 'paused';

  @override
  String get reasonOnBattery => 'switched to battery';

  @override
  String newData(String size) {
    return '$size of new data';
  }

  @override
  String skippedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files skipped',
      one: '$count file skipped',
    );
    return '$_temp0';
  }

  @override
  String get details => 'Details';

  @override
  String get skippedTitle => 'Skipped files';

  @override
  String get skippedExplain =>
      'These files are not in the snapshot. Usually they cannot be read or changed while being read — the next backup will try again.';

  @override
  String get skipReasonError => 'no access or read error';

  @override
  String get skipReasonSpecial =>
      'special file (socket, device) — these are not backed up';

  @override
  String retentionResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count old snapshots removed',
      one: '$count old snapshot removed',
    );
    return '$_temp0';
  }

  @override
  String freed(String size) {
    return '$size freed';
  }

  @override
  String verifyResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segments checked',
      one: '$count segment checked',
    );
    return '$_temp0';
  }

  @override
  String errorText(String message) {
    return 'Error: $message';
  }

  @override
  String get snapshotsOnRestore => 'The list of snapshots is under Restore.';

  @override
  String get restoreOpenSnapshot => 'Open snapshot';

  @override
  String get browserBack => 'Back to snapshots';

  @override
  String get browserRoot => 'Snapshot';

  @override
  String get searchHint =>
      'Search by name: part of a name or a pattern like *.pdf';

  @override
  String get searchClear => 'Clear search';

  @override
  String searchResults(int count) {
    return 'Found: $count';
  }

  @override
  String searchTruncated(int count) {
    return 'Showing the first $count. Narrow the search.';
  }

  @override
  String get searchNothing => 'Nothing found';

  @override
  String get folderEmpty => 'The folder is empty';

  @override
  String get loadingItem => 'Loading…';

  @override
  String selectedCount(int count) {
    return 'Selected: $count';
  }

  @override
  String get restoreSelected => 'Restore selected';

  @override
  String get clearSelection => 'Clear selection';

  @override
  String get fileVersions => 'File versions';

  @override
  String versionsTitle(String name) {
    return 'Versions of “$name”';
  }

  @override
  String get versionChanged => 'changed';

  @override
  String get versionSame => 'unchanged';

  @override
  String get versionAbsent => 'not in this snapshot';

  @override
  String get restoreThisVersion => 'Restore';

  @override
  String get chooseFolder => 'Choose a folder';

  @override
  String restoreWhat(String what) {
    return 'What: $what';
  }

  @override
  String get restoreWholeSnapshot => 'the whole snapshot';

  @override
  String get restoreWhere => 'Where to';

  @override
  String get restoreOriginal => 'To the original location';

  @override
  String get restoreOriginalHint =>
      'Files go back to where they were backed up from.';

  @override
  String get restoreToFolder => 'To another folder';

  @override
  String get restoreExisting => 'If the file already exists';

  @override
  String get existingKeepBoth =>
      'Keep both: the restored copy gets “(restored)” in its name';

  @override
  String get existingSkip => 'Keep the existing file, skip the restored one';

  @override
  String get existingOverwrite =>
      'Replace the existing file with the restored one';

  @override
  String get restoredSuffix => 'restored';

  @override
  String get restoreWait => 'If some keepers are offline';

  @override
  String get waitNone => 'Don’t wait — restore what is available';

  @override
  String get waitHour => 'Wait up to an hour';

  @override
  String get waitDay => 'Wait up to a day';

  @override
  String get restoreStart => 'Restore';

  @override
  String get restoreStarted =>
      'Restore started. Progress is shown here and on the Overview.';

  @override
  String get restoreCurrent => 'Restore in progress';

  @override
  String waitingTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files are waiting for keepers',
      one: '$count file is waiting for keepers',
    );
    return '$_temp0';
  }

  @override
  String get waitingExplain =>
      'Parts of these files are held by keepers that are offline right now: fewer fragments are available than needed to rebuild them. Everything else is being restored; these files will follow when the keepers come back.';

  @override
  String andMore(int count) {
    return 'and $count more';
  }

  @override
  String waitingRetry(String time) {
    return 'Next attempt within $time';
  }

  @override
  String waitingLeft(String time) {
    return 'Will keep waiting for up to $time';
  }

  @override
  String waitingReason(String reason) {
    return 'Details: $reason';
  }

  @override
  String get lastRestore => 'Last restore';

  @override
  String get restoreWhen => 'When';

  @override
  String get restoreProblem => 'Error';

  @override
  String get restoreWhereLabel => 'Where';

  @override
  String get restoreRestored => 'Restored';

  @override
  String get restoreSkippedLabel => 'Existing files left as is';

  @override
  String get restoreRenamedLabel => 'Saved next to existing files';

  @override
  String get restoreErrorsLabel => 'Not restored';

  @override
  String get speedUnlimited => 'unlimited';

  @override
  String speedValue(String size) {
    return '$size/s';
  }

  @override
  String get keeperEnableTitle => 'Share space';

  @override
  String get keeperEditTitle => 'Keeper settings';

  @override
  String get keeperPrivacy =>
      'Fragments are encrypted on the owner’s computer before they are sent. A keeper cannot read them and does not know whose files they are or what they are called.';

  @override
  String get keeperFolder => 'Folder for fragments';

  @override
  String keeperFree(String size) {
    return 'Free on this disk: $size';
  }

  @override
  String get keeperQuotaLabel => 'Space to share, GB';

  @override
  String get keeperQuotaInvalid => 'Enter a number of gigabytes';

  @override
  String get keeperQuotaTooBig => 'More than is free on the disk';

  @override
  String get keeperQuotaMin =>
      'The server usually accepts keepers sharing 10 GB or more';

  @override
  String get keeperUpload => 'Upload';

  @override
  String get keeperDownload => 'Download';

  @override
  String get keeperWorkHours => 'During work hours (Mon–Fri, 9–18)';

  @override
  String get keeperBackgroundNote =>
      'The keeper runs in the background, even with the window closed.';

  @override
  String get keeperEnable => 'Become a keeper';

  @override
  String get keeperEnabled => 'You are now a keeper';

  @override
  String get keeperNoBinary =>
      'Settings are saved, but the keeper program was not found next to the app. Start the keeper service manually.';

  @override
  String get keeperNoCoordinator =>
      'This account has no server, so the keeper has nowhere to register.';

  @override
  String get keeperNotRunning =>
      'The keeper role is on, but the keeper service is not running.';

  @override
  String get keeperStart => 'Start';

  @override
  String get keeperStats => 'Statistics';

  @override
  String get keeperFreeQuota => 'Free of shared space';

  @override
  String get keeperDisk => 'Free on disk';

  @override
  String get keeperTraffic => 'Traffic since start';

  @override
  String keeperTrafficValue(String sent, String received) {
    return 'sent $sent, received $received';
  }

  @override
  String get keeperUdp => 'over UDP after hole punching';

  @override
  String get keeperRelay => 'through a relay';

  @override
  String get keeperNoIncoming => 'no incoming connections';

  @override
  String keeperPortHint(int port) {
    return 'For faster direct connections, open port $port (TCP and UDP) on your router or enable UPnP on it.';
  }

  @override
  String keeperPortMappingError(String error) {
    return 'Could not open the port automatically: $error';
  }

  @override
  String get keeperCoordinator => 'How the server sees you';

  @override
  String get keeperNoCoordinatorShort => 'no server configured';

  @override
  String get keeperRegistered => 'registered';

  @override
  String keeperNotRegistered(String error) {
    return 'not registered: $error';
  }

  @override
  String get keeperWaitingCoordinator => 'waiting for the server';

  @override
  String get keeperAvailability => 'Availability, last 30 days';

  @override
  String get keeperReputation => 'Reputation';

  @override
  String keeperProbation(String date) {
    return 'on probation until $date';
  }

  @override
  String get keeperAudits => 'Storage audits';

  @override
  String keeperAuditsValue(int passed, int failed) {
    return 'passed $passed, failed $failed';
  }

  @override
  String get keeperExcluded =>
      'The server has excluded this keeper: no new fragments will arrive.';

  @override
  String get keeperStandingSoon =>
      'Details appear after the next contact with the server.';

  @override
  String get keeperBarter => 'Balance';

  @override
  String get keeperBarterSoon =>
      'Your barter balance will appear here: how much space you share and how much you can store.';

  @override
  String get keeperRole => 'Keeper role';

  @override
  String get keeperChange => 'Change';

  @override
  String get keeperStop => 'Turn the keeper off';

  @override
  String get keeperStopConfirm =>
      'The keeper stops; fragments stay on the disk. If it stays off for long, the server rebuilds these fragments on other keepers. You can turn it back on at any time.';

  @override
  String get keeperLeave => 'Leave the keeper role';

  @override
  String get keeperLeaveSoon =>
      'Leaving with fragments moved to other keepers and the space freed is coming in a later version. For now you can turn the keeper off.';

  @override
  String get trayBackupNow => 'Back up now';

  @override
  String get trayPause => 'Pause';

  @override
  String get trayResume => 'Resume';

  @override
  String get trayOpen => 'Open window';

  @override
  String get trayQuit => 'Close icon';

  @override
  String get backgroundTitle => 'Background work';

  @override
  String get backgroundExplain =>
      'Scheduled backups and the keeper keep working after the window is closed: they are system services that start when you sign in.';

  @override
  String get backgroundService => 'Backup agent service';

  @override
  String get backgroundServices => 'Services';

  @override
  String get serviceAgent => 'Backup agent';

  @override
  String get serviceKeeper => 'Keeper';

  @override
  String get serviceStart => 'Start';

  @override
  String get serviceStop => 'Stop';

  @override
  String get serviceRestart => 'Restart';

  @override
  String get serviceKeeperOff =>
      'The keeper role is off — enable it on the Keeper screen.';

  @override
  String get serviceRunning => 'running';

  @override
  String get serviceStopped => 'stopped';

  @override
  String get serviceNotInstalled => 'not installed';

  @override
  String get serviceInstall => 'Install service';

  @override
  String get serviceRemove => 'Remove service';

  @override
  String get serviceRemoveConfirm =>
      'Without the service, scheduled backups will not run unless the agent is started manually. Remove the service?';

  @override
  String get backgroundUnavailable =>
      'System services are unavailable or the agent program was not found: the backup agent has to be started manually.';

  @override
  String get trayAtLogin => 'Tray icon at sign-in';

  @override
  String get trayUnavailable =>
      'The tray icon is not available in this environment (GNOME needs the AppIndicator extension). Backups still run in the background.';

  @override
  String get keeperLingerTitle => 'Keeper without signing in';

  @override
  String get keeperLingerOff =>
      'Right now the keeper only works while you are signed in. To keep it available after a reboot without signing in, run this command in a terminal (administrator rights required):';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get updateTitle => 'Updates';

  @override
  String get autoUpdate => 'Check for and install updates automatically';

  @override
  String get betaChannel => 'Beta update channel';

  @override
  String get updateCheck => 'Check for updates';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String updateAvailable(String version) {
    return 'Version $version is available';
  }

  @override
  String get updateInstall => 'Download and install';

  @override
  String get updateApplying => 'Downloading and installing…';

  @override
  String get updateUpToDate => 'You have the latest version.';

  @override
  String get updateNeverChecked => 'Updates have not been checked yet.';

  @override
  String updateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String get updateRestarting => 'Update installed; the app will restart.';

  @override
  String updateManual(String url) {
    return 'A new version is available manually: $url';
  }

  @override
  String get updateWaitingBackup =>
      'The update will install after the backup finishes.';

  @override
  String get crashReports => 'Send crash reports';

  @override
  String get crashReportsExplain =>
      'A report contains only the version, the error type, and text with paths and keys removed. It helps fix crashes and does not contain your files, keys, or passwords.';
}
