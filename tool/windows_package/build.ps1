<#
.SYNOPSIS
    Установщик Backpeer для Windows (задачи 0.2.5, 5.7.1).

.DESCRIPTION
    Собирает программы агента, хранителя и CLI и приложение, раскладывает их
    так, как их ищет DaemonBundle, при желании подписывает (Authenticode) и
    собирает установщик Inno Setup. Запуск на Windows с Visual Studio 2022
    (Desktop development with C++) и Inno Setup 6.3+; подробности —
    docs/ops/windows-packages.md, подпись — docs/ops/windows-signing.md.

.EXAMPLE
    pwsh -File tool/windows_package/build.ps1
    # build/packages/Backpeer-Setup-<версия>-windows-x64.exe, без подписи

.EXAMPLE
    pwsh -File tool/windows_package/build.ps1 -SignThumbprint B6B6…
    # подпись сертификатом из хранилища (токен уже вставлен)
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    # Версия продукта; по умолчанию — из packages/cli/pubspec.yaml.
    [string] $Version,
    # Не собирать приложение (уже собрано прошлым запуском).
    [switch] $SkipApp,
    # Только разложить папку сборки, без установщика.
    [switch] $NoInstaller,
    # Печать отпечатка сертификата в хранилище: signtool /sha1.
    [string] $SignThumbprint,
    # Сертификат в хранилище машины (LocalMachine), а не пользователя.
    [switch] $MachineStore,
    # Файл .pfx вместо хранилища (для сертификата, выпущенного до 2023 года,
    # или тестового; новые сертификаты ЦС выдают только на токене).
    [string] $SignPfx,
    [string] $SignPfxPassword,
    # Сервер отметки времени; пусто вместе с -NoTimestamp — не ставить.
    [string] $TimestampUrl = 'http://timestamp.digicert.com',
    [switch] $NoTimestamp,
    # Подпись через облачный HSM: dlib и метаданные (DigiCert KeyLocker,
    # Azure Artifact Signing). См. docs/ops/windows-signing.md.
    [string] $SignDlib,
    [string] $SignDmdf,
    # Путь к ISCC.exe, если Inno Setup не в PATH.
    [string] $InnoCompiler
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $root

function Write-Step([string] $text) {
    Write-Host ''
    Write-Host "== $text" -ForegroundColor Cyan
}

function Invoke-Native {
    param([string] $FilePath, [string[]] $Arguments)
    Write-Host "> $FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath завершилась с кодом $LASTEXITCODE"
    }
}

function Resolve-Tool {
    param([string] $Name, [string] $Fallback, [string] $Hint)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if ($Fallback -and (Test-Path $Fallback)) { return $Fallback }
    throw "$Name не найден: $Hint"
}

