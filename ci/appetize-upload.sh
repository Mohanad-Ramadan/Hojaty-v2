#!/usr/bin/env bash
# Uploads a build to Appetize so it can be used in a browser.
# Needs the APPETIZE_API_TOKEN secret. Set the repo variable APPETIZE_IOS_KEY or
# APPETIZE_ANDROID_KEY to the app's public key to update the same link each run.
set -euo pipefail
platform=$1 file=$2
url=https://api.appetize.io/v1/apps
[ -n "${APPETIZE_KEY:-}" ] && url="$url/$APPETIZE_KEY"
resp=$(curl -sS --fail-with-body -X POST "$url" -H "X-API-KEY: $APPETIZE_API_TOKEN" \
  -F "file=@$file" -F "platform=$platform")
key=$(printf '%s' "$resp" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("publicKey",""))')
echo "Appetize ($platform): https://appetize.io/app/$key" | tee -a "$GITHUB_STEP_SUMMARY"
