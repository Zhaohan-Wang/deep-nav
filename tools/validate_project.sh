#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
GODOT_LAUNCHER="$PROJECT_ROOT/tools/godot-cli"
RUN_LOG="$(mktemp /private/tmp/deep-nav-validate.XXXXXX)"
ENGINE_LOG="$(mktemp /private/tmp/deep-nav-engine.XXXXXX)"
trap 'rm -f "$RUN_LOG" "$ENGINE_LOG"' EXIT

"$GODOT_LAUNCHER" \
	--headless \
	--log-file "$ENGINE_LOG" \
	--path "$PROJECT_ROOT" \
	--quit-after 8 \
	-- --dual-window-smoke >"$RUN_LOG" 2>&1

cat "$RUN_LOG"

# macOS 沙箱中的证书和退出期 Dummy renderer 泄漏是环境噪声；
# 这里只把会破坏项目运行的解析、脚本、资源和 shader 错误视为失败。
if rg -n \
	'SCRIPT ERROR|Parse Error|SHADER ERROR|Shader compilation failed|Failed to load script|Cannot open file.*res://' \
	"$RUN_LOG" "$ENGINE_LOG"; then
	print -u2 "DEEP_NAV_VALIDATION_FAILED"
	exit 1
fi

print "DEEP_NAV_VALIDATION_OK"

"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/flow_smoke.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/participant_ui_privacy_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/visual_asset_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/waypoint_behavior_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/mission_flow_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/mission_audit.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/boundary_physics_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/belt_consistency_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/navigation_difficulty_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/billboard_projection_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/asteroid_belt_hazard_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/asteroid_belt_gameplay_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/hull_feedback_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/role_claim_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/session_progress_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/experiment_pipeline_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/menu_input_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/keyboard_seat_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/audio_system_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/pause_menu_test.gd >>"$RUN_LOG" 2>&1
"$GODOT_LAUNCHER" --headless --log-file "$ENGINE_LOG" --path "$PROJECT_ROOT" --script res://tools/performance_budget_test.gd >>"$RUN_LOG" 2>&1
cat "$RUN_LOG"
if rg -n \
	'SCRIPT ERROR|Parse Error|SHADER ERROR|Shader compilation failed|Failed to load script|Cannot open file.*res://' \
	"$RUN_LOG" "$ENGINE_LOG"; then
	print -u2 "DEEP_NAV_FULL_VALIDATION_FAILED"
	exit 1
fi
if ! rg -q 'FLOW_SMOKE_OK' "$RUN_LOG" || ! rg -q 'PARTICIPANT_UI_PRIVACY_OK missions=5' "$RUN_LOG" || ! rg -q 'VISUAL_ASSET_OK' "$RUN_LOG" || ! rg -q 'WAYPOINT_BEHAVIOR_OK' "$RUN_LOG" || ! rg -q 'MISSION_FLOW_OK' "$RUN_LOG" || ! rg -q 'MISSION_CATALOG_OK count=5' "$RUN_LOG" || ! rg -q 'BOUNDARY_PHYSICS_OK' "$RUN_LOG" || ! rg -q 'BELT_CONSISTENCY_OK' "$RUN_LOG" || ! rg -q 'NAVIGATION_DIFFICULTY_OK missions=5' "$RUN_LOG" || ! rg -q 'BILLBOARD_PROJECTION_OK' "$RUN_LOG" || ! rg -q 'ASTEROID_BELT_HAZARD_OK' "$RUN_LOG" || ! rg -q 'ASTEROID_BELT_GAMEPLAY_OK' "$RUN_LOG" || ! rg -q 'HULL_RING_FEEDBACK_OK' "$RUN_LOG" || ! rg -q 'ROLE_CLAIM_OK' "$RUN_LOG" || ! rg -q 'SESSION_PROGRESS_OK missions=5' "$RUN_LOG" || ! rg -q 'EXPERIMENT_PIPELINE_TEST_OK' "$RUN_LOG" || ! rg -q 'MENU_INPUT_TEST_OK' "$RUN_LOG" || ! rg -q 'KEYBOARD_SEAT_TEST_OK' "$RUN_LOG" || ! rg -q 'AUDIO_SYSTEM_TEST_OK' "$RUN_LOG" || ! rg -q 'PAUSE_MENU_TEST_OK' "$RUN_LOG" || ! rg -q 'PERFORMANCE_BUDGET_OK' "$RUN_LOG"; then
	print -u2 "DEEP_NAV_FULL_VALIDATION_FAILED: smoke or mission audit did not reach its success sentinel"
	exit 1
fi
print "DEEP_NAV_FULL_VALIDATION_OK"
