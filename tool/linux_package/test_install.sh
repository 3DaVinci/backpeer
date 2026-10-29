#!/bin/bash
# Проверка пакетов из build/packages в чистых контейнерах систем из
# docs/mvp-scope.md (задача 5.7.3): зависимости ставятся менеджером
# пакетов, программы запускаются, все библиотеки приложения находятся,
# агент работает от обычного пользователя, удаление не оставляет файлов
# пакета. AppImage — на Ubuntu 22.04 без FUSE (распаковкой).
#
#   tool/linux_package/test_install.sh [ubuntu:22.04 debian:12 fedora:40]
#
# Перезагрузку с бэкапом по расписанию в контейнере не проверить: нужен
# systemd с сеансом пользователя (docs/ops/linux-packages.md, «Проверка»).
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
packages="$root/build/packages"
images=("$@")
[ ${#images[@]} -gt 0 ] || images=(ubuntu:22.04 debian:12 fedora:40)

# Общая часть: программы, библиотеки, агент от пользователя, удаление.
check='
set -eu
for p in backpeer-cli backpeer-agent; do "$p" --version; done
/opt/backpeer/daemons/node/bin/node --version
missing="$(ldd /opt/backpeer/backpeer | grep "not found" || true)"
[ -z "$missing" ] || { echo "нет библиотек: $missing"; exit 1; }
test -f /usr/share/applications/org.backpeer.app.desktop
test -f /usr/share/icons/hicolor/256x256/apps/backpeer.png
test -f /usr/share/metainfo/org.backpeer.app.metainfo.xml
useradd -m tester
su tester -c "
  export FS_HOME=/home/tester/fs FS_AGENT_SECRETS=none FS_AGENT_NOTIFY=none \
         FS_AGENT_POWER=none FS_SERVICES=none
  backpeer-agent run --log /home/tester/agent.log &
  for i in \$(seq 50); do backpeer-agent status >/dev/null 2>&1 && break; sleep 0.2; done
  backpeer-agent status | grep -q \"\\\"status\\\": \\\"idle\\\"\"
  backpeer-agent stop >/dev/null
  wait
"
echo "агент от пользователя: ок"
'

for image in "${images[@]}"; do
  echo "=== $image"
  case "$image" in
    fedora:*)
      pkg="$(ls "$packages"/*.rpm | head -1)"
      # В образе fedora нет su и useradd.
      install="dnf install -y -q util-linux shadow-utils /pkg/$(basename "$pkg") >/dev/null"
      remove="dnf remove -y -q backpeer >/dev/null"
      ;;
    *)
      pkg="$(ls "$packages"/*.deb | head -1)"
      install="apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq /pkg/$(basename "$pkg") >/dev/null"
      remove="DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq backpeer >/dev/null"
      ;;
  esac
  docker run --rm -v "$packages:/pkg:ro" "$image" bash -c "
    set -eu
    $install
    $check
    $remove
    test ! -e /opt/backpeer && test ! -e /usr/bin/backpeer-cli
    echo 'удаление: ок'
  "
done

appimage="$(ls "$packages"/*.AppImage | head -1)"
echo "=== AppImage на ubuntu:22.04"
docker run --rm -v "$packages:/pkg:ro" ubuntu:22.04 bash -c "
  set -eu
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    libgtk-3-0 libsecret-1-0 >/dev/null
  cp /pkg/$(basename "$appimage") /tmp/app.AppImage
  cd /tmp && ./app.AppImage --appimage-extract >/dev/null
  squashfs-root/AppRun cli --version
  squashfs-root/AppRun agent --version
  missing=\"\$(ldd squashfs-root/backpeer | grep 'not found' || true)\"
  [ -z \"\$missing\" ] || { echo \"нет библиотек: \$missing\"; exit 1; }
  echo 'AppImage: ок'
"
