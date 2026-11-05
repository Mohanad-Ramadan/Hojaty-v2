#!/usr/bin/env bash
# Installs and launches the debug APK on the running emulator, then saves
# screenshots, a screen recording, the full logcat, and (when LOG_FILTER is set)
# the log lines that contain it.
set -uo pipefail
out=results/android
mkdir -p "$out"
apk=build/app/outputs/flutter-apk/app-debug.apk
app=${ANDROID_APP_ID:?}
wait=${WAIT_SECONDS:-25}

adb wait-for-device
# A cold emulator is slow enough that system apps raise "isn't responding"
# dialogs over the app. Hide those dialogs and let the system settle first.
adb shell settings put global hide_error_dialogs 1 || true
adb shell settings put secure anr_show_background 0 || true
sleep 20
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
adb logcat -c || true
adb emu geo fix "$LON" "$LAT" || true
adb install -r -g "$apk"
for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS; do
  adb shell pm grant "$app" "android.permission.$perm" 2>/dev/null || true
done

adb shell screenrecord --time-limit 60 /sdcard/run.mp4 &
rec=$!
adb shell monkey -p "$app" -c android.intent.category.LAUNCHER 1 >/dev/null
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
sleep 8
adb exec-out screencap -p > "$out/01-launch.png"
sleep "$wait"
adb exec-out screencap -p > "$out/02-after-${wait}s.png"
adb shell pidof "$app" > "$out/pid.txt" || echo "app is not running" | tee "$out/pid.txt"
kill -INT "$rec" 2>/dev/null; sleep 3
adb pull /sdcard/run.mp4 "$out/run.mp4" >/dev/null 2>&1 || true

adb logcat -d > "$out/logcat.txt"
if [ -n "${LOG_FILTER:-}" ]; then
  grep -F -- "$LOG_FILTER" "$out/logcat.txt" > "$out/filtered-log.txt" || true
  echo "lines matching '$LOG_FILTER': $(wc -l < "$out/filtered-log.txt")"
fi
grep -E "flutter|AndroidRuntime|FATAL" "$out/logcat.txt" > "$out/app-log.txt" || true
if grep -q "FATAL EXCEPTION" "$out/logcat.txt"; then echo "the app crashed; see logcat.txt"; exit 1; fi
exit 0
