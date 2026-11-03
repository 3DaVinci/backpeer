#!/bin/bash
# Приложение для macOS: Backpeer.app с программами внутри и .dmg (задачи 0.2.5,
# 5.7.2). Запуск на Mac с Xcode и Flutter из .fvm/flutter_sdk:
#
#   tool/macos_package/build.sh                    # build/packages/, подпись ad-hoc
#   SIGN_IDENTITY="Developer ID Application: …" tool/macos_package/build.sh
#   SIGN_IDENTITY="Developer ID Application: …" \
#     NOTARY_PROFILE=backpeer tool/macos_package/build.sh   # + нотаризация
#
# CODE_SIGN_TS=0 — подписать без отметки времени (сеть не пускает к
# timestamp.apple.com; для нотаризации такая подпись не годится).
#
# Что делает:
#   1. собирает программы агента, хранителя и CLI (tool/build_exe.dart);
#   2. собирает приложение (flutter build macos --release);
#   3. кладёт программы внутрь .app — туда, где их ищет DaemonBundle
#      (Contents/MacOS/daemons/<программа>/bin/<программа>);
#   4. проверяет, что все Mach-O собраны под архитектуру машины: кросс-сборки
#      нет, build hook пакета sodium молча собирает libsodium под хост
#      (docs/benchmarks.md);
#   5. подписывает изнутри наружу: библиотеки, программы, .framework, затем
#      само приложение (hardened runtime, отметка времени, entitlements из
#      Release.entitlements — без App Sandbox, ADR-012);
#   6. собирает .dmg со ссылкой на /Applications;
#   7. с NOTARY_PROFILE — отправляет .dmg в notarytool, ждёт решения,
#      прикрепляет билет (stapler) и проверяет Gatekeeper на смонтированном
#      образе;
#   8. пишет SHA256SUMS.
#
# Ключи подписи и профиль notarytool — только на машине подписи, не на
# машинах общего назначения (П-3, 5.7.4). Профиль создаётся один раз:
#
#   xcrun notarytool store-credentials backpeer --apple-id … --team-id … \
#     --password <пароль приложения>
#
# Подпись ad-hoc (`-`, по умолчанию) годится только для своей проверки:
# Gatekeeper такие сборки не пропускает.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

export PATH="$root/.fvm/flutter_sdk/bin:$PATH"
flutter config --no-analytics >/dev/null 2>&1 || true

version="$(sed -n 's/^version:[[:space:]]*//p' packages/cli/pubspec.yaml)"
commit="${CI_COMMIT_SHORT_SHA:-$(git rev-parse --short HEAD)}"

# Сертификат: SIGN_IDENTITY, иначе первый Developer ID Application из связки
# ключей, иначе ad-hoc. Developer ID нужен, чтобы Gatekeeper пропустил .dmg
# на чужой машине (после нотаризации, docs/ops/macos-packages.md).
developer_id() {
  security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application: [^"]*\)"/\1/p' | head -1
}
if [ -n "${SIGN_IDENTITY:-}" ]; then
  identity="$SIGN_IDENTITY"
elif [ -n "$(developer_id)" ]; then
  identity="$(developer_id)"
  echo "SIGN_IDENTITY не задан — взята «$identity» из связки ключей."
else
  identity="-"
fi
case "$identity" in
  "-") ;;
  "Developer ID Application:"*) ;;
  *)
    echo "Внимание: «$identity» — не Developer ID Application. Gatekeeper на" >&2
    echo "чужой машине такую сборку не пропустит (docs/ops/macos-packages.md)." >&2
    ;;
esac
case "$(uname -m)" in
  arm64) arch=arm64 ;;
  x86_64) arch=x64 ;;
  *)
    echo "Неизвестная архитектура: $(uname -m)" >&2
    exit 1
    ;;
esac

out="$root/build/packages"
app="$root/apps/app/build/macos/Build/Products/Release/Backpeer.app"
entitlements="$root/apps/app/macos/Runner/Release.entitlements"
dmg="$out/Backpeer-$version-macos-$arch.dmg"

echo "macOS: версия $version ($commit), архитектура $arch, подпись: $identity"
rm -rf "$out"
mkdir -p "$out"

# --- 1. Программы: папка «бинарник + lib/» на каждую ----------------------
dart run tool/build_exe.dart

# --- 2. Приложение ---------------------------------------------------------
(cd apps/app && flutter build macos --release)

# --- 3. Раскладка внутри .app ---------------------------------------------
# DaemonBundle.executable ищет <программа>/bin/<программа> и
# <программа>/bundle/bin/<программа> рядом с исполняемым файлом приложения.
mkdir -p "$app/Contents/MacOS/daemons"
for program in agent node cli; do
  rm -rf "$app/Contents/MacOS/daemons/$program"
  mkdir -p "$app/Contents/MacOS/daemons/$program"
  cp -a "build/bin/macos-$arch/$program/bundle/." \
    "$app/Contents/MacOS/daemons/$program/"
