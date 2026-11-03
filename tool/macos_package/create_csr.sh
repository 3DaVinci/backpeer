#!/bin/bash
# Запрос сертификата Developer ID Application (задача 5.7.2, П-3):
#
#   tool/macos_package/create_csr.sh <почта Apple ID> [каталог]
#
# Готовит закрытый ключ и запрос на сертификат (CSR) для
# developer.apple.com → Certificates → + → Developer ID Application.
# Закрытый ключ остаётся на машине подписи: каталог по умолчанию —
# build/signing (в git не попадает), права 0600. Ключ и CSR в git не
# коммитятся; после выпуска сертификата его ставят в связку ключей
# (docs/ops/macos-packages.md, раздел «Сертификат Developer ID»).
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Использование: create_csr.sh <почта Apple ID> [каталог]" >&2
  exit 2
fi

email=$1
dir="${2:-build/signing}"
mkdir -p "$dir"
chmod 700 "$dir"
key="$dir/DeveloperID.key"
csr="$dir/DeveloperID.csr"
umask 077

if [ -e "$key" ] || [ -e "$csr" ]; then
  echo "Уже есть $key или $csr — удалите их, если нужен новый ключ." >&2
  exit 1
fi

openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$key" \
  -out "$csr" \
  -subj "/CN=Backpeer Developer ID/emailAddress=$email" >/dev/null

echo "Закрытый ключ: $key"
echo "Запрос: $csr"
echo
echo "Дальше:"
echo "  1. developer.apple.com → Certificates, Identifiers & Profiles → Certificates → +"
echo "  2. G2 Sub-CA (Xcode 11 or later) → Developer ID Application → загрузить $csr"
echo "  3. Скачать .cer и поставить в связку ключей вместе с ключом:"
echo "     docs/ops/macos-packages.md, раздел «Сертификат Developer ID»"
