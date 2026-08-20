#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-3.0.0}"
deb_arch="${2:-$(dpkg --print-architecture)}"
appimagetool="${3:-}"
bundle="$root/release/NDM2-$version-linux-$deb_arch"
release_dir="$root/release"

case "$deb_arch" in
  amd64) rpm_arch="x86_64"; appimage_arch="x86_64" ;;
  arm64) rpm_arch="aarch64"; appimage_arch="aarch64" ;;
  *) echo "Unsupported Linux package architecture: $deb_arch" >&2; exit 1 ;;
esac

if [[ ! -x "$bundle/bin/NDM2" || ! -x "$bundle/bin/nova-core" || ! -x "$bundle/start-nova-core.sh" ]]; then
  echo "Prepared NDM2 + NOVA Core bundle is incomplete: $bundle" >&2
  exit 1
fi

work_dir="$root/package-linux-formats"
rm -rf "$work_dir"
mkdir -p "$work_dir"

# AppImage: repackage the tested portable bundle into the documented AppDir
# shape. The complete Qt runtime and NOVA Core remain inside usr/.
appdir="$work_dir/NDM2.AppDir"
mkdir -p "$appdir/usr"
cp -a "$bundle/." "$appdir/usr/"
cp "$bundle/share/applications/ndm2.desktop" "$appdir/ndm2.desktop"
cp "$bundle/share/icons/hicolor/512x512/apps/ndm2.png" "$appdir/ndm2.png"
cat > "$appdir/AppRun" <<'APPRUN'
#!/usr/bin/env sh
set -eu
root="${APPDIR:?APPDIR must be set by AppImage}"
exec "$root/usr/ndm2" "$@"
APPRUN
chmod 0755 "$appdir/AppRun"

if [[ -z "$appimagetool" || ! -x "$appimagetool" ]]; then
  echo "A matching appimagetool binary is required to create the AppImage." >&2
  exit 1
fi
ARCH="$appimage_arch" "$appimagetool" --no-appstream "$appdir" "$release_dir/NDM2-$version-linux-$deb_arch.AppImage"

# Debian package: retain the full portable runtime under /opt and expose the
# same two launchers system-wide without replacing any distribution libraries.
deb_root="$work_dir/deb-root"
mkdir -p "$deb_root/DEBIAN" "$deb_root/opt/ndm2" "$deb_root/usr/bin" "$deb_root/usr/share/applications"
cp -a "$bundle/." "$deb_root/opt/ndm2/"
ln -s ../../opt/ndm2/ndm2 "$deb_root/usr/bin/ndm2"
ln -s ../../opt/ndm2/start-nova-core.sh "$deb_root/usr/bin/nova-core"
ln -s ../../../opt/ndm2/share/applications/ndm2.desktop "$deb_root/usr/share/applications/ndm2.desktop"
cat > "$deb_root/DEBIAN/control" <<EOF
Package: ndm2
Version: $version
Section: net
Priority: optional
Architecture: $deb_arch
Maintainer: NOVA Download Manager
Depends: libc6, libgl1, libx11-6, libxkbcommon0
Description: NOVA Download Manager native Qt client and authenticated loopback Core
 NDM2 ships its Qt runtime and a platform-matched NOVA Core under /opt/ndm2.
EOF
dpkg-deb --root-owner-group --build "$deb_root" "$release_dir/NDM2-$version-linux-$deb_arch.deb"

# RPM package: mirror the same relocatable /opt payload and public launchers.
rpm_top="$work_dir/rpm"
mkdir -p "$rpm_top/BUILD" "$rpm_top/BUILDROOT" "$rpm_top/RPMS/$rpm_arch" "$rpm_top/SOURCES" "$rpm_top/SPECS" "$rpm_top/SRPMS"
cat > "$rpm_top/SPECS/ndm2.spec" <<EOF
Name: ndm2
Version: $version
Release: 1%{?dist}
Summary: NOVA Download Manager native Qt client and Core
License: Proprietary
BuildArch: $rpm_arch

%description
Native NDM2 client with its matching authenticated loopback NOVA Core.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/opt/ndm2 %{buildroot}/usr/bin %{buildroot}/usr/share/applications
cp -a $bundle/. %{buildroot}/opt/ndm2/
ln -s ../../opt/ndm2/ndm2 %{buildroot}/usr/bin/ndm2
ln -s ../../opt/ndm2/start-nova-core.sh %{buildroot}/usr/bin/nova-core
ln -s ../../../opt/ndm2/share/applications/ndm2.desktop %{buildroot}/usr/share/applications/ndm2.desktop

%files
/opt/ndm2
/usr/bin/ndm2
/usr/bin/nova-core
/usr/share/applications/ndm2.desktop
EOF
rpmbuild --define "_topdir $rpm_top" -bb "$rpm_top/SPECS/ndm2.spec"
cp "$rpm_top/RPMS/$rpm_arch/ndm2-$version-1.$rpm_arch.rpm" "$release_dir/NDM2-$version-linux-$deb_arch.rpm"

printf 'appimage=%s\ndeb=%s\nrpm=%s\n' \
  "$release_dir/NDM2-$version-linux-$deb_arch.AppImage" \
  "$release_dir/NDM2-$version-linux-$deb_arch.deb" \
  "$release_dir/NDM2-$version-linux-$deb_arch.rpm"
