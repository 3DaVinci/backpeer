; Установщик Backpeer для Windows (задачи 0.2.5, 5.7.1).
;
; Собирается tool/windows_package/build.ps1; вручную запускать не нужно.
; Раскладка Source — папка «приложение + daemons/<программа>/bin|lib>»,
; которую готовит скрипт (DaemonBundle ищет daemons/ рядом с backpeer.exe,
; packages/agent/lib/src/services.dart).
;
; Установка только для текущего пользователя (ADR-011: фоновые процессы —
; службы уровня пользователя, задание Планировщика; служба Windows не видит
; ни сетевых дисков, ни секретов DPAPI). Поэтому прав администратора при
; установке не нужно, а правило брандмауэра ставит не установщик: его может
; добавить только администратор, при первом прослушивании Windows спросит
; разрешение (docs/ops/windows-packages.md).
;
; Inno Setup 6.3 и новее (ArchitecturesAllowed=x64compatible). Лицензия Inno
; Setup разрешает коммерческое использование и не требует открывать код.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef NumericVersion
  #define NumericVersion "0.0.0.0"
#endif
#ifndef StageDir
  #define StageDir "..\..\build\packages\windows\stage"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\packages"
#endif
#ifndef SourceDir
  #define SourceDir "."
#endif

[Setup]
; Идентификатор приложения (не менять: по нему Windows узнаёт обновление).
AppId={{34109E71-5CFE-4E25-BC2C-AD3B1699D1B0}
AppName=Backpeer
AppVersion={#AppVersion}
AppVerName=Backpeer {#AppVersion}
AppPublisher=Backpeer
AppPublisherURL=https://backpeer.app/
AppSupportURL=https://backpeer.app/
AppUpdatesURL=https://backpeer.app/downloads/
VersionInfoVersion={#NumericVersion}
VersionInfoProductVersion={#NumericVersion}
VersionInfoProductName=Backpeer
VersionInfoCompany=Backpeer
VersionInfoDescription=Backpeer setup
VersionInfoCopyright=AGPL-3.0
DefaultDirName={autopf}\Backpeer
DefaultGroupName=Backpeer
DisableProgramGroupPage=yes
AllowNoIcons=yes
; Только текущий пользователь: %LOCALAPPDATA%\Programs\Backpeer, без UAC.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; MVP поддерживает Windows 10 22H2 и 11 (docs/mvp-scope.md).
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=Backpeer-Setup-{#AppVersion}-windows-x64
SetupIconFile={#SourceDir}\..\..\apps\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\backpeer.exe
UninstallDisplayName=Backpeer
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
; Обновление: закрыть процессы, которые держат файлы из {app}.
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Приложение, программы фоновых процессов и библиотеки — как есть.
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Backpeer"; Filename: "{app}\backpeer.exe"
Name: "{autodesktop}\Backpeer"; Filename: "{app}\backpeer.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\backpeer.exe"; Description: "{cm:LaunchProgram,Backpeer}"; Flags: nowait postinstall skipifsilent

; Удаление: сначала снять службы (задание Планировщика, запуск при входе) и
; остановить процессы — это умеет `agent uninstall` (5.6.1, 5.7.3), затем
; установщик удаляет {app}. Данные и ключи остаются в %APPDATA%\backpeer и
; %LOCALAPPDATA%\backpeer\node, если пользователь не выбрал полное удаление.
[UninstallRun]
Filename: "{app}\daemons\agent\bin\agent.exe"; Parameters: "uninstall --yes"; Flags: runhidden waituntilterminated; RunOnceId: "AgentUninstall"; Check: KeepData
Filename: "{app}\daemons\agent\bin\agent.exe"; Parameters: "uninstall --purge --yes"; Flags: runhidden waituntilterminated; RunOnceId: "AgentUninstallPurge"; Check: PurgeAll

[Code]
var
  PurgeData: Boolean;

/// Check в [UninstallRun] принимает только имя функции, поэтому две обёртки.
function KeepData: Boolean;
begin
  Result := not PurgeData;
end;

function PurgeAll: Boolean;
begin
  Result := PurgeData;
end;

/// Установка поверх прошлой версии: работающие agent.exe и node.exe держат
/// файлы в {app}, и установщик не смог бы их заменить. `agent uninstall`
/// снимает службы и останавливает оба процесса через локальный API; службы
/// поставит снова приложение при первом запуске (5.6.1).
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Agent: String;
  ResultCode: Integer;
begin
  Agent := ExpandConstant('{app}\daemons\agent\bin\agent.exe');
  if FileExists(Agent) then
  begin
    Log('Остановка фоновых процессов прошлой версии: ' + Agent);
    Exec(Agent, 'uninstall --yes', '', SW_HIDE, ewWaitUntilTerminated,
      ResultCode);
  end;
  Result := '';
end;

/// Удаление: спросить, удалять ли данные и ключи. В тихом режиме
/// (/VERYSILENT) вопрос подавляется и данные остаются — так удаление
/// безопасно и для автоматических сценариев.
function InitializeUninstall(): Boolean;
begin
  PurgeData :=
    SuppressibleMsgBox(
      'Удалить также настройки, ключи этого устройства и данные хранителя?'
      + #13#10 + #13#10
      + 'Нет — данные останутся в %APPDATA%\backpeer и '
      + '%LOCALAPPDATA%\backpeer\node, а программа удалится. Бэкапы в сети '
      + 'останутся в любом случае: войти к ним можно по паролю или фразе '
      + 'восстановления.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;
  Result := True;
end;

/// Брандмауэр: установка идёт без прав администратора, поэтому правило
/// добавляет не установщик. Подсказка — на последней странице.
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
    WizardForm.FinishedLabel.Caption :=
      WizardForm.FinishedLabel.Caption + #13#10 + #13#10 +
      'Роль хранителя принимает подключения других узлов. При первом ' +
      'запуске Windows спросит разрешение для node.exe — без него ' +
      'узел будет доступен только через relay. Правило можно добавить и ' +
      'вручную, от имени администратора (docs/ops/windows-packages.md).';
end;
