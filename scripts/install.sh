#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLED_APP="$SCRIPT_DIR/.payload/PnP-o-matic.app"
[[ -d "$BUNDLED_APP" ]] || BUNDLED_APP="$SCRIPT_DIR/PnP-o-matic.app"

APP="$HOME/Applications/PnP-o-matic.app"

OS_MAJOR="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
if (( OS_MAJOR < 11 )); then
  echo "PnP-o-matic requires macOS 11 Big Sur or later." >&2
  exit 1
fi

mkdir -p "$HOME/Applications"

install_binary() {
  local binary="$1"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  cp "$binary" "$APP/Contents/MacOS/PnPOMaticApp"
  cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
  chmod 755 "$APP/Contents/MacOS/PnPOMaticApp"
}

if [[ -d "$BUNDLED_APP" ]]; then
  echo "Installing PnP-o-matic..."
  rm -rf "$APP"
  /usr/bin/ditto "$BUNDLED_APP" "$APP"
else
  BUILD="${PNPOMATIC_BUILD:-}"
  if [[ -z "$BUILD" ]]; then
    echo "Building PnP-o-matic..."
    cd "$ROOT"
    MACOSX_DEPLOYMENT_TARGET=11.0 /usr/bin/swift build -c release --product PnPOMaticApp
    BUILD="$ROOT/.build/release/PnPOMaticApp"
  fi
  [[ -x "$BUILD" ]] || {
    echo "PnPOMaticApp binary not found at $BUILD" >&2
    exit 1
  }
  install_binary "$BUILD"
fi

/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
fi

echo "Installed PnP-o-matic at:"
echo "  $APP"

/usr/bin/open "$APP" >/dev/null 2>&1 || true
