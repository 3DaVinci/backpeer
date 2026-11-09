<#
.SYNOPSIS
    Проверка установщика Windows на настоящей системе (задача 5.7.1).

.DESCRIPTION
    Ставит установщик молча, проверяет раскладку и запуск программ, ставит и
    снимает службу Планировщика (5.6.1), удаляет программу и проверяет, что
    каталог установки убран. Так задание `installer-windows` в CI проверяет
    не только сборку, но и установку на чистой Windows.

    Запуск на машине установки, права администратора не нужны (установка
    идёт в %LOCALAPPDATA%\Programs\Backpeer).

.EXAMPLE
    pwsh -File tool/windows_package/test_install.ps1 build\packages\Backpeer-Setup-*-windows-x64.exe
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    # Установщик; можно с шаблоном, но найдено должно быть ровно одно.
    [Parameter(Mandatory = $true)]
    [string] $Installer,
    # Не проверять задание Планировщика (на машине без планировщика).
    [switch] $SkipService
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Write-Step([string] $text) {
    Write-Host ''
    Write-Host "== $text" -ForegroundColor Cyan
}

function Assert-Path([string] $path, [string] $what) {
    if (-not (Test-Path $path)) { throw "нет $what : $path" }
    Write-Host "  есть $what"
}

function Wait-For([scriptblock] $condition, [string] $what, [int] $seconds = 180) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (& $condition) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "не дождались: $what"
}

# Подсистема PE: 2 — WINDOWS (без консоли), 3 — CONSOLE. У запускателя
# должна быть 2, иначе он сам покажет чёрное окно (Б-2).
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

function Get-TaskState([string] $Name) {
    $task = Get-ScheduledTask -TaskName $Name -TaskPath '\backpeer\' `
        -ErrorAction SilentlyContinue
    if (-not $task) { return 'NotFound' }
    return [string]$task.State
}

$found = @(Get-Item $Installer -ErrorAction Stop)
if ($found.Count -ne 1) {
    throw "ожидался один установщик, найдено $($found.Count)"
}
$installerPath = $found[0].FullName
$installer = $found[0].Name
$dir = Join-Path $env:LOCALAPPDATA 'Programs\Backpeer'
$logDir = Join-Path $root 'build\packages\windows'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$installLog = Join-Path $logDir 'install.log'
$uninstallLog = Join-Path $logDir 'uninstall.log'

Write-Host "Установщик: $installer"
$signature = Get-AuthenticodeSignature -FilePath $installerPath
Write-Host "Подпись: $($signature.Status)"
if ($signature.SignerCertificate) {
    Write-Host "Издатель: $($signature.SignerCertificate.Subject)"
}

# --- Установка -------------------------------------------------------------

