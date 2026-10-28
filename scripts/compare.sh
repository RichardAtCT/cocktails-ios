#!/bin/bash
# Side by side: the website (local dev server, headless Chrome) and the app (a simulator) at the
# same size, to check the app's layout follows the site's.
#   scripts/compare.sh <site path> <iphone|ipad> <p|l> <out.png>
# The simulator must already be rotated to match (p = portrait, l = landscape).
set -e
cd "$(dirname "$0")/.."
path=$1 dev=$2 ori=$3 out=$4
case $dev in
	iphone) UDID=3702ED8D-C59F-46EF-8E18-9F680DE180F3; W=402; H=874 ;;
	ipad)   UDID=35B94EE7-E8EB-4ABE-8E8A-2D7F94F1734C; W=820; H=1180 ;;
esac
[ "$ori" = l ] && { t=$W; W=$H; H=$t; }
tmp=$(mktemp -d)
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
	--force-device-scale-factor=2 --window-size=$W,$H --screenshot=$tmp/web.png "http://localhost:8000$path" >/dev/null 2>&1
xcrun simctl terminate $UDID com.decentespresso.cocktails 2>/dev/null || true
xcrun simctl launch $UDID com.decentespresso.cocktails -open "$path" -lang en >/dev/null
sleep ${WAIT:-4}
xcrun simctl io $UDID screenshot $tmp/app.png >/dev/null 2>&1
# the simulator captures the portrait framebuffer: turn a landscape capture upright
[ "$ori" = l ] && magick $tmp/app.png -rotate -90 $tmp/app.png
# both at the same pixel width, labelled
magick $tmp/web.png -resize $((W*2))x -gravity north -background white -splice 0x40 -pointsize 28 -annotate +0+4 "website $W×$H" $tmp/w.png
magick $tmp/app.png -resize $((W*2))x -gravity north -background white -splice 0x40 -pointsize 28 -annotate +0+4 "app" $tmp/a.png
magick $tmp/w.png $tmp/a.png -background '#888' -splice 12x0 +append -resize ${SCALE:-50}% "$out"
rm -rf $tmp
echo "$out"
