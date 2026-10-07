#!/bin/zsh
set -euo pipefail

APP="$HOME/Applications/PnP-o-matic.app"
rm -rf "$APP"
rm -rf "${TMPDIR:-/tmp}/PnP-o-matic"

echo "Removed PnP-o-matic."