# Компилятор C# входит в .NET Framework 4, то есть в Windows 10/11; отдельная
# установка не нужна. Запускатель — единственный .cs в сборке (5.7.1, Б-2).
function Resolve-Csc {
    $candidates = @(
        (Join-Path ${env:WINDIR} 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path ${env:WINDIR} 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    $command = Get-Command 'csc.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    # Продолжение строки в PowerShell — оператором в конце строки: «+» в
    # начале следующей строки разборщик не принимает (Missing closing ')')
    # и задание сборки установщика падало ещё до компиляции (10.11.2026).
    throw ('csc.exe не найден: нужен .NET Framework 4 (входит в Windows ' +
        '10/11), см. docs/ops/windows-packages.md')
}

# Подсистема PE: 2 — WINDOWS (без консоли), 3 — CONSOLE. У запускателя
# должна быть 2, иначе он сам покажет чёрное окно.
function Get-PeSubsystem([string] $Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x100 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "$Path не похож на .exe (нет MZ)"
    }
    $pe = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($pe -le 0 -or $pe + 0x5E -ge $bytes.Length -or
        $bytes[$pe] -ne 0x50 -or $bytes[$pe + 1] -ne 0x45) {
        throw "$Path не похож на PE-файл"
    }
    return [BitConverter]::ToUInt16($bytes, $pe + 0x5C)
}

# --- Версия и коммит -------------------------------------------------------

if (-not $Version) {
    $pubspec = Join-Path $root 'packages\cli\pubspec.yaml'
    $match = Select-String -Path $pubspec -Pattern '^version:\s*(\S+)\s*$' |
        Select-Object -First 1
    if (-not $match) { throw "в $pubspec нет строки version:" }
    $Version = $match.Matches[0].Groups[1].Value
}
# Версия PE-ресурсов и установщика — только цифры: 0.0.3-dev.3 -> 0.0.3.0.
$numeric = ($Version -replace '[-+].*$', '')
$parts = @($numeric.Split('.'))
while ($parts.Count -lt 4) { $parts += '0' }
$numericVersion = ($parts[0..3] -join '.')

$commit = $env:GITHUB_SHA
if ($commit) { $commit = $commit.Substring(0, [Math]::Min(7, $commit.Length)) }
else {
    $commit = (& git rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $commit = 'unknown' }
}

$dart = Resolve-Tool 'dart' (Join-Path $root '.fvm\flutter_sdk\bin\dart.exe') `
    'поставьте Flutter из .fvmrc (fvm install) или добавьте Dart в PATH'
$flutter = Resolve-Tool 'flutter' (Join-Path $root '.fvm\flutter_sdk\bin\flutter.bat') `
    'поставьте Flutter из .fvmrc (fvm install) или добавьте Flutter в PATH'

$packages = Join-Path $root 'build\packages'
$stage = Join-Path $packages 'windows\stage'
$installerName = "Backpeer-Setup-$Version-windows-x64.exe"

Write-Host "Windows: версия $Version ($commit), сборка установщика"

# --- 1. Программы: папка «бинарник + lib/» на каждую ----------------------

Write-Step 'Программы агента, хранителя и CLI'
Invoke-Native $dart @('run', 'tool/build_exe.dart')

$bundles = @{}
foreach ($program in @('agent', 'node', 'cli')) {
    $bundle = Join-Path $root "build\bin\windows-x64\$program\bundle"
    $exe = Join-Path $bundle "bin\$program.exe"
    if (-not (Test-Path $exe)) { throw "нет $exe — сборка программ не удалась" }
    $bundles[$program] = $bundle
}

# --- 2. Приложение ---------------------------------------------------------

if ($SkipApp) {
    Write-Step 'Приложение: сборка пропущена (-SkipApp)'
}
else {
    Write-Step 'Приложение (flutter build windows --release)'
    # Версия и коммит в приложении: от версии зависит проверка обновлений
    # (5.8.2), а `flutter build` не знает `--define` для core. Значения
    # подставляются на время сборки, как в tool/macos_package/build.sh.
    $values = Join-Path $root 'packages\core\lib\src\build_info_values.dart'
    $original = [IO.File]::ReadAllText($values)
    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
    $appInfo = $original.Replace(
        "buildAppVersion = 'dev'", "buildAppVersion = '$Version'").Replace(
        "buildGitCommit = 'unknown'", "buildGitCommit = '$commit'")
    $defines = @()
    if ($env:UPDATE_PUBLIC_KEY) {
        $defines += "--dart-define=UPDATE_PUBLIC_KEY=$env:UPDATE_PUBLIC_KEY"
    }
    if ($env:UPDATE_BASE_URL) {
        $defines += "--dart-define=UPDATE_BASE_URL=$env:UPDATE_BASE_URL"
    }
    Push-Location (Join-Path $root 'apps\app')
    try {
        [IO.File]::WriteAllText($values, $appInfo, $utf8)
        Invoke-Native $flutter (@('build', 'windows', '--release') + $defines)
    }
    finally {
        [IO.File]::WriteAllText($values, $original, $utf8)
        Pop-Location
    }
}

$release = Join-Path $root 'apps\app\build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'backpeer.exe'))) {
    throw "нет $release\backpeer.exe — приложение не собралось"
}

# --- 3. Раскладка ----------------------------------------------------------

Write-Step "Раскладка в $stage"
if (Test-Path $stage) { Remove-Item -Path $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -Path (Join-Path $release '*') -Destination $stage -Recurse -Force

# DaemonBundle ищет daemons/<программа>/bin/<программа>.exe и lib/ рядом
# (packages/agent/lib/src/services.dart). Та же раскладка, что в .app на macOS
# (tool/macos_package/build.sh) и в /opt/backpeer на Linux (5.7.3).
foreach ($program in $bundles.Keys) {
    $target = Join-Path $stage "daemons\$program"
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item -Path (Join-Path $bundles[$program] '*') -Destination $target -Recurse -Force
}

# Запускатель без консольного окна: задание Планировщика запускает не сам
# agent.exe/node.exe (подсистема CONSOLE — окно висело бы всё время работы),
# а backpeer-launcher.exe (подсистема WINDOWS), который запускает демон с
# CREATE_NO_WINDOW. Копия — рядом с каждой программой: так её ищет
# ScheduledTaskServices (packages/daemon_kit/lib/src/user_services.dart).
Write-Step 'Запускатель фоновых процессов без окна (C#)'
$launcherSource = Join-Path $PSScriptRoot 'launcher.cs'
$csc = Resolve-Csc
$launcherTemp = Join-Path $packages 'windows\backpeer-launcher.exe'
Invoke-Native $csc @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/codepage:65001',
    "/out:$launcherTemp",
    $launcherSource
)
if ((Get-PeSubsystem $launcherTemp) -ne 2) {
    throw "запускатель $launcherTemp собрался не подсистемой WINDOWS"
}
foreach ($program in @('agent', 'node')) {
    Copy-Item -Path $launcherTemp `
        -Destination (Join-Path $stage "daemons\$program\bin\backpeer-launcher.exe") `
        -Force
}
Remove-Item -Path $launcherTemp -Force

