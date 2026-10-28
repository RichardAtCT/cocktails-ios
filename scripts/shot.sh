#!/bin/bash
# Screenshot one page of the Catalyst debug build: scripts/shot.sh <site path> <out.png> [width height]
# e.g. scripts/shot.sh /cocktails/pdt/recipes/Negroni /tmp/negroni.png 430 900
# extra launch arguments in $SHOT_ARGS, e.g. SHOT_ARGS="-drinks 2"
set -e
cd "$(dirname "$0")/.."
APP="build/Build/Products/Debug-maccatalyst/Decent Cocktails.app"
W=${3:-430}; H=${4:-932}
pkill -x "Decent Cocktails" 2>/dev/null || true; sleep 0.5
"$APP/Contents/MacOS/Decent Cocktails" -open "$1" $SHOT_ARGS >/dev/null 2>&1 &
sleep 3
osascript -e "tell application \"System Events\" to tell (first process whose name is \"Cocktails\") to set size of front window to {$W, $H}" >/dev/null 2>&1 || true
sleep 1.2
ID=$(scripts/winid "Decent Cocktails")
screencapture -x -o -l "$ID" "$2"
echo "$2"
