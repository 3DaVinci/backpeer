#!/bin/sh
# Точка входа образа relay (задача 4.6.1). Без аргументов: открытые ключи
# пропусков из файла стенда (`/stand/keys/pass.pub`, кладёт стенд), затем
# `relay serve`. С аргументами — команда `relay` с ними: этим же образом
# стенд готовит свои ключи (`relay keygen`).
set -eu

if [ "$#" -gt 0 ]; then
  exec relay "$@"
fi

# Ключи пропусков координатора. Стенд: файл вместо списка в настройках
# (docs/ops/relay.md, раздел «Подготовка»).
if [ -z "${FS_RELAY_PASS_KEYS:-}" ] && [ -s /stand/keys/pass.pub ]; then
  FS_RELAY_PASS_KEYS=$(tr -d '[:space:]' </stand/keys/pass.pub)
  export FS_RELAY_PASS_KEYS
fi

exec relay serve
