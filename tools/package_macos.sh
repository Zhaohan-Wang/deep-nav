#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
DIST_ROOT="${1:-$PROJECT_ROOT/../deep-nav-dist}"
APP="$DIST_ROOT/DeepNav.app"
ZIP="$DIST_ROOT/DeepNav-macOS.zip"
HELPERS="$APP/Contents/Helpers"

if [[ "$(uname -s)" != "Darwin" ]]; then
	print -u2 "DeepNav macOS packaging must run on macOS."
	exit 1
fi

"$PROJECT_ROOT/tools/build_macos_hid_bridge.sh"

mkdir -p "$DIST_ROOT"
rm -rf "$APP"
rm -f "$ZIP"
"$PROJECT_ROOT/tools/godot-cli" \
	--headless \
	--path "$PROJECT_ROOT" \
	--export-release "DeepNav_macOS" "$APP"

mkdir -p "$HELPERS"
cp "$PROJECT_ROOT/native/macos/bin/deepnav-hid-mouse-bridge" "$HELPERS/"
chmod +x "$HELPERS/deepnav-hid-mouse-bridge"

# 必须用稳定的开发者证书签名。临时签名（-）每次打包都会改变签名指纹，
# macOS 会把新包当成陌生应用、作废已授予的「输入监控」权限，导致双鼠标
# 桥接进程被系统拒绝（kIOReturnNotPermitted），两只鼠标退化成一只合并指针。
SIGN_IDENTITY="${DEEPNAV_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' 'NR==1 {print $2}')}"
if [[ -z "$SIGN_IDENTITY" ]]; then
	print -u2 "未找到代码签名证书；打包中止。临时签名会在每次重打包后丢失输入监控权限。"
	print -u2 "请安装 Apple Development 证书，或设置 DEEPNAV_SIGN_IDENTITY 后重试。"
	exit 1
fi
print "Signing with identity: $SIGN_IDENTITY"

xattr -cr "$APP"
codesign --force --sign "$SIGN_IDENTITY" \
	--identifier "com.zhaohanwang.deepnav.hid-mouse-bridge" \
	"$HELPERS/deepnav-hid-mouse-bridge"
codesign --force --sign "$SIGN_IDENTITY" --preserve-metadata=identifier,entitlements,flags "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP"

cat > "$DIST_ROOT/实验数据位置.txt" <<'TEXT'
DeepNav 打包版实验记录：

~/Library/Application Support/DeepNav/experiments/

标题页的「打开数据文件夹」会直接打开该目录。

首次使用实验模式时，macOS 会分别请求：
1. 输入监控权限（区分两只实体鼠标）

DeepNav 1.1.0 首次打开还会在应用内重新确认：
1. 是否启用游戏声音以及音量
2. 是否启用画面震动

双鼠标使用的是「输入监控」，不是「辅助功能」。同一台 Mac 如果已经
授权过相同 Bundle ID 和开发团队，macOS 可能沿用原权限而不重复弹窗。
需要重新验证系统弹窗时，请先在“系统设置 → 隐私与安全性”中移除旧授权。

修改权限后如未立即生效，请完全退出 DeepNav 再重新打开。
TEXT

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
print "Packaged:"
print "  $APP"
print "  $ZIP"
