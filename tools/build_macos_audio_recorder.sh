#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SOURCE="$PROJECT_ROOT/native/macos/audio_recorder.m"
APP_DIR="$PROJECT_ROOT/native/macos/bin/DeepNavAudioRecorder.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
OUTPUT="$MACOS_DIR/deepnav-audio-recorder"

mkdir -p "$MACOS_DIR"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>deepnav-audio-recorder</string>
	<key>CFBundleIdentifier</key>
	<string>dev.deepnav.audio-recorder</string>
	<key>CFBundleName</key>
	<string>DeepNav Audio Recorder</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.1.0</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>DeepNav records the experiment session audio for research analysis.</string>
</dict>
</plist>
PLIST

clang -fobjc-arc -O2 -Wall -Wextra -arch arm64 -arch x86_64 \
	"$SOURCE" \
	-framework AVFoundation \
	-framework Foundation \
	-o "$OUTPUT"
chmod +x "$OUTPUT"
print "Built $OUTPUT"
