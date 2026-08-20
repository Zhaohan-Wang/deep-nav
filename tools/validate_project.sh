#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
GODOT_LAUNCHER="$PROJECT_ROOT/tools/godot-cli"
TEST_QUIT_FRAMES=1800
FATAL_PATTERN='SCRIPT ERROR|Parse Error|SHADER ERROR|Shader compilation failed|Failed to load script|Cannot open file.*res://'
RUN_FULL=false
RUN_MAPS=false
RUN_PERFORMANCE=false
PASSED=0
SUITE_STARTED=$SECONDS

FAST_TESTS=(
	"流程冒烟|res://tools/flow_smoke.gd|FLOW_SMOKE_OK"
	"任务流程|res://tools/mission_flow_test.gd|MISSION_FLOW_OK"
	"四关问卷|res://tools/four_mission_questionnaire_test.gd|FOUR_MISSION_QUESTIONNAIRE_OK"
	"碎石带一致性|res://tools/belt_consistency_test.gd|BELT_CONSISTENCY_OK"
	"碎石伤害|res://tools/asteroid_belt_gameplay_test.gd|ASTEROID_BELT_GAMEPLAY_OK"
	"飞船转向|res://tools/ship_turning_test.gd|SHIP_TURNING_OK"
	"实验数据链路|res://tools/experiment_pipeline_test.gd|EXPERIMENT_PIPELINE_TEST_OK"
	"菜单与设置|res://tools/menu_input_test.gd|MENU_INPUT_TEST_OK"
	"性能结构预算|res://tools/performance_budget_test.gd|PERFORMANCE_BUDGET_OK"
)

MAP_TESTS=(
	"关卡目录|res://tools/mission_audit.gd|MISSION_CATALOG_OK count=5"
	"边界封闭|res://tools/boundary_physics_test.gd|BOUNDARY_PHYSICS_OK"
	"导航难度|res://tools/navigation_difficulty_test.gd|NAVIGATION_DIFFICULTY_OK missions=5"
	"碎石带风险|res://tools/asteroid_belt_hazard_test.gd|ASTEROID_BELT_HAZARD_OK"
)

SPECIALTY_TESTS=(
	"被试隐私|res://tools/participant_ui_privacy_test.gd|PARTICIPANT_UI_PRIVACY_OK missions=5"
	"视觉资源|res://tools/visual_asset_test.gd|VISUAL_ASSET_OK"
	"航点行为|res://tools/waypoint_behavior_test.gd|WAYPOINT_BEHAVIOR_OK"
	"航点投影|res://tools/billboard_projection_test.gd|BILLBOARD_PROJECTION_OK"
	"船体反馈|res://tools/hull_feedback_test.gd|HULL_RING_FEEDBACK_OK"
	"实验视觉反馈|res://tools/experiment_visual_feedback_test.gd|EXPERIMENT_VISUAL_FEEDBACK_OK"
	"岗位认领|res://tools/role_claim_test.gd|ROLE_CLAIM_OK"
	"实验进度|res://tools/session_progress_test.gd|SESSION_PROGRESS_OK missions=5"
	"双鼠标分流|res://tools/raw_mouse_separation_test.gd|RAW_MOUSE_SEPARATION_OK slots=2 seats=2 cursors=independent"
	"双键盘分流|res://tools/keyboard_seat_test.gd|KEYBOARD_SEAT_TEST_OK"
	"音频系统|res://tools/audio_system_test.gd|AUDIO_SYSTEM_TEST_OK"
	"暂停菜单|res://tools/pause_menu_test.gd|PAUSE_MENU_TEST_OK"
)

usage() {
	print "用法: tools/validate_project.sh [--maps] [--full] [--performance]"
	print "  默认          只跑日常关键回归"
	print "  --maps        再跑地图、边界和难度检查"
	print "  --full        再跑全部专项回归（包含 --maps）"
	print "  --performance 关键回归通过后实测五关帧率"
}

