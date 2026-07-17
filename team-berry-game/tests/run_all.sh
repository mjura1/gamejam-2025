#!/usr/bin/env bash
# Runs every automated check for team-berry-game in one shot.
# Usage: team-berry-game/tests/run_all.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

GODOT="${GODOT_BIN:-godot4}"
OVERALL_FAIL=0

if [ ! -d ".godot" ]; then
	echo "== Importing assets (first run) =="
	"$GODOT" --headless --import --path . >/dev/null 2>&1
fi

echo "== Unit tests (res://tests/unit) =="
"$GODOT" --headless --path . --script res://tests/run_unit_tests.gd 2>&1 | grep -v "^Godot Engine\|^Vulkan\|^WARNING: Editor Settings"
UNIT_STATUS=${PIPESTATUS[0]}
if [ "$UNIT_STATUS" -ne 0 ]; then
	echo "FAIL: unit tests (exit $UNIT_STATUS)"
	OVERALL_FAIL=1
else
	echo "PASS: unit tests"
fi
echo

# If a new understood-but-not-yet-fixed error starts showing up in a smoke
# test, allowlist it with check_script's expect_str/errors mechanism (or add
# a dedicated allowlist here) rather than letting run_all.sh silently pass -
# see git history for the KNOWN_BATTLE_ERROR_PATTERNS mechanism this replaced,
# which became permanent dead weight once every known finding got fixed.

check_scene() {
	local label="$1" scene_path="$2" quit_after="${3:-2}"
	local out
	out=$("$GODOT" --headless --path . --scene "$scene_path" --quit-after "$quit_after" 2>&1)
	local errors
	# <<< (here-string) instead of `echo "$out" | grep` - with `pipefail` set,
	# a pipe here races grep's early-exit (on match) against echo still
	# writing the rest of $out; the resulting SIGPIPE makes pipefail report
	# the pipeline as failed even though grep matched. A here-string has no
	# separate writer process, so there's nothing to race.
	# ^SCRIPT ERROR too: GDScript runtime faults (invalid assignment, null
	# reference, etc.) print as "SCRIPT ERROR:", not "ERROR:" - a plain
	# ^ERROR grep let a real crash (Nil map_camera in
	# MapController._center_and_zoom_camera) through silently, since the
	# script kept running past the bad line and still printed expect_str.
	errors=$(grep -E "^(ERROR|SCRIPT ERROR)" <<< "$out" | grep -v "resources still in use at exit" || true)
	if [ -z "$errors" ]; then
		echo "PASS: $label"
	else
		echo "FAIL: $label"
		echo "$errors" | sed 's/^/    /'
		OVERALL_FAIL=1
	fi
}

check_script() {
	# expect_str: a substring that MUST appear in the output for a real pass -
	# not just "no errors". A script that silently no-ops (as smoke_battle_end/
	# smoke_battle_loss did before their MainLoop return-value bug was found)
	# produces zero ERROR lines too, so absence of errors alone proves nothing.
	local label="$1" script_path="$2" quit_after="$3" expect_str="$4"
	local out
	out=$("$GODOT" --headless --path . --script "$script_path" --quit-after "$quit_after" 2>&1)
	local errors
	# <<< (here-string) instead of `echo "$out" | grep` - see check_scene()
	# above for why a pipe here can misreport pass as fail under `pipefail`.
	# ^SCRIPT ERROR too: GDScript runtime faults (invalid assignment, null
	# reference, etc.) print as "SCRIPT ERROR:", not "ERROR:" - a plain
	# ^ERROR grep let a real crash (Nil map_camera in
	# MapController._center_and_zoom_camera) through silently, since the
	# script kept running past the bad line and still printed expect_str.
	errors=$(grep -E "^(ERROR|SCRIPT ERROR)" <<< "$out" | grep -v "resources still in use at exit" || true)
	if [ -n "$errors" ]; then
		echo "FAIL: $label - unexpected errors"
		echo "$errors" | sed 's/^/    /'
		OVERALL_FAIL=1
	elif [ -n "$expect_str" ] && ! grep -qF "$expect_str" <<< "$out"; then
		echo "FAIL: $label - expected confirmation not found: \"$expect_str\""
		OVERALL_FAIL=1
	else
		echo "PASS: $label"
	fi
}

echo "== Scene load smoke tests =="
check_scene "main_menu.tscn" "res://Scenes/Menu/main_menu.tscn"
check_scene "map.tscn" "res://Scenes/Map/map.tscn"
echo

echo "== Main menu Start -> GameFlow._initialize_game() smoke test =="
check_script "smoke_start_new_game" "res://tests/smoke/smoke_start_new_game.gd" 5 \
	"SMOKE TEST: map initialized cleanly via the real Start flow"
echo

echo "== Campfire room -> Campfire scene -> REST -> BACK -> map smoke test =="
check_script "smoke_campfire_flow" "res://tests/smoke/smoke_campfire_flow.gd" 8 \
	"SMOKE TEST: campfire flow completed cleanly, back on the map"
echo

echo "== Battle smoke test (res://tests/smoke/smoke_battle.gd) =="
check_script "smoke_battle" "res://tests/smoke/smoke_battle.gd" 4 ""
echo

echo "== Battle-end smoke tests (C7/T5.1, C8/T5.2) =="
check_script "smoke_battle_end (WIN path)" "res://tests/smoke/smoke_battle_end.gd" 15 \
	"SMOKE TEST: Battle scene left the tree - transition happened cleanly"
check_script "smoke_battle_loss (LOSS path, map-leak check)" "res://tests/smoke/smoke_battle_loss.gd" 15 \
	"SMOKE TEST: old (detached) map instance was freed - no leak"
echo

echo "== Enemy turn pacing / move visualizer smoke test =="
check_script "smoke_enemy_turn_pacing" "res://tests/smoke/smoke_enemy_turn_pacing.gd" 130 \
	"SMOKE TEST: enemy turn completed after"
check_script "smoke_enemy_turn_stale_reference (regression)" "res://tests/smoke/smoke_enemy_turn_stale_reference.gd" 150 \
	"SMOKE TEST: enemy turn completed without crashing"
check_script "smoke_enemy_turn_highlight_reset (regression)" "res://tests/smoke/smoke_enemy_turn_highlight_reset.gd" 15 \
	"SMOKE TEST: leftover flash correctly cleared when new enemy turn started"
echo

echo "== test_sandbox.tscn smoke test =="
check_script "smoke_test_sandbox (regression)" "res://tests/smoke/smoke_test_sandbox.gd" 5 \
	"SMOKE TEST: all"
echo

echo "== AI obstacle-filter smoke test =="
check_script "smoke_ai_ignores_obstacles (regression)" "res://tests/smoke/smoke_ai_ignores_obstacles.gd" 10 \
	"SMOKE TEST: obstacle correctly ignored"
echo

echo "== Pause menu smoke test =="
check_script "smoke_pause_menu" "res://tests/smoke/smoke_pause_menu.gd" 80 \
	"SMOKE TEST: escape resumed - menu hidden and tree unpaused again"
echo

if [ "$OVERALL_FAIL" -ne 0 ]; then
	echo "=== RESULT: FAIL ==="
else
	echo "=== RESULT: PASS ==="
fi
exit $OVERALL_FAIL
