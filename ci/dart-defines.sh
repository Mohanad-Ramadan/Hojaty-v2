#!/bin/sh
# Turns DART_DEFINES ("A=1 B=2") into "--dart-define=A=1 --dart-define=B=2".
for pair in $DART_DEFINES; do
  case "$pair" in
    *=*) printf -- '--dart-define=%s ' "$pair" ;;
    *) echo "ignoring dart define without '=': $pair" >&2 ;;
  esac
done
