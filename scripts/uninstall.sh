#!/bin/sh
set -eu

APP_NAME="GitHubPRBar"
LABEL="${LABEL:-io.github.karakanb.githubmenubar}"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_PATH="$PREFIX/bin/$APP_NAME"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LAUNCH_DOMAIN="gui/$(id -u)"

if launchctl print "$LAUNCH_DOMAIN/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "$LAUNCH_DOMAIN/$LABEL" >/dev/null 2>&1 || true
fi

rm -f "$PLIST_PATH"
rm -f "$BIN_PATH"

echo "Uninstalled $APP_NAME"
