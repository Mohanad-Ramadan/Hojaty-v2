#!/usr/bin/env bash
# Searches the release build's binaries for strings that must only exist in
# debug builds (RELEASE_FORBIDDEN, space-separated). Empty: the check is skipped.
# Usage: release-check.sh android <apk> | ios <Runner.app>
set -uo pipefail
kind=$1 target=$2
out=results/$kind
mkdir -p "$out"
if [ -z "${RELEASE_FORBIDDEN:-}" ]; then
  echo "SKIPPED: no release_forbidden strings given" | tee "$out/release-check.txt"
  exit 0
fi
dir=$(mktemp -d)
case "$kind" in
  android) unzip -q "$target" -d "$dir" ;;
  ios) cp -R "$target" "$dir/" ;;
esac
files=$(find "$dir" -type f \( -name '*.so' -o -name '*.dex' -o -name 'App' -o -name 'Runner' \))
if [ -z "$files" ]; then echo "FAIL: no binaries found to search" | tee "$out/release-check.txt"; exit 1; fi
hits=0
: > "$out/release-check.txt"
for f in $files; do
  for s in $RELEASE_FORBIDDEN; do
    if strings -a "$f" | grep -qF -- "$s"; then echo "FOUND: $s in ${f#$dir/}" >> "$out/release-check.txt"; hits=1; fi
  done
done
[ $hits = 0 ] && echo "PASS: none of [$RELEASE_FORBIDDEN] in $(echo "$files" | wc -l | tr -d ' ') release binaries" >> "$out/release-check.txt"
cat "$out/release-check.txt"
exit $hits
