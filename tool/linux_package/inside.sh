#!/bin/bash
# Сборка пакетов внутри контейнера Dockerfile.build (задача 5.7.3); запускает
# build.sh. Исходники — в /src (копия рабочего дерева), Flutter — /flutter,
# кеш pub — /pub-cache, результат — /out.
#
# Переменные: VERSION, COMMIT; SIGN_KEY — id ключа GPG для подписи (ключи
# — в GNUPGHOME, смонтированном только на машине подписи, П-3).
set -euo pipefail

export PATH=/flutter/bin:$PATH
export HOME=/work/home PUB_CACHE=/pub-cache
mkdir -p "$HOME"
git config --global --add safe.directory '*'

: "${VERSION:?}" "${COMMIT:?}"
case "$(uname -m)" in
  x86_64) arch=x64 deb_arch=amd64 rpm_arch=x86_64 appimage_arch=x86_64 ;;
  aarch64) arch=arm64 deb_arch=arm64 rpm_arch=aarch64 appimage_arch=aarch64 ;;
esac
id=org.file_storage.app
here=/src/tool/linux_package

cd /src
# Версия и коммит в приложении, как tool/build_exe.dart делает для
# программ: от версии зависит копия программ AppImage (PersistentDaemons).
sed -i -e "s/buildAppVersion = 'dev'/buildAppVersion = '$VERSION'/" \
  -e "s/buildGitCommit = 'unknown'/buildGitCommit = '$COMMIT'/" \
  packages/core/lib/src/build_info_values.dart
flutter config --no-analytics >/dev/null
flutter pub get --offline >/dev/null 2>&1 || flutter pub get
(cd apps/app && flutter build linux --release)
CI_COMMIT_SHORT_SHA="$COMMIT" dart run tool/build_exe.dart

# --- Раскладка: /opt/file-storage и файлы рабочего стола ---------------
stage=/work/stage
rm -rf "$stage"
opt="$stage/opt/file-storage"
mkdir -p "$opt/daemons" "$stage/usr/bin" "$stage/usr/share/applications" \
  "$stage/usr/share/metainfo"
cp -a "apps/app/build/linux/$arch/release/bundle/." "$opt/"
for p in agent node cli; do
  mkdir -p "$opt/daemons/$p"
  cp -a "build/bin/linux-$arch/$p/bundle/." "$opt/daemons/$p/"
done
ln -s /opt/file-storage/file-storage "$stage/usr/bin/file-storage"
ln -s /opt/file-storage/daemons/cli/bin/cli "$stage/usr/bin/file-storage-cli"
ln -s /opt/file-storage/daemons/agent/bin/agent "$stage/usr/bin/file-storage-agent"
cp "$here/$id.desktop" "$stage/usr/share/applications/"
sed -e "s/@VERSION@/$VERSION/" -e "s/@DATE@/$(date -u +%F)/" \
  "$here/$id.metainfo.xml" > "$stage/usr/share/metainfo/$id.metainfo.xml"
icons=apps/app/linux/icons
for size in 16 24 32 48 64 128 256 512; do
  dir="$stage/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  cp "$icons/file-storage-$size.png" "$dir/file-storage.png"
done
mkdir -p "$stage/usr/share/icons/hicolor/scalable/apps"
cp "$icons/file-storage.svg" "$stage/usr/share/icons/hicolor/scalable/apps/"

desktop-file-validate "$stage/usr/share/applications/$id.desktop"
appstreamcli validate --no-net --pedantic \
  "$stage/usr/share/metainfo/$id.metainfo.xml" || \
  appstreamcli validate --no-net "$stage/usr/share/metainfo/$id.metainfo.xml"

name="file-storage_${VERSION}"
mkdir -p /out

# --- .deb ----------------------------------------------------------------
deb=/work/deb
rm -rf "$deb"
cp -a "$stage" "$deb"
mkdir -p "$deb/DEBIAN"
cat > "$deb/DEBIAN/control" <<CONTROL
Package: file-storage
Version: $VERSION
Architecture: $deb_arch
Maintainer: File Storage <packages@file-storage.invalid>
Installed-Size: $(du -sk "$stage" | cut -f1)
Depends: libgtk-3-0, libsecret-1-0, libglib2.0-0
Recommends: libayatana-appindicator3-1 | libappindicator3-1, libglib2.0-bin, systemd
Section: utils
Priority: optional
Description: Encrypted backups on other people's computers
 Back up important files in encrypted form to computers of other users
 and give your own free disk space in return. Files are encrypted on your
 computer; scheduled backups run in the background.
CONTROL
install -m 0755 "$here/deb/postinst" "$here/deb/prerm" "$deb/DEBIAN/"
fakeroot dpkg-deb --build -Zxz "$deb" "/out/${name}_${deb_arch}.deb"

# --- .rpm ----------------------------------------------------------------
rpmtop=/work/rpmbuild
rm -rf "$rpmtop"
mkdir -p "$rpmtop/SPECS"
sed -e "s|@VERSION@|$VERSION|" -e "s|@RPM_ARCH@|$rpm_arch|" \
  -e "s|@STAGE@|$stage|" "$here/rpm/file-storage.spec.in" \
  > "$rpmtop/SPECS/file-storage.spec"
rpmbuild -bb --define "_topdir $rpmtop" --target "$rpm_arch" \
  "$rpmtop/SPECS/file-storage.spec" >/dev/null
cp "$rpmtop/RPMS/$rpm_arch/"*.rpm "/out/file-storage-${VERSION}-1.${rpm_arch}.rpm"

# --- AppImage ------------------------------------------------------------
appdir=/work/AppDir
rm -rf "$appdir"
cp -a "$opt" "$appdir"
install -m 0755 "$here/AppRun" "$appdir/AppRun"
cp "$here/$id.desktop" "$appdir/$id.desktop"
cp "$icons/file-storage-256.png" "$appdir/file-storage.png"
mkdir -p "$appdir/usr/share/metainfo"
cp "$stage/usr/share/metainfo/$id.metainfo.xml" "$appdir/usr/share/metainfo/"
sign_args=()
if [ -n "${SIGN_KEY:-}" ]; then sign_args=(--sign --sign-key "$SIGN_KEY"); fi
ARCH="$appimage_arch" appimagetool --no-appstream "${sign_args[@]}" "$appdir" \
  "/out/File_Storage-${VERSION}-${appimage_arch}.AppImage"

# --- Подпись -------------------------------------------------------------
cd /out
if [ -n "${SIGN_KEY:-}" ]; then
  rpm --define "_gpg_name $SIGN_KEY" --addsign ./*.rpm
fi
sha256sum ./*.deb ./*.rpm ./*.AppImage > SHA256SUMS
if [ -n "${SIGN_KEY:-}" ]; then
  gpg --batch --yes --local-user "$SIGN_KEY" --armor --detach-sign SHA256SUMS
  for f in ./*.deb; do
    gpg --batch --yes --local-user "$SIGN_KEY" --armor --detach-sign "$f"
  done
fi
ls -l /out
