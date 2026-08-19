#!/bin/zsh
set -euo pipefail

# 独立进程启动游戏（不要用编辑器里的嵌入播放）。
# 双屏窗口、HID 双鼠标桥都依赖这个独立进程。
PROJECT_ROOT="${0:A:h:h}"
exec "$PROJECT_ROOT/tools/godot-cli" --path "$PROJECT_ROOT" "$@"
