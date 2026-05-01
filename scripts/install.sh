#!/bin/sh
set -eu

APP_NAME="GitHubPRBar"
LABEL="${LABEL:-io.github.karakanb.githubmenubar}"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
BIN_PATH="$BIN_DIR/$APP_NAME"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/$APP_NAME"
LAUNCH_DOMAIN="gui/$(id -u)"
PATH_VALUE="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

cd "$(dirname "$0")/.."

if ! command -v swift >/dev/null 2>&1; then
    echo "error: swift is required. Install Xcode or Command Line Tools first." >&2
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "warning: gh is not on PATH. Install GitHub CLI and run 'gh auth login' before using the app." >&2
elif ! gh auth status >/dev/null 2>&1; then
    echo "warning: gh is installed but not authenticated. Run 'gh auth login' before using the app." >&2
fi

swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"

if launchctl print "$LAUNCH_DOMAIN/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "$LAUNCH_DOMAIN/$LABEL" >/dev/null 2>&1 || true
fi

mkdir -p "$BIN_DIR" "$PLIST_DIR" "$LOG_DIR"
install -m 755 "$BUILD_DIR/$APP_NAME" "$BIN_PATH"
codesign --force --sign - "$BIN_PATH" >/dev/null 2>&1 || true

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$PATH_VALUE</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/stderr.log</string>
</dict>
</plist>
PLIST

launchctl bootstrap "$LAUNCH_DOMAIN" "$PLIST_PATH"
launchctl enable "$LAUNCH_DOMAIN/$LABEL"
launchctl kickstart -k "$LAUNCH_DOMAIN/$LABEL"

echo "Installed $APP_NAME to $BIN_PATH"
echo "LaunchAgent: $PLIST_PATH"
