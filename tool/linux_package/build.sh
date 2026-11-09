#!/bin/bash
# Пакеты Linux — AppImage, .deb и .rpm (задача 5.7.3, docs/ops/linux-packages.md):
#
#   tool/linux_package/build.sh                 # build/packages/
#   SIGN_KEY=<id> GNUPGHOME=... tool/linux_package/build.sh   # с подписью
#
# Собирает в контейнере Ubuntu 22.04 (Dockerfile.build) из копии рабочего
# дерева (git ls-files: отслеживаемые и новые файлы без игнорируемых), чтобы
# кеши сборки хоста не попали в пакет. Flutter — из .fvm/flutter_sdk, пакеты
# pub — из кеша хоста. Архитектура — как у хоста (x64; arm64 — на раннере
# ARM64, 0.2.x).
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
image=backpeer-linux-build:22.04
version="$(sed -n 's/^version:[[:space:]]*//p' packages/cli/pubspec.yaml)"
commit="${CI_COMMIT_SHORT_SHA:-$(git rev-parse --short HEAD)}"
out="$root/build/packages"
pub_cache="${PUB_CACHE:-$HOME/.pub-cache}"
flutter_sdk="$(readlink -f .fvm/flutter_sdk)"

docker build -q -t "$image" -f tool/linux_package/Dockerfile.build tool/linux_package >/dev/null
rm -rf "$out"
mkdir -p "$out"

gpg_args=()
if [ -n "${SIGN_KEY:-}" ]; then
  gpg_args=(-v "${GNUPGHOME:-$HOME/.gnupg}:/work/gnupg" -e GNUPGHOME=/work/gnupg -e SIGN_KEY)
fi

git ls-files -z --cached --others --exclude-standard \
  | tar --null -T - -cf - \
  | docker run --rm -i --user "$(id -u):$(id -g)" \
      -v "$flutter_sdk:/flutter" -v "$pub_cache:/pub-cache" -v "$out:/out" \
      -e VERSION="$version" -e COMMIT="$commit" \
      -e UPDATE_PUBLIC_KEY="${UPDATE_PUBLIC_KEY:-}" \
      -e UPDATE_BASE_URL="${UPDATE_BASE_URL:-}" "${gpg_args[@]}" \
      "$image" bash -c 'tar -xf - -C /src && exec /src/tool/linux_package/inside.sh'
echo "Пакеты: $out"
