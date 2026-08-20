# NDM2 Native Distribution Matrix

## Scope

The native distribution workflow builds the **Qt Quick NDM2 client** and the matching **NOVA Rust Core** together for every supported desktop target. Each published artifact carries a SHA-256 checksum and is named by operating-system family and CPU architecture.

| Target | GitHub-hosted runner | Native package | Included NOVA Core |
|---|---|---|---|
| Linux x64 | `ubuntu-24.04` | AppImage, DEB, RPM | `bin/nova-core` |
| Linux ARM64 | `ubuntu-24.04-arm` | AppImage, DEB, RPM | `bin/nova-core` |
| Windows x64 | `windows-latest` | NSIS installer | `bin/nova-core.exe` |
| Windows ARM64 | `windows-11-arm` | NSIS installer | `bin/nova-core.exe` |
| macOS Intel | `macos-15-intel` | DMG and `.app` | `NDM2.app/Contents/MacOS/nova-core` |
| macOS Apple Silicon | `macos-15` | DMG and `.app` | `NDM2.app/Contents/MacOS/nova-core` |

> GitHub provides the Intel macOS, Apple-Silicon macOS, Linux ARM64, and Windows ARM64 runner labels used by this matrix.[1]

## Linux distribution support

Linux receives the same format families as the primary CI: **AppImage**, **DEB**, and **RPM**. All three carry the NDM2 executable, bundled Qt runtime and QML modules, platform plugins, icon assets, and a platform-matched NOVA Core. The AppImage is the portable choice for current glibc-based desktops; DEB targets Debian/Ubuntu derivatives and RPM targets Fedora/RHEL/openSUSE-style systems.

No binary package can honestly guarantee execution on every historical or non-glibc Linux distribution. The workflow validates all three formats on Ubuntu 24.04 for x64 and ARM64, and verifies that both DEB and RPM payloads contain the expected Core binary.

## Core launch and authentication

The bundled Core is intentionally not given a fixed token. Start it with a per-launch secret and supply the same value to NDM2:

```sh
export NOVA_INTEGRATION_API_TOKEN="replace-with-a-secret-of-at-least-24-characters"
./start-nova-core.sh
NOVA_DAEMON_TOKEN="$NOVA_INTEGRATION_API_TOKEN" ./ndm2 --daemon-endpoint http://127.0.0.1:3199
```

The Core remains bound to loopback, and the client retains its loopback endpoint validation and bearer-token authentication. No credential is committed or embedded in any package.

## Verification gates

Every matrix entry builds `nova` in release mode, builds NDM2 in release mode with the Core supplied as a CMake package input, runs the NDM2 model tests, verifies the Core binary is present in the assembled artifact, and uploads checksums alongside the package.

## References

[1]: https://docs.github.com/en/actions/reference/runners/github-hosted-runners "GitHub-hosted runners reference"
