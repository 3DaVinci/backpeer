# Полный цикл собранного cli на Windows (задача 1.7.3): recover → backup →
# restore → verify --full, со сравнением восстановленных файлов. Запуск:
#
#   powershell -File tool\smoke_test.ps1 build\bin\windows-x64\cli\bundle
$ErrorActionPreference = 'Stop'
$bundle = Resolve-Path $args[0]
$cli = Join-Path $bundle 'bin\cli.exe'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("fs-smoke-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path "$work\data\sub" | Out-Null
try {
  $env:FS_HOME = "$work\home"
  $env:FS_PASSWORD = 'correct horse battery staple'
  $env:FS_PHRASE = (@('abandon') * 23 + 'art') -join ' '
  $bytes = New-Object byte[] 20000000
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  [System.IO.File]::WriteAllBytes("$work\data\random.bin", $bytes)
  Set-Content -Path "$work\data\sub\text.txt" -Value 'привет' -Encoding utf8

  function Run { & $cli @args; if ($LASTEXITCODE -ne 0) { throw "cli ${args}: код $LASTEXITCODE" } }
  Run --version
  Run recover
  Run backup "$work\data"
  $id = (& $cli snapshots).Substring(0, 12)
  Run restore $id --to "$work\out"
  # Корень снимка раскладывается по полному пути без двоеточия: C:\x → C\x.
  $restored = Join-Path "$work\out" ("$work\data" -replace ':', '')
  if ((Get-FileHash "$work\data\random.bin").Hash -ne (Get-FileHash "$restored\random.bin").Hash) { throw 'random.bin не совпал' }
  if ((Get-FileHash "$work\data\sub\text.txt").Hash -ne (Get-FileHash "$restored\sub\text.txt").Hash) { throw 'text.txt не совпал' }
  Run verify --full
  Write-Output 'smoke: OK'
} finally {
  Remove-Item -Recurse -Force $work
}
