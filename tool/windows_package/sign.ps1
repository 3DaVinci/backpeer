<#
.SYNOPSIS
    Подпись Authenticode для сборки Windows (задача 5.7.1).

.DESCRIPTION
    Подписывает .exe и .dll (signtool), ставит отметку времени и проверяет
    подпись. Ключ берётся из хранилища сертификатов (токен или облачный HSM,
    установленный на машине подписи), из .pfx (сертификаты, выпущенные до
    июня 2023, и тестовые) или через dlib облачного HSM. Один из способов
    должен быть задан.

    Ключи подписи держат на машине подписи, а не на раннерах общего
    назначения (П-3, задача 5.7.4). Как получить сертификат —
    docs/ops/windows-signing.md.

.EXAMPLE
    pwsh -File tool/windows_package/sign.ps1 -Path build\packages\windows\stage -Thumbprint 1A2B…
    # сертификат с токена в хранилище пользователя, отметка времени DigiCert

.EXAMPLE
    $env:SIGN_PFX_PASSWORD = '…'
    pwsh -File tool/windows_package/sign.ps1 -Path build\packages\*.exe -Pfx build\signing\backpeer.pfx
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    # Файлы или каталоги (.exe и .dll обходятся рекурсивно).
    [Parameter(Mandatory = $true)]
    [string[]] $Path,
    # Отпечаток сертификата в хранилище (токен, eToken, облачный HSM).
    [string] $Thumbprint,
    # Сертификат в хранилище машины (LocalMachine), а не пользователя.
    [switch] $MachineStore,
    # Файл .pfx; пароль — -PfxPassword или SIGN_PFX_PASSWORD.
    [string] $Pfx,
    [string] $PfxPassword,
    # Облачный HSM: dlib и необязательные метаданные (DigiCert KeyLocker,
    # Azure Artifact Signing). См. docs/ops/windows-signing.md.
    [string] $Dlib,
    [string] $Dmdf,
    # Сервер отметки времени RFC 3161.
    [string] $TimestampUrl = 'http://timestamp.digicert.com',
    [switch] $NoTimestamp,
    # Проверить подпись после подписи (signtool verify /pa /all).
    [switch] $Verify,
    # signtool.exe, если Windows SDK не в PATH и не в стандартном месте.
    [string] $SignTool
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step([string] $text) {
    Write-Host ''
    Write-Host "== $text" -ForegroundColor Cyan
}

# --- Способ подписи --------------------------------------------------------

$methods = @()
if ($Thumbprint) { $methods += 'Thumbprint' }
if ($Pfx) { $methods += 'Pfx' }
if ($Dlib) { $methods += 'Dlib' }
if ($methods.Count -ne 1) {
    throw ('Укажите ровно один способ подписи: -Thumbprint (токен), -Pfx ' +
        'или -Dlib (облачный HSM). Подробности — docs/ops/windows-signing.md')
}

if ($Pfx -and -not $PfxPassword) {
    $PfxPassword = $env:SIGN_PFX_PASSWORD
    if (-not $PfxPassword) {
        throw 'Для -Pfx нужен -PfxPassword или переменная SIGN_PFX_PASSWORD'
    }
}

# --- signtool --------------------------------------------------------------

function Find-SignTool([string] $explicit) {
    if ($explicit) {
        if (Test-Path $explicit) { return (Resolve-Path $explicit).Path }
        throw "нет $explicit"
    }
    if ($env:SIGNTOOL -and (Test-Path $env:SIGNTOOL)) { return $env:SIGNTOOL }
    $command = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    # Windows SDK: bin\<версия>\x64\signtool.exe, берём самую свежую версию.
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path $kits) {
        $candidates = Get-ChildItem -Path $kits -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' } |
            Where-Object { Test-Path $_ }
        if ($candidates) { return $candidates[0] }
    }
    throw ('signtool.exe не найден: поставьте Windows SDK (или Build Tools с ' +
        'ним) и добавьте x64\signtool.exe в PATH, либо укажите -SignTool')
}

$signtool = Find-SignTool $SignTool
Write-Host "signtool: $signtool"
if ($Thumbprint) { Write-Host "сертификат: $Thumbprint" }
elseif ($Pfx) { Write-Host "сертификат: $Pfx" }
else { Write-Host "сертификат: облачный HSM ($Dlib)" }

# --- Файлы -----------------------------------------------------------------

$files = @()
foreach ($item in $Path) {
    if (-not (Test-Path $item)) { throw "нет $item" }
    $resolved = Resolve-Path $item
    foreach ($entry in $resolved) {
        $info = Get-Item $entry.Path
        if ($info.PSIsContainer) {
            $files += Get-ChildItem -Path $info.FullName -Recurse -File |
                Where-Object { $_.Extension -in @('.exe', '.dll') } |
                ForEach-Object { $_.FullName }
        }
        elseif ($info.Extension -in @('.exe', '.dll')) {
            $files += $info.FullName
        }
    }
}
$files = @($files | Sort-Object -Unique)
if ($files.Count -eq 0) { throw 'нечего подписывать: нет .exe и .dll' }
Write-Step "Подпись: файлов $($files.Count)"

function Sign-File([string] $file) {
    $arguments = @('sign', '/fd', 'sha256')
    if ($Thumbprint) {
        $arguments += @('/sha1', $Thumbprint)
        if ($MachineStore) { $arguments += '/sm' }
    }
    elseif ($Pfx) {
        $arguments += @('/f', $Pfx, '/p', $PfxPassword)
    }
    else {
        $arguments += @('/dlib', $Dlib)
        if ($Dmdf) { $arguments += @('/dmdf', $Dmdf) }
    }
    if (-not $NoTimestamp -and $TimestampUrl) {
        $arguments += @('/tr', $TimestampUrl, '/td', 'sha256')
    }
    $arguments += @('/v', $file)

    $attempt = 0
    while ($true) {
        $attempt++
        & $signtool @arguments
        if ($LASTEXITCODE -eq 0) { return }
        # Сервер отметки времени иногда недоступен — несколько попыток.
        if ($attempt -ge 3) { throw "signtool не подписал $file (код $LASTEXITCODE)" }
        Write-Warning "подпись не удалась, попытка $attempt из 3: $file"
        Start-Sleep -Seconds 3
    }
}

$first = $null
foreach ($file in $files) {
    if (-not $first) { $first = $file }
    Write-Host ("  $file")
    Sign-File $file
}

$signature = Get-AuthenticodeSignature -FilePath $first
if ($signature -and $signature.SignerCertificate) {
    Write-Host ''
    Write-Host ("Подписал: {0}" -f $signature.SignerCertificate.Subject)
    Write-Host ("Действителен до: {0}" -f $signature.SignerCertificate.NotAfter)
}

if ($Verify) {
    Write-Step 'Проверка подписи (signtool verify /pa /all)'
    foreach ($file in $files) {
        & $signtool @('verify', '/pa', '/all', '/q', $file)
        if ($LASTEXITCODE -ne 0) { throw "подпись не проверяется: $file" }
    }
    Write-Host "Подпись проверена: файлов $($files.Count)"
}
