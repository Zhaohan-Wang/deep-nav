#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
DIST_ROOT="${1:-$PROJECT_ROOT/../deep-nav-dist}"
APP="$DIST_ROOT/DeepNav.app"
ZIP="$DIST_ROOT/DeepNav-macOS.zip"
HELPERS="$APP/Contents/Helpers"
ENTITLEMENTS="$(mktemp /private/tmp/deepnav-audio-entitlements.XXXXXX)"
trap 'rm -f "$ENTITLEMENTS"' EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
	print -u2 "DeepNav macOS packaging must run on macOS."
	exit 1
fi

"$PROJECT_ROOT/tools/build_macos_hid_bridge.sh"
"$PROJECT_ROOT/tools/build_macos_audio_recorder.sh"

mkdir -p "$DIST_ROOT"
rm -rf "$APP"
rm -f "$ZIP"
"$PROJECT_ROOT/tools/godot-cli" \
	--headless \
	--path "$PROJECT_ROOT" \
	--export-release "DeepNav_macOS" "$APP"

mkdir -p "$HELPERS"
cp "$PROJECT_ROOT/native/macos/bin/deepnav-hid-mouse-bridge" "$HELPERS/"
ditto \
	"$PROJECT_ROOT/native/macos/bin/DeepNavAudioRecorder.app" \
	"$HELPERS/DeepNavAudioRecorder.app"
chmod +x \
	"$HELPERS/deepnav-hid-mouse-bridge" \
	"$HELPERS/DeepNavAudioRecorder.app/Contents/MacOS/deepnav-audio-recorder"

cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.device.audio-input</key>
	<true/>
</dict>
</plist>
PLIST

xattr -cr "$APP"
codesign --force --sign - "$HELPERS/deepnav-hid-mouse-bridge"
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$HELPERS/DeepNavAudioRecorder.app"
codesign --force --sign - --preserve-metadata=identifier,entitlements,flags "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

cat > "$DIST_ROOT/实验数据位置.txt" <<'TEXT'
DeepNav 打包版实验记录：

~/Library/Application Support/DeepNav/experiments/

标题页的「打开数据文件夹」会直接打开该目录。

首次使用实验模式时，macOS 会分别请求：
1. 输入监控权限（区分两只实体鼠标）
2. 麦克风权限（录制实验原始音频）

修改权限后如未立即生效，请完全退出 DeepNav 再重新打开。
TEXT

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
print "Packaged:"
print "  $APP"
print "  $ZIP"
