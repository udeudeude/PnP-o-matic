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
<p>Build duplex-ready 3×3 print-and-play card sheets from PDFs and image files.</p>
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
<li>Add front cards with <strong>Add Fronts…</strong>, by dropping PDF/image files onto front slots, or by opening files with the app.</li>
<li>Add matching backs with <strong>Add Backs…</strong>. Page 1 pairs with front 1, page 2 with front 2, and so on.</li>
<li>For front-back-front-back PDFs, choose <strong>Import Alternating Front / Back PDF…</strong>.</li>
<li>For PDFs divided into two equal halves, choose <strong>Import First Half / Second Half…</strong>.</li>
<li>For a single shared back, import fronts then choose <strong>Repeat One Back…</strong>.</li>
<li>Drag numbered slots to rearrange cards. Leave the front/back lock on to move pairs together, or switch it off to rearrange one side independently.</li>
<li>Choose Poker, Bridge, Euro, Tarot, 2.5-inch Square, source-page, or custom finished card size.</li>
<li>Choose Fit or Fill artwork, PDF page box and optional 3 mm bleed.</li>
<li>Choose US Letter or A4 and edge-only or full-page cut lines.</li>
<li>Choose long-edge duplex for normal portrait book-style flipping. The back grid mirrors columns automatically.</li>
<li>Click <strong>Make Duplex 9-Up PDF</strong>. The result opens in Preview.</li>
</ol>
<p>Tarot cards cannot fit nine-up at 100% on Letter or A4; the scale warning shows the reduction. For correctly sized cards, print at Actual Size / 100% without automatic fit-to-page.</p>
<p>The previews are numbered to show physical duplex placement. With long-edge duplex, fronts read 1-2-3 / 4-5-6 / 7-8-9 and backs read 3-2-1 / 6-5-4 / 9-8-7. Artwork is not mirrored; only back positions are rearranged.</p>
<p>Requires macOS 11 Big Sur or later. Universal Intel + Apple Silicon release.</p>
</body>
</html>
HTML_EOF

cd "$ROOT/dist"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$DIST_NAME" "$ZIP"
echo "$ZIP"
