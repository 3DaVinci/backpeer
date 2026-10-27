#!/bin/sh
# Точка входа образа узла (задача 3.10.1; docs/ops/node.md, раздел «Docker»).
# Без аргументов: ключи узла, сертификат, `node run`. С аргументами —
# команда `node` с ними (`node init --json`, `node --version`).
set -eu

if [ "$#" -gt 0 ]; then
  exec node "$@"
fi

# Открытые ключи подписанта из файла (стенд: подписант пишет его при
# запуске), если не заданы списком.
if [ -z "${FS_NODE_COORDINATOR_KEYS:-}" ] && [ -n "${FS_NODE_COORDINATOR_KEYS_FILE:-}" ]; then
  FS_NODE_COORDINATOR_KEYS=$(tr -s '[:space:]' ',' <"$FS_NODE_COORDINATOR_KEYS_FILE")
  export FS_NODE_COORDINATOR_KEYS
fi
unset FS_NODE_COORDINATOR_KEYS_FILE

node init --json
if [ -n "${FS_NODE_CERT_FILE:-}" ]; then
  # Сертификат от `cli node-cert` владельца, смонтированный в контейнер.
  node import-cert "$FS_NODE_CERT_FILE"
elif [ "${FS_NODE_STAND_CERT:-}" = 1 ]; then
  # Только стенд: сертификат от новой случайной учётной записи.
  node stand-cert
fi
unset FS_NODE_CERT_FILE FS_NODE_STAND_CERT

exec node run