# Проверка раскладки до сборки установщика: без libsodium программа не
# запустится, а установщик собрался бы и упал только у пользователя.
$required = @(
    'backpeer.exe',
    'flutter_windows.dll',
    'data\app.so',
    'daemons\agent\bin\agent.exe',
    'daemons\agent\bin\backpeer-launcher.exe',
    'daemons\agent\lib\libsodium.dll',
    'daemons\node\bin\node.exe',
    'daemons\node\bin\backpeer-launcher.exe',
    'daemons\node\lib\libsodium.dll',
    'daemons\cli\bin\cli.exe'
)
foreach ($file in $required) {
    $path = Join-Path $stage $file
    if (-not (Test-Path $path)) { throw "в сборке нет $file" }
}

$size = (Get-ChildItem $stage -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("Раскладка: {0:N1} МиБ, файлов {1}" -f ($size / 1MB),
    (Get-ChildItem $stage -Recurse -File).Count)

# --- 4. Подпись файлов -----------------------------------------------------

# Подписываем только если задан способ подписи: без сертификата сборка
# остаётся неподписанной (так собирает задание installer-windows).
$signing = [bool]($SignThumbprint -or $SignPfx -or $SignDlib)
$signArgs = @{}
if ($signing) {
    if ($SignThumbprint) {
        $signArgs.Thumbprint = $SignThumbprint
        if ($MachineStore) { $signArgs.MachineStore = $true }
    }
    if ($SignPfx) { $signArgs.Pfx = $SignPfx }
    if ($SignPfxPassword) { $signArgs.PfxPassword = $SignPfxPassword }
    if ($SignDlib) { $signArgs.Dlib = $SignDlib }
    if ($SignDmdf) { $signArgs.Dmdf = $SignDmdf }
    if ($NoTimestamp) { $signArgs.NoTimestamp = $true }
    else { $signArgs.TimestampUrl = $TimestampUrl }
}

$signScript = Join-Path $PSScriptRoot 'sign.ps1'
if ($signing) {
    Write-Step 'Подпись Authenticode: программы и библиотеки'
    $files = Get-ChildItem -Path $stage -Recurse -File |
        Where-Object { $_.Extension -in @('.exe', '.dll') } |
        ForEach-Object { $_.FullName }
    if (-not $files) { throw "в $stage нет .exe и .dll для подписи" }
    & $signScript -Path $files @signArgs -Verify
    if ($LASTEXITCODE -ne 0) { throw 'подпись файлов не удалась' }
}
else {
    Write-Step 'Подпись пропущена: сборка неподписанная (docs/ops/windows-signing.md)'
}

# --- 5. Установщик ---------------------------------------------------------

if ($NoInstaller) {
    Write-Step 'Установщик: сборка пропущена (-NoInstaller)'
    return
}

function Find-Iscc([string] $explicit) {
    if ($explicit) {
        if (Test-Path $explicit) { return (Resolve-Path $explicit).Path }
        throw "нет $explicit"
    }
    $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    $found = Get-ChildItem -Path "${env:ProgramFiles(x86)}", $env:ProgramFiles `
        -Filter 'ISCC.exe' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    throw ('Inno Setup не найден: поставьте Inno Setup 6.3+ ' +
        '(https://jrsoftware.org/isdl.php) или укажите -InnoCompiler')
}

$iscc = Find-Iscc $InnoCompiler
New-Item -ItemType Directory -Path $packages -Force | Out-Null

Write-Step 'Установщик (Inno Setup)'
Invoke-Native $iscc @(
    '/Qp',
    "/DStageDir=$stage",
    "/DOutputDir=$packages",
    "/DAppVersion=$Version",
    "/DNumericVersion=$numericVersion",
    "/DSourceDir=$(Join-Path $root 'tool\windows_package')",
    (Join-Path $root 'tool\windows_package\backpeer.iss')
)

$installer = Join-Path $packages $installerName
if (-not (Test-Path $installer)) { throw "нет $installer — ISCC не собрал установщик" }

# --- 6. Подпись установщика и контрольная сумма ---------------------------

if ($signing) {
    Write-Step 'Подпись установщика'
    & $signScript -Path $installer @signArgs -Verify
    if ($LASTEXITCODE -ne 0) { throw 'подпись установщика не удалась' }
}

$hash = (Get-FileHash -Path $installer -Algorithm SHA256).Hash.ToLower()
$sums = Join-Path $packages 'SHA256SUMS'
Set-Content -Path $sums -Value "$hash  $installerName" -Encoding ASCII

Write-Step 'Готово'
Write-Host ("{0} ({1:N1} МиБ)" -f $installer,
    ((Get-Item $installer).Length / 1MB))
Write-Host "SHA-256: $hash"
if (-not $signing) {
    Write-Host 'Сборка неподписанная: Windows покажет предупреждение SmartScreen.' -ForegroundColor Yellow
}
