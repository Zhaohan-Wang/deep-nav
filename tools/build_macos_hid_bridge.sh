#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SOURCE="$PROJECT_ROOT/native/macos/hid_mouse_bridge.c"
OUTPUT_DIR="$PROJECT_ROOT/native/macos/bin"
OUTPUT="$OUTPUT_DIR/deepnav-hid-mouse-bridge"

mkdir -p "$OUTPUT_DIR"
clang -std=c11 -O2 -Wall -Wextra \
	"$SOURCE" \
	-framework IOKit \
	-framework CoreFoundation \
	-o "$OUTPUT"
chmod +x "$OUTPUT"
print "Built $OUTPUT"
