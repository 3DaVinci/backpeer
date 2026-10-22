#!/bin/sh
# Полный цикл собранного cli (задача 1.7.3): recover → backup → restore →
# verify --full, со сравнением восстановленных файлов. Запуск:
#
#   tool/smoke_test.sh build/bin/linux-x64/cli/bundle
#
# Нужны только sh, head, cmp, cut. Работает на Linux и macOS; для Windows —
# tool/smoke_test.ps1. Пароль — FS_PASSWORD, Argon2id с настоящими
# параметрами.
set -eu
bundle=$(cd "$1" && pwd)
cli="$bundle/bin/cli"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export FS_HOME="$work/home"
export FS_PASSWORD='correct horse battery staple'
export FS_PHRASE='abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art'

mkdir -p "$work/data/sub"
head -c 20000000 /dev/urandom > "$work/data/random.bin"
echo 'привет' > "$work/data/sub/text.txt"

"$cli" --version
"$cli" recover
"$cli" backup "$work/data"
id=$("$cli" snapshots | cut -c1-12)
"$cli" restore "$id" --to "$work/out"
cmp "$work/data/random.bin" "$work/out$work/data/random.bin"
cmp "$work/data/sub/text.txt" "$work/out$work/data/sub/text.txt"
"$cli" verify --full
echo 'smoke: OK'