Write-Step "Установка (для текущего пользователя, $dir)"
if (Test-Path $dir) { Remove-Item -Path $dir -Recurse -Force }
$process = Start-Process -FilePath $installerPath -Wait -PassThru -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-',
    "/LOG=`"$installLog`""
)
if ($process.ExitCode -ne 0) {
    throw "установщик завершился с кодом $($process.ExitCode), журнал: $installLog"
}

# --- Раскладка -------------------------------------------------------------

Write-Step 'Раскладка установленной программы'
Assert-Path (Join-Path $dir 'backpeer.exe') 'приложение'
Assert-Path (Join-Path $dir 'data\app.so') 'код приложения (AOT)'
Assert-Path (Join-Path $dir 'flutter_windows.dll') 'Flutter'
foreach ($program in @('agent', 'node', 'cli')) {
    Assert-Path (Join-Path $dir "daemons\$program\bin\$program.exe") "программа $program"
    Assert-Path (Join-Path $dir "daemons\$program\lib\libsodium.dll") "libsodium для $program"
}
Assert-Path (Join-Path $dir 'daemons\node\lib\sqlite3.dll') 'SQLite для хранителя'

# Запускатель без консольного окна: именно его, а не консольный agent.exe,
# запускает задание Планировщика (Б-2, 5.7.1).
foreach ($program in @('agent', 'node')) {
    $launcher = Join-Path $dir "daemons\$program\bin\backpeer-launcher.exe"
    Assert-Path $launcher "запускатель без окна для $program"
    $subsystem = Get-PeSubsystem $launcher
    if ($subsystem -ne 2) {
        throw "у $launcher подсистема $subsystem, а нужна WINDOWS (2)"
    }
    Write-Host "  $program: подсистема WINDOWS (2), окна консоли нет"
}

$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Backpeer.lnk'
Assert-Path $shortcut 'ярлык в меню «Пуск»'

# --- Запуск программ из установленной папки --------------------------------
# Проверяет, что DaemonBundle-раскладка рабочая: программы находят libsodium
# и SQLite рядом с собой, а не в каталоге сборки.

Write-Step 'Программы запускаются'
foreach ($program in @('cli', 'node', 'agent')) {
    $exe = Join-Path $dir "daemons\$program\bin\$program.exe"
    $output = & $exe --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$program --version завершилась с кодом $($LASTEXITCODE): $output"
    }
    if (-not ("$output" -match '\d+\.\d+\.\d+')) {
        throw "$program --version не назвала версию: $output"
    }
    Write-Host "  ${program}: $output"
}

# --- Служба Планировщика (5.6.1) -------------------------------------------
# Впервые проверяется на настоящей Windows: до этого XML и вызовы schtasks
# были проверены только тестами.

if (-not $SkipService) {
    Write-Step 'Задание Планировщика: установка, состояние, удаление'
    $agent = Join-Path $dir 'daemons\agent\bin\agent.exe'
    & $agent service install
    if ($LASTEXITCODE -ne 0) { throw 'agent service install завершилась с ошибкой' }

    & schtasks /Query /TN '\backpeer\agent' /FO LIST 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'задание \backpeer\agent не создано' }
    Write-Host '  задание \backpeer\agent создано'

    # Задание запускает запускатель, а не консольную программу.
    $taskXml = (& schtasks /Query /TN '\backpeer\agent' /XML) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'не удалось прочитать XML задания' }
    if ($taskXml -notmatch 'backpeer-launcher\.exe') {
        throw 'задание запускает не backpeer-launcher.exe: будет окно консоли'
    }
    Write-Host '  задание запускает backpeer-launcher.exe'

    $status = & $agent service status 2>&1
    if ($LASTEXITCODE -ne 0) { throw "agent service status: $status" }
    Write-Host "  состояние: $($status -join ' ' | Out-String)"

    # Запуск, остановка и перезапуск из CLI (app/service management).
    & $agent service stop
    if ($LASTEXITCODE -ne 0) { throw 'agent service stop завершилась с ошибкой' }
    Wait-For { (Get-TaskState 'agent') -ne 'Running' } 'задание остановлено'
    Write-Host '  задание остановлено'

    & $agent service start
    if ($LASTEXITCODE -ne 0) { throw 'agent service start завершилась с ошибкой' }
    Wait-For { (Get-TaskState 'agent') -eq 'Running' } 'задание запущено'
    Write-Host '  задание запущено'

    & $agent service restart
    if ($LASTEXITCODE -ne 0) { throw 'agent service restart завершилась с ошибкой' }
    Wait-For { (Get-TaskState 'agent') -eq 'Running' } 'задание перезапущено'
    Write-Host '  задание перезапущено'

    & $agent service uninstall
    if ($LASTEXITCODE -ne 0) { throw 'agent service uninstall завершилась с ошибкой' }
    & schtasks /Query /TN '\backpeer\agent' /FO LIST 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { throw 'задание \backpeer\agent осталось после удаления' }
    Write-Host '  задание удалено'
}

# --- Удаление --------------------------------------------------------------

Write-Step 'Удаление'
$uninstaller = Get-ChildItem -Path $dir -Filter 'unins*.exe' | Select-Object -First 1
if (-not $uninstaller) { throw "в $dir нет unins*.exe" }
$process = Start-Process -FilePath $uninstaller.FullName -Wait -PassThru -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$uninstallLog`""
)
if ($process.ExitCode -ne 0) {
    throw "удаление завершилось с кодом $($process.ExitCode), журнал: $uninstallLog"
}
Wait-For { -not (Test-Path $dir) } "каталог $dir удалён"
Write-Host "  каталог $dir удалён"
if (Test-Path $shortcut) { throw "ярлык остался: $shortcut" }
Write-Host '  ярлык удалён'

Write-Step 'Готово'
Write-Host 'Установка, запуск программ, служба и удаление работают.'
