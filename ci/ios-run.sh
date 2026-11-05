#!/usr/bin/env bash
# Boots an iPhone simulator, installs and launches the debug build, then saves
# screenshots, a screen recording, the app's log, and (when LOG_FILTER is set)
# the log lines that contain it.
set -uo pipefail
out=results/ios
mkdir -p "$out"
app_path=build/ios/iphonesimulator/Runner.app
bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_path/Info.plist")
wait=${WAIT_SECONDS:-25}

udid=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
c=[(rt,x) for rt,xs in d.items() if "iOS" in rt for x in xs if x["name"].startswith("iPhone")]
c.sort(key=lambda t:(t[0],"Pro" in t[1]["name"]))
print(c[-1][1]["udid"])')
echo "simulator: $(xcrun simctl list devices | grep "$udid")"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl location "$udid" set "$LAT,$LON" || true
xcrun simctl install "$udid" "$app_path"
xcrun simctl privacy "$udid" grant location "$bundle" || true
xcrun simctl privacy "$udid" grant location-always "$bundle" || true

start=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl io "$udid" recordVideo --codec=h264 --force "$out/run.mp4" &
rec=$!
sleep 2
xcrun simctl launch "$udid" "$bundle"
sleep 8
xcrun simctl io "$udid" screenshot "$out/01-launch.png"
sleep "$wait"
xcrun simctl io "$udid" screenshot "$out/02-after-${wait}s.png"
kill -INT "$rec" 2>/dev/null; wait "$rec" 2>/dev/null

xcrun simctl spawn "$udid" log show --start "$start" --style compact \
  --predicate 'process == "Runner"' > "$out/app-log.txt" 2>&1 || true
if [ -n "${LOG_FILTER:-}" ]; then
  # Every process, not only Runner, so print() and os_log from any subsystem count.
  # The log command logs its own arguments, which contain the filter: drop that line.
  xcrun simctl spawn "$udid" log show --start "$start" --style compact \
    --predicate "eventMessage CONTAINS \"$LOG_FILTER\"" 2>/dev/null |
    grep -F -- "$LOG_FILTER" | grep -v "args: 'log'" > "$out/filtered-log.txt" || true
  echo "lines matching '$LOG_FILTER': $(wc -l < "$out/filtered-log.txt")"
fi
if ! xcrun simctl spawn "$udid" launchctl list | grep -q "$bundle"; then
  echo "the app is not running; see app-log.txt"; exit 1
fi
exit 0
