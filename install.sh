#!/bin/bash
set -euo pipefail

readonly ROOT=$(cd "$(dirname "$0")" && pwd)
readonly APP="$HOME/Applications/Scotty.app"
readonly CLI="$HOME/.local/bin/scotty"
readonly LIBEXEC=/usr/local/libexec/scotty
readonly OPENCONNECT=/opt/homebrew/bin/openconnect
readonly VPNC=/opt/homebrew/etc/vpnc/vpnc-script
readonly SUDOERS=/etc/sudoers.d/scotty
readonly RULE="$USER ALL=(root) NOPASSWD: $LIBEXEC/tunnel"

[[ -x $OPENCONNECT && -f $VPNC ]] || {
  echo "error: needs openconnect at $OPENCONNECT: brew install openconnect" >&2
  exit 1
}

swift build -c release --package-path "$ROOT"
bin=$(swift build -c release --package-path "$ROOT" --show-bin-path)

osascript -e 'quit app "Scotty"' 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Bundle/Info.plist" "$APP/Contents/"
cp "$bin/ScottyApp" "$bin/scotty" "$APP/Contents/MacOS/"
cp "$ROOT"/Bundle/StatusIcon*.png "$APP/Contents/Resources/"
xcrun actool "$ROOT/Bundle/AppIcon.icon" --compile "$APP/Contents/Resources" --app-icon AppIcon \
  --platform macosx --target-device mac --minimum-deployment-target 15.0 \
  --output-partial-info-plist /dev/null --standalone-icon-behavior all >/dev/null
codesign --force --sign - "$APP/Contents/MacOS/scotty"
codesign --force --sign - "$APP"
mkdir -p "$(dirname "$CLI")"
ln -sfn "$APP/Contents/MacOS/scotty" "$CLI"

stale() { ! cmp -s "$1" "$2" 2>/dev/null; }
if stale "$ROOT/Root/tunnel" "$LIBEXEC/tunnel" || stale "$ROOT/Root/routes" "$LIBEXEC/routes" ||
  stale "$VPNC" "$LIBEXEC/vpnc-script" || ! sudo -n -l "$LIBEXEC/tunnel" >/dev/null 2>&1; then
  sudo install -d -o root -g wheel -m 755 "$LIBEXEC"
  sudo install -o root -g wheel -m 755 "$ROOT/Root/tunnel" "$ROOT/Root/routes" "$VPNC" "$LIBEXEC/"
  printf '%s\n' "$RULE" | sudo tee "$SUDOERS" >/dev/null
  sudo chmod 440 "$SUDOERS"
  sudo visudo -cf "$SUDOERS"
fi

open "$APP"
