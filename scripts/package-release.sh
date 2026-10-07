#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$PLIST")"
BUILD="${PNPOMATIC_BUILD:-$ROOT/.build/release/PnPOMaticApp}"
DIST_NAME="PnP-o-matic $VERSION"
DIST="$ROOT/dist/$DIST_NAME"
ZIP="$ROOT/dist/PnP-o-matic-v$VERSION.zip"
PAYLOAD="$DIST/.payload"
APP="$PAYLOAD/PnP-o-matic.app"

[[ -x "$BUILD" ]] || {
  echo "Release binary not found at $BUILD" >&2
  exit 1
}

rm -rf "$ROOT/dist"
mkdir -p "$APP/Contents/MacOS"
cp "$BUILD" "$APP/Contents/MacOS/PnPOMaticApp"
cp "$PLIST" "$APP/Contents/Info.plist"
chmod 755 "$APP/Contents/MacOS/PnPOMaticApp"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null

/usr/bin/codesign --force --deep --sign - "$APP"

cp "$ROOT/scripts/install.sh" "$DIST/Install PnP-o-matic.command"
cp "$ROOT/scripts/uninstall.sh" "$DIST/Uninstall PnP-o-matic.command"
chmod 755 "$DIST/Install PnP-o-matic.command" "$DIST/Uninstall PnP-o-matic.command"

cat > "$DIST/START HERE.html" <<HTML_EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PnP-o-matic $VERSION</title>
<style>
body{font:17px -apple-system,BlinkMacSystemFont,sans-serif;max-width:760px;margin:48px auto;padding:0 24px;line-height:1.5}
h1{font-size:34px}.box{border:1px solid #9996;border-radius:12px;padding:18px 22px;margin:20px 0}
</style>
</head>
<body>
<h1>PnP-o-matic $VERSION</h1>
<p>Turn PDFs with one card per page into print-ready 3×3 sheets.</p>
<div class="box">
<h2>Install</h2>
<ol>
<li>Double-click <strong>Install PnP-o-matic.command</strong>.</li>
<li>If macOS cannot verify the developer, Control-click/right-click the installer, choose <strong>Open</strong>, then <strong>Open</strong> again.</li>
<li>PnP-o-matic opens when installation finishes.</li>
</ol>
</div>
<h2>Use</h2>
<ol>
<li>Drop a PDF into the window. Each page is one card.</li>
<li>Drop additional PDFs to append their cards.</li>
<li>Choose a finished card size: Poker 2.5 × 3.5 in, Bridge 2.25 × 3.5 in, Euro 59 × 92 mm, PDF page size, or Custom.</li>
<li>Choose US Letter or A4.</li>
<li>Choose <strong>Edge marks only</strong> or <strong>Full-page cut lines</strong>.</li>
<li>Click <strong>Make 9-Up PDF</strong>. The result opens in Preview.</li>
</ol>
<p>Poker size is the default. Built-in Poker, Bridge, and Euro presets define the finished cut size exactly and fit 3×3 at full size on Letter and A4. Source artwork is scaled proportionally without distortion.</p>
<p>Requires macOS 11 Big Sur or later. Universal Intel + Apple Silicon release.</p>
</body>
</html>
HTML_EOF

cd "$ROOT/dist"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$DIST_NAME" "$ZIP"
echo "$ZIP"