done

# --- 4. Архитектура Mach-O -------------------------------------------------
# Программы собираются только под архитектуру хоста: кросс-сборки под macOS
# нет, build hook пакета sodium молча собрал бы libsodium под хост
# (docs/benchmarks.md). Приложение Flutter при этом universal (x86_64 и
# arm64), поэтому у каждого Mach-O проверяется наличие архитектуры хоста, а
# не точное совпадение: .dmg выпускается для той архитектуры, на которой
# собран.
check_arch() {
  local file=$1 want=$2
  local archs
  archs="$(lipo -archs "$file" 2>/dev/null || true)"
  case " $archs " in
    *" $want "*) ;;
    *)
      echo "Не та архитектура: $file ($archs, нужна $want)" >&2
      exit 1
      ;;
  esac
}

machos() {
  find "$1" -type f | while IFS= read -r file; do
    if file -b "$file" | grep -q 'Mach-O'; then printf '%s\n' "$file"; fi
  done
}

while IFS= read -r file; do
  check_arch "$file" "$arch"
done < <(machos "$app")

# --- 5. Подпись изнутри наружу --------------------------------------------
# Отметка времени нужна для нотаризации: без неё подпись действительна,
# только пока действует сертификат. Служба timestamp.apple.com из
# корпоративной сети иногда недоступна, поэтому попыток несколько.
# CODE_SIGN_TS=0 — без отметки времени (для проверки на своей машине;
# нотаризация такую подпись не примет).
ts_args=(--timestamp)
if [ "${CODE_SIGN_TS:-1}" = "0" ]; then
  ts_args=()
fi

sign() {
  if [ "$identity" = "-" ]; then
    codesign --force --sign - "$@" >/dev/null
    return
  fi
  local attempt
  for attempt in 1 2 3; do
    if codesign --force --options runtime "${ts_args[@]}" \
        --sign "$identity" "$@" >/dev/null 2>&1; then
      return
    fi
    echo "Подпись не удалась (попытка $attempt из 3): $*" >&2
    sleep 2
  done
  codesign --force --options runtime "${ts_args[@]}" --sign "$identity" "$@"
}

if [ -n "$(find "$app/Contents/Frameworks" -maxdepth 1 -name '*.framework' \
  2>/dev/null)" ]; then
  sign "$app/Contents/Frameworks/"*.framework
fi
# Сначала библиотеки, потом программы: Mach-O внутри .app подписываются
# каждый отдельно, иначе hardened runtime не даст их загрузить.
while IFS= read -r file; do
  case "$file" in
    *.dylib) sign "$file" ;;
  esac
done < <(machos "$app/Contents/MacOS/daemons")
while IFS= read -r file; do
  case "$file" in
    */bin/*) sign "$file" ;;
  esac
done < <(machos "$app/Contents/MacOS/daemons")
sign --entitlements "$entitlements" "$app"

echo "Подпись:"
codesign --verify --strict --verbose=1 "$app"
if [ "$identity" != "-" ]; then
  codesign -dv --verbose=2 "$app" 2>&1 | sed -n 's/^/  /p'
fi

# --- 6. .dmg ---------------------------------------------------------------
stage="$out/dmg"
mkdir -p "$stage"
cp -a "$app" "$stage/"
ln -sfn /Applications "$stage/Applications"
hdiutil create -quiet -volname "Backpeer" -srcfolder "$stage" -ov \
  -format UDZO "$dmg"
rm -rf "$stage"

# --- 7. Нотаризация --------------------------------------------------------
if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "Нотаризация ($NOTARY_PROFILE)…"
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  mount="$(mktemp -d "/tmp/backpeer-dmg.XXXXXX")"
  trap 'hdiutil detach -quiet "$mount" 2>/dev/null || true; rmdir "$mount" 2>/dev/null || true' EXIT
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$dmg"
  spctl --assess --type execute --verbose=4 "$mount/Backpeer.app"
  hdiutil detach -quiet "$mount"
  rmdir "$mount"
  trap - EXIT
else
  echo "Нотаризация пропущена: не задан NOTARY_PROFILE."
  echo "Такую сборку Gatekeeper на чужой машине не пропустит (5.7.2)."
fi

# --- 8. Контрольные суммы --------------------------------------------------
(cd "$out" && shasum -a 256 "$(basename "$dmg")" > SHA256SUMS)

echo "Готово:"
echo "  $app"
echo "  $dmg"
echo "  $out/SHA256SUMS"
