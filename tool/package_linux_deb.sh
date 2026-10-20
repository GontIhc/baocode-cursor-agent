#!/bin/sh
# Packages flutter build linux --release into a .deb and a portable tarball,
# for this machine's processor (x64 or arm64). Run on Ubuntu after the
# bundle exists at build/linux/<arch>/release/bundle. The remote server's
# VERSION and servers.json, when built into build/remote/, go beside the
# executable (lib/remote/remote_binaries.dart); the app downloads the
# builds they name.
#
#   sh tool/package_linux_deb.sh            the standard build
#   sh tool/package_linux_deb.sh --channel  the channel build (built with
#                                           BAOCODE_CHANNEL=true in the
#                                           environment and as a dart-define):
#                                           its files end in -channel, and it
#                                           depends on WebKitGTK, for its
#                                           login window
#
# Installers are BaoCursor-<version>-linux-<arch>.deb and .tar.gz, and the
# desktop entry's Name is BaoCursor (same product name as the macOS
# BaoCursor.app installers). The executable stays `baocode`: Flutter's Linux
# target takes that from linux/CMakeLists.txt BINARY_NAME, and it does not
# have to be baocode to build, but the dpkg package name `baocode` and
# /opt/baocode are what lib/update/installer_io.dart checks before it will
# apply an update. /usr/bin/baocursor and /usr/bin/baocode both run it.
# StartupWMClass stays dev.baocode.desktop (APPLICATION_ID).
set -eu

edition=
webkit=
case "${1:-}" in
  --channel) edition=-channel; webkit=", libwebkit2gtk-4.1-0" ;;
  "") ;;
  *) echo "Unknown argument: $1" >&2; exit 1 ;;
esac

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
version=$(sed -n 's/^version:[[:space:]]*//p' "$root/pubspec.yaml")
marketing=${version%%+*}
case "$(uname -m)" in
  x86_64) arch=x64; package_arch=amd64 ;;
  aarch64 | arm64) arch=arm64; package_arch=arm64 ;;
  *) echo "Not built for $(uname -m)" >&2; exit 1 ;;
esac
bundle="$root/build/linux/$arch/release/bundle"

if [ ! -x "$bundle/baocode" ]; then
  echo "No bundle at $bundle (expected executable baocode). Run: flutter build linux --release" >&2
  exit 1
fi

if [ -f "$root/build/remote/servers.json" ]; then
  rm -rf "$bundle/remote"
  mkdir -p "$bundle/remote"
  cp "$root/build/remote/VERSION" "$root/build/remote/servers.json" "$bundle/remote/"
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/opt/baocode" \
  "$stage/usr/bin" \
  "$stage/usr/share/applications" \
  "$stage/usr/share/icons/hicolor/128x128/apps" \
  "$stage/DEBIAN"

cp -a "$bundle/." "$stage/opt/baocode/"
cp "$root/assets/branding/app_icon.png" \
  "$stage/usr/share/icons/hicolor/128x128/apps/baocursor.png"

cat > "$stage/usr/bin/baocursor" << 'EOF'
#!/bin/sh
exec /opt/baocode/baocode "$@"
EOF
chmod 755 "$stage/usr/bin/baocursor"
# The historical command name, same binary.
cp "$stage/usr/bin/baocursor" "$stage/usr/bin/baocode"

cat > "$stage/usr/share/applications/baocursor.desktop" << 'EOF'
[Desktop Entry]
Name=BaoCursor
Comment=Desktop shell for Cursor Agent
Exec=baocursor %U
Icon=baocursor
Terminal=false
Type=Application
Categories=Development;
StartupWMClass=dev.baocode.desktop
EOF

# libgtk-3-0 is what the engine links. libblkid1 and liblzma5 are the
# extra libraries Flutter's Linux bundle expects on the system.
cat > "$stage/DEBIAN/control" << EOF
Package: baocode
Version: ${marketing}
Section: devel
Priority: optional
Architecture: ${package_arch}
Depends: libgtk-3-0, libblkid1, liblzma5${webkit}
Maintainer: BaoCursor <noreply@baocode.dev>
Homepage: https://baocode.dev
Description: BaoCursor desktop for Linux
 A desktop shell for the Cursor Agent CLI, with a fast IDE built in.
EOF

out="$root/build/installers"
mkdir -p "$out"
name="BaoCursor-${marketing}-linux-${package_arch}${edition}"
dpkg-deb --build --root-owner-group "$stage" "$out/$name.deb"
tar -C "$bundle" -czf "$out/$name.tar.gz" .
echo "Wrote $out/$name.deb"
echo "Wrote $out/$name.tar.gz"
