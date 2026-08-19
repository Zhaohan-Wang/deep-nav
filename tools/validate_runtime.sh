#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
LOG_FILE="$(mktemp /private/tmp/deep-nav-runtime.XXXXXX.log)"
trap 'rm -f "$LOG_FILE"' EXIT

"$PROJECT_ROOT/tools/godot-cli" \
	--log-file "$LOG_FILE" \
	--path "$PROJECT_ROOT" \
	--script res://tools/runtime_capture.gd

if ! rg -q 'RUNTIME_CAPTURE_OK' "$LOG_FILE"; then
	print -u2 "DEEP_NAV_RUNTIME_VALIDATION_FAILED"
	exit 1
fi
if rg -n 'SCRIPT ERROR|SHADER ERROR|Shader compilation failed|Invalid polygon data|Failed to load script' "$LOG_FILE"; then
	print -u2 "DEEP_NAV_RUNTIME_VALIDATION_FAILED: runtime log contains rendering or script errors"
	exit 1
fi
START_PNG="$PROJECT_ROOT/artifacts/runtime/gameplay_split_start.png"
COOLDOWN_PNG="$PROJECT_ROOT/artifacts/runtime/gameplay_waypoint_cooldown.png"
ARROWS_PNG="$PROJECT_ROOT/artifacts/runtime/gameplay_control_arrows.png"
TITLE_PNG="$PROJECT_ROOT/artifacts/runtime/title_screen.png"
SELECT_PNG="$PROJECT_ROOT/artifacts/runtime/level_select_experiment.png"
HULL_PNG="$PROJECT_ROOT/artifacts/runtime/gameplay_hull_ring_damage.png"
MID_PNG="$PROJECT_ROOT/artifacts/runtime/gameplay_split_mid.png"
APPROACH_PNG="$PROJECT_ROOT/artifacts/runtime/gameplay_planet_approach.png"
BOUNDARY_PNG="$PROJECT_ROOT/artifacts/runtime/gameplay_split_boundary.png"
LEVEL3_PNG="$PROJECT_ROOT/artifacts/runtime/gameplay_level3_corridor.png"
BLOCKER_PNG="$PROJECT_ROOT/artifacts/runtime/gameplay_level3_blocker.png"
EXPLOSION_PNG="$PROJECT_ROOT/artifacts/runtime/gameplay_explosion.png"
RESULT_PNG="$PROJECT_ROOT/artifacts/runtime/mission_result.png"
RESULT_SUCCESS_PNG="$PROJECT_ROOT/artifacts/runtime/mission_result_success.png"
SUMMARY_PNG="$PROJECT_ROOT/artifacts/runtime/mission_summary.png"
SURVEY_1_PNG="$PROJECT_ROOT/artifacts/runtime/survey_page_1.png"
SURVEY_2_PNG="$PROJECT_ROOT/artifacts/runtime/survey_page_2.png"
if [[ ! -s "$TITLE_PNG" || ! -s "$SELECT_PNG" || ! -s "$START_PNG" || ! -s "$COOLDOWN_PNG" || ! -s "$ARROWS_PNG" || ! -s "$HULL_PNG" || ! -s "$MID_PNG" || ! -s "$APPROACH_PNG" || ! -s "$BOUNDARY_PNG" || ! -s "$LEVEL3_PNG" || ! -s "$BLOCKER_PNG" || ! -s "$EXPLOSION_PNG" || ! -s "$RESULT_PNG" || ! -s "$RESULT_SUCCESS_PNG" || ! -s "$SUMMARY_PNG" || ! -s "$SURVEY_1_PNG" || ! -s "$SURVEY_2_PNG" ]] || cmp -s "$TITLE_PNG" "$SELECT_PNG" || cmp -s "$SELECT_PNG" "$START_PNG" || cmp -s "$START_PNG" "$COOLDOWN_PNG" || cmp -s "$COOLDOWN_PNG" "$ARROWS_PNG" || cmp -s "$ARROWS_PNG" "$HULL_PNG" || cmp -s "$HULL_PNG" "$MID_PNG" || cmp -s "$MID_PNG" "$APPROACH_PNG" || cmp -s "$APPROACH_PNG" "$BOUNDARY_PNG" || cmp -s "$BOUNDARY_PNG" "$LEVEL3_PNG" || cmp -s "$LEVEL3_PNG" "$BLOCKER_PNG" || cmp -s "$BLOCKER_PNG" "$EXPLOSION_PNG" || cmp -s "$EXPLOSION_PNG" "$RESULT_PNG" || cmp -s "$RESULT_PNG" "$RESULT_SUCCESS_PNG" || cmp -s "$RESULT_SUCCESS_PNG" "$SUMMARY_PNG" || cmp -s "$SUMMARY_PNG" "$SURVEY_1_PNG" || cmp -s "$SURVEY_1_PNG" "$SURVEY_2_PNG"; then
	print -u2 "DEEP_NAV_RUNTIME_VALIDATION_FAILED: captures missing or map did not move"
	exit 1
fi
print "DEEP_NAV_RUNTIME_VALIDATION_OK"
