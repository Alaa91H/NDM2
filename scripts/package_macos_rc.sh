#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${1:-$root/build-native-release}"
version="${2:-3.0.0}"
architecture="${3:-$(uname -m)}"
core_binary="${4:-}"
staging_root="$root/package-native-stage"
release_dir="$root/release"
app_bundle="$staging_root/NDM2.app"
release_app="$release_dir/NDM2.app"
dmg_archive="$release_dir/NDM2-$version-macos-$architecture.dmg"

if [[ ! -x "$build_dir/native/NDM2.app/Contents/MacOS/NDM2" ]]; then
    echo "Native macOS application bundle not found in $build_dir" >&2
    exit 1
fi
if [[ -z "$core_binary" || ! -x "$core_binary" ]]; then
    echo "A built NOVA Core binary is required: $core_binary" >&2
    exit 1
fi

rm -rf "$staging_root" "$release_app" "$dmg_archive"
mkdir -p "$staging_root" "$release_dir"
cmake --install "$build_dir" --prefix "$staging_root"

if [[ ! -x "$app_bundle/Contents/MacOS/nova-core" ]]; then
    echo "The installed NDM2 app bundle does not contain NOVA Core." >&2
    exit 1
fi

cat > "$app_bundle/Contents/MacOS/start-nova-core" <<'CORELAUNCHER'
#!/usr/bin/env sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$root/nova-core" --integration "$@"
CORELAUNCHER
chmod 0755 "$app_bundle/Contents/MacOS/start-nova-core"

cat > "$staging_root/README.txt" <<EOF
NDM2 $version macOS release

This archive contains the native NDM2 app plus a platform-matched NOVA Core.
Open NDM2 normally from Finder or with:

  open -a NDM2

On each launch, NDM2 starts its bundled NOVA Core on loopback and supplies a fresh in-memory
bearer token automatically. No credential is stored in this archive. For advanced external-Core
diagnostics, provide NOVA_DAEMON_URL and NOVA_DAEMON_TOKEN before opening NDM2; explicit values
are preserved and NDM2 will not start a second Core.
EOF

# Match the primary CI deliverables: an installable app bundle and Finder-ready DMG.
cp -a "$app_bundle" "$release_app"
# macOS can retain a transient lock while macdeployqt finishes touching the app
# bundle. Retrying hdiutil makes the packaging step deterministic on Intel and
# Apple Silicon hosted runners without changing the DMG contents.
dmg_created=false
for attempt in 1 2 3 4; do
    rm -f "$dmg_archive"
    if hdiutil create -volname "NOVA Download Manager" -srcfolder "$staging_root" -ov -format UDZO "$dmg_archive" >/dev/null; then
        dmg_created=true
        break
    fi
    sleep "$attempt"
done
if [[ "$dmg_created" != true ]]; then
    echo "Could not create the macOS DMG after retrying transient filesystem locks." >&2
    exit 1
fi

printf 'app=%s\ndmg=%s\n' "$release_app" "$dmg_archive"
