#!/bin/zsh
# Build the prototype and capture screenshots on the Mac simulator.
# Usage: ./mac_shoot.sh <device name> <shots file> [out dir]
# Shots file: one shot per line -> name|appearance(light|dark)|content size|launch args...
#   e.g. home-light|light|large|-screen home -theme instrument
set -euo pipefail
cd "$(dirname "$0")"
DEVICE="${1:-iPhone 18 Pro}"
SHOTS="${2:-shots.txt}"
OUT="${3:-shots}"
BUNDLE="com.chengzixqq.sub2mobile.uiproto"

python3 generate_project.py >/dev/null
xcodebuild -project Sub2Proto.xcodeproj -scheme Sub2Proto \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath build -quiet build
APP="build/Build/Products/Debug-iphonesimulator/Sub2Proto.app"

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
data=json.load(sys.stdin)['devices']
for runtime in sorted(data, reverse=True):
    for d in data[runtime]:
        if d['name']=='$DEVICE' and d['isAvailable']:
            print(d['udid']); sys.exit()")
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null
xcrun simctl install "$UDID" "$APP"
mkdir -p "$OUT"

while IFS='|' read -r name appearance size args; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl ui "$UDID" content_size "$size"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  eval "xcrun simctl launch \"$UDID\" \"$BUNDLE\" $args" >/dev/null
  sleep "${SHOT_DELAY:-2.5}"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
  echo "shot $name"
done < "$SHOTS"
xcrun simctl ui "$UDID" content_size large
xcrun simctl ui "$UDID" appearance light
