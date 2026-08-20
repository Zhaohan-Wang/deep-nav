#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

PROJECT_ROOT="${0:A:h:h}"
GODOT_LAUNCHER="$PROJECT_ROOT/tools/godot-cli"
RUN_LOG="$(mktemp /private/tmp/deep-nav-performance.XXXXXX)"
ENGINE_LOG="$(mktemp /private/tmp/deep-nav-performance-engine.XXXXXX)"
TIMEOUT_MARKER="$(mktemp /private/tmp/deep-nav-performance-timeout.XXXXXX)"
PERF_PID=""
WATCHDOG_PID=""
TIMEOUT_SECONDS=45

cleanup() {
	if [[ -n "$WATCHDOG_PID" ]]; then
		kill "$WATCHDOG_PID" 2>/dev/null || true
	fi
	if [[ -n "$PERF_PID" ]] && kill -0 "$PERF_PID" 2>/dev/null; then
		kill -TERM "$PERF_PID" 2>/dev/null || true
	fi
	rm -f "$RUN_LOG" "$ENGINE_LOG" "$TIMEOUT_MARKER"
}
trap cleanup EXIT INT TERM

"$GODOT_LAUNCHER" \
	--log-file "$ENGINE_LOG" \
	--path "$PROJECT_ROOT" \
	--script res://tools/runtime_performance_test.gd >"$RUN_LOG" 2>&1 &
PERF_PID=$!

(
	sleep "$TIMEOUT_SECONDS"
	if kill -0 "$PERF_PID" 2>/dev/null; then
		print "timeout" >"$TIMEOUT_MARKER"
		kill -TERM "$PERF_PID" 2>/dev/null || true
		sleep 2
		kill -KILL "$PERF_PID" 2>/dev/null || true
	fi
) &
WATCHDOG_PID=$!

set +e
wait "$PERF_PID"
STATUS=$?
set -e
PERF_PID=""
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true
WATCHDOG_PID=""

if [[ -s "$TIMEOUT_MARKER" ]]; then
	print -u2 "PERFORMANCE_VALIDATION_FAILED: 超过 ${TIMEOUT_SECONDS} 秒，已停止测试进程"
	tail -100 "$RUN_LOG" >&2
	exit 1
fi

if (( STATUS != 0 )) || ! rg -q -F 'RUNTIME_PERFORMANCE_OK missions=5 target_fps=120' "$RUN_LOG"; then
	print -u2 "PERFORMANCE_VALIDATION_FAILED"
	rg '^(PERF |RUNTIME_PERFORMANCE_)' "$RUN_LOG" >&2 || tail -100 "$RUN_LOG" >&2
	tail -60 "$ENGINE_LOG" >&2
	exit 1
fi

rg '^(PERF |RUNTIME_PERFORMANCE_)' "$RUN_LOG"
print "PERFORMANCE_VALIDATION_OK"