for argument in "$@"; do
	case "$argument" in
		--maps) RUN_MAPS=true ;;
		--full) RUN_FULL=true; RUN_MAPS=true ;;
		--performance) RUN_PERFORMANCE=true ;;
		--help|-h) usage; exit 0 ;;
		*) print -u2 "未知参数: $argument"; usage >&2; exit 2 ;;
	esac
done

print_failure_logs() {
	local run_log="$1"
	local engine_log="$2"
	print -u2 "最近的测试输出："
	tail -80 "$run_log" >&2 2>/dev/null || true
	print -u2 "最近的引擎输出："
	tail -80 "$engine_log" >&2 2>/dev/null || true
}

run_startup_smoke() {
	local run_log engine_log command_status started
	run_log="$(mktemp /private/tmp/deep-nav-startup.XXXXXX)"
	engine_log="$(mktemp /private/tmp/deep-nav-startup-engine.XXXXXX)"
	started=$SECONDS
	set +e
	"$GODOT_LAUNCHER" \
		--headless \
		--log-file "$engine_log" \
		--path "$PROJECT_ROOT" \
		--quit-after 8 \
		-- --dual-window-smoke >"$run_log" 2>&1
	command_status=$?
	set -e
	if (( command_status != 0 )) || rg -q "$FATAL_PATTERN" "$run_log" "$engine_log"; then
		print -u2 "FAIL 项目启动（$((SECONDS - started)) 秒）"
		print_failure_logs "$run_log" "$engine_log"
		rm -f "$run_log" "$engine_log"
		exit 1
	fi
	rm -f "$run_log" "$engine_log"
	(( PASSED += 1 ))
	print "PASS 项目启动（$((SECONDS - started)) 秒）"
}

run_test() {
	local name="$1"
	local script="$2"
	local sentinel="$3"
	local run_log engine_log command_status started
	run_log="$(mktemp /private/tmp/deep-nav-test.XXXXXX)"
	engine_log="$(mktemp /private/tmp/deep-nav-test-engine.XXXXXX)"
	started=$SECONDS
	set +e
	"$GODOT_LAUNCHER" \
		--headless \
		--log-file "$engine_log" \
		--path "$PROJECT_ROOT" \
		--quit-after "$TEST_QUIT_FRAMES" \
		--script "$script" >"$run_log" 2>&1
	command_status=$?
	set -e
	if (( command_status != 0 )) || ! rg -q -F "$sentinel" "$run_log" || rg -q "$FATAL_PATTERN" "$run_log" "$engine_log"; then
		print -u2 "FAIL $name（$((SECONDS - started)) 秒）"
		print_failure_logs "$run_log" "$engine_log"
		rm -f "$run_log" "$engine_log"
		exit 1
	fi
	rm -f "$run_log" "$engine_log"
	(( PASSED += 1 ))
	print "PASS $name（$((SECONDS - started)) 秒）"
}

run_specs() {
	local spec name remainder script sentinel
	for spec in "$@"; do
		name="${spec%%|*}"
		remainder="${spec#*|}"
		script="${remainder%%|*}"
		sentinel="${remainder#*|}"
		run_test "$name" "$script" "$sentinel"
	done
}

print "开始日常关键回归"
run_startup_smoke
run_specs "${FAST_TESTS[@]}"

if [[ "$RUN_MAPS" == true ]]; then
	print "开始地图专项回归"
	run_specs "${MAP_TESTS[@]}"
fi

if [[ "$RUN_FULL" == true ]]; then
	print "开始完整专项回归"
	run_specs "${SPECIALTY_TESTS[@]}"
fi

if [[ "$RUN_PERFORMANCE" == true ]]; then
	print "开始五关图形性能实测"
	"$PROJECT_ROOT/tools/validate_performance.sh"
fi

print "DEEP_NAV_VALIDATION_OK tests=$PASSED elapsed=$((SECONDS - SUITE_STARTED))s"
