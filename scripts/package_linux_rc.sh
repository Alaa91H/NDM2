#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${1:-$root/build-release}"
version="${2:-3.0.0}"
architecture="$(dpkg --print-architecture)"
source_binary="$build_dir/native/NDM2"
release_root="$root/release/NDM2-$version-linux-$architecture"
archive="$root/release/NDM2-$version-linux-$architecture.tar.gz"

if [[ ! -x "$source_binary" ]]; then
    echo "Release binary not found: $source_binary" >&2
    exit 1
fi

rm -rf "$release_root" "$archive"
mkdir -p "$release_root/bin" "$release_root/lib" "$release_root/plugins" "$release_root/qml" "$release_root/share/applications" "$release_root/share/icons/hicolor/512x512/apps"
install -m 0755 "$source_binary" "$release_root/bin/NDM2"
install -m 0644 "$root/branding/source/app-icon.png" "$release_root/share/icons/hicolor/512x512/apps/ndm2.png"

# Bundle only Qt runtime libraries. The supported Linux baseline continues to provide libc,
# graphics drivers, X11/Wayland stack, OpenSSL and other operating-system components.
while IFS= read -r library; do
    [[ -n "$library" ]] || continue
    install -m 0644 -D "$library" "$release_root/lib/$(basename "$library")"
done < <(ldd "$source_binary" | awk '/Qt6/ {print $3}' | sort -u)

qt_plugin_dir="$(qtpaths6 --plugin-dir)"
qt_qml_dir="$(qtpaths6 --query QT_INSTALL_QML)"
for plugin in platforms/libqxcb.so platforms/libqoffscreen.so imageformats/libqico.so imageformats/libqjpeg.so imageformats/libqgif.so imageformats/libqsvg.so; do
    if [[ -f "$qt_plugin_dir/$plugin" ]]; then
        install -m 0644 -D "$qt_plugin_dir/$plugin" "$release_root/plugins/$plugin"
    fi
done

for module in QtQml QtQuick QtQuick.2 QtQuick/Controls QtQuick/Controls/Basic QtQuick/Layouts QtQuick/Templates QtQuick/Window; do
    if [[ -d "$qt_qml_dir/$module" ]]; then
        cp -a "$qt_qml_dir/$module" "$release_root/qml/$(dirname "$module")/"
    fi
done

# QML modules and plugins can load further Qt libraries that are not direct
# dependencies of the executable (for example Quick Controls and OpenGL).
while IFS= read -r library; do
    [[ -n "$library" ]] || continue
    install -m 0644 -D "$library" "$release_root/lib/$(basename "$library")"
done < <(find "$release_root/plugins" "$release_root/qml" -type f -name '*.so' -print0 | xargs -0r ldd | awk '/Qt6/ {print $3}' | sort -u)

cat > "$release_root/bin/qt.conf" <<'QTCONF'
[Paths]
Prefix=..
Libraries=lib
Plugins=plugins
QmlImports=qml
QTCONF

cat > "$release_root/ndm2" <<'LAUNCHER'
#!/usr/bin/env sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export LD_LIBRARY_PATH="$root/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$root/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
export QML2_IMPORT_PATH="$root/qml${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
exec "$root/bin/NDM2" "$@"
LAUNCHER
chmod 0755 "$release_root/ndm2"

cat > "$release_root/share/applications/ndm2.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=NOVA Download Manager
Comment=Native NOVA download manager
Exec=ndm2
Icon=ndm2
Terminal=false
Categories=Network;FileTransfer;
StartupWMClass=NDM2
DESKTOP

cat > "$release_root/install-desktop-shortcut.sh" <<'SHORTCUT'
#!/usr/bin/env sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
desktop="${XDG_DESKTOP_DIR:-}"
if [ -z "$desktop" ] && command -v xdg-user-dir >/dev/null 2>&1; then desktop="$(xdg-user-dir DESKTOP 2>/dev/null || true)"; fi
if [ -z "$desktop" ] || [ "$desktop" = "$HOME" ]; then desktop="$HOME/Desktop"; fi
mkdir -p "$desktop"
desktop_file="$desktop/NOVA Download Manager.desktop"
cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=NOVA Download Manager
Comment=Native NOVA download manager
Exec=$root/ndm2
Icon=$root/share/icons/hicolor/512x512/apps/ndm2.png
Terminal=false
Categories=Network;FileTransfer;
StartupWMClass=NDM2
EOF
chmod 0755 "$desktop_file"
printf 'desktop_shortcut=%s\\n' "$desktop_file"
SHORTCUT
chmod 0755 "$release_root/install-desktop-shortcut.sh"

cat > "$release_root/README.txt" <<EOF
NDM2 $version Linux Release Candidate

This bundle contains the native NDM2 client plus the Qt runtime libraries, XCB platform
plugin, image plugins and Qt Quick QML modules required by this client. Start it with:

  ./ndm2 --daemon-endpoint http://127.0.0.1:3199

To create a desktop shortcut that uses the bundled NOVA icon, run:

  ./install-desktop-shortcut.sh

The NOVA daemon remains a separately managed, authenticated loopback service. Supply its
Bearer credential through NOVA_DAEMON_TOKEN or --daemon-token; do not place credentials in
this bundle. The host still needs a supported Linux graphics stack and the system libraries
required by Qt's XCB platform integration.
EOF

find "$release_root" -type f -print0 | xargs -0r touch -h -d "@${SOURCE_DATE_EPOCH:-0}"
tar --sort=name --mtime="@${SOURCE_DATE_EPOCH:-0}" --owner=0 --group=0 --numeric-owner -C "$root/release" -czf "$archive" "$(basename "$release_root")"
printf 'bundle=%s\narchive=%s\n' "$release_root" "$archive"
