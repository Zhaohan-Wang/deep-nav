#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
LOG_FILE="$(mktemp /private/tmp/deep-nav-star-map.XXXXXX.log)"
trap 'rm -f "$LOG_FILE"' EXIT

"$PROJECT_ROOT/tools/godot-cli" \
	--log-file "$LOG_FILE" \
	--path "$PROJECT_ROOT" \
	--script res://tools/star_map_capture.gd

if ! rg -q 'STAR_MAP_CAPTURE_ALL_OK count=5' "$LOG_FILE"; then
	print -u2 "DEEP_NAV_STAR_MAP_CAPTURE_FAILED"
	exit 1
fi
if rg -n 'SCRIPT ERROR|SHADER ERROR|Shader compilation failed|Invalid polygon data|Failed to load script' "$LOG_FILE"; then
	print -u2 "DEEP_NAV_STAR_MAP_CAPTURE_FAILED: runtime errors"
	exit 1
fi
print "DEEP_NAV_STAR_MAP_CAPTURE_OK"
