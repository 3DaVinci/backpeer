#!/bin/sh
# Сборка cli на чистой машине (критерий 1.7.3): папка копируется в
# контейнеры без Dart и без libsodium в системе, там выполняется
# tool/smoke_test.sh. Нужен Docker. Запуск:
#
#   tool/smoke_clean.sh build/bin/linux-x64/cli/bundle [образ...]
#
# По умолчанию — debian:12-slim и ubuntu:22.04 (glibc 2.36 и 2.35; минимум
# для сборки — glibc 2.34, docs/cli.md).
set -eu
bundle=$(cd "$1" && pwd)
shift
images=${*:-debian:12-slim ubuntu:22.04}
here=$(cd "$(dirname "$0")" && pwd)
# В контейнер — только сам скрипт: docker cp копирует каталог целиком.
scripts=$(mktemp -d)
trap 'rm -rf "$scripts"' EXIT
cp "$here/smoke_test.sh" "$scripts/"
for image in $images; do
  echo "=== $image"
  container=$(docker create "$image" /smoke/smoke_test.sh /bundle)
  docker cp "$bundle" "$container:/bundle"
  docker cp "$scripts" "$container:/smoke"
  if docker start -a "$container"; then
    docker rm "$container" > /dev/null
  else
    docker rm "$container" > /dev/null
    echo "=== $image: ошибка" >&2
    exit 1
  fi
done
