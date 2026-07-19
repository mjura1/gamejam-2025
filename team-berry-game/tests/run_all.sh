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

echo "== Main menu Play -> Mode Select CLASSIC -> GameFlow._initialize_game() smoke test =="
check_script "smoke_start_new_game" "res://tests/smoke/smoke_start_new_game.gd" 5 \
	"SMOKE TEST: map initialized cleanly via the real Start flow"
echo

echo "== Mode Select overlay open/close smoke test =="
check_script "smoke_mode_select" "res://tests/smoke/smoke_mode_select.gd" 5 \
	"SMOKE_MODE_SELECT_OK"
echo

echo "== Infinite mode tier-3 continuation smoke test =="
check_script "smoke_infinite_mode" "res://tests/smoke/smoke_infinite_mode.gd" 8 \
	"SMOKE_INFINITE_MODE_OK"
echo

echo "== Tutorial stage AI-disabled smoke test =="
check_script "smoke_tutorial_ai_disabled" "res://tests/smoke/smoke_tutorial_ai_disabled.gd" 8 \
	"SMOKE_TUTORIAL_AI_OK"
echo

echo "== Campfire room -> Campfire scene -> REST -> BACK -> map smoke test =="
check_script "smoke_campfire_flow" "res://tests/smoke/smoke_campfire_flow.gd" 8 \
	"SMOKE TEST: campfire flow completed cleanly, back on the map"
echo

echo "== Campfire upgrade panel spend-flow smoke test =="
check_script "smoke_upgrade_panel" "res://tests/smoke/smoke_upgrade_panel.gd" 8 \
	"SMOKE TEST: upgrade panel spend flow completed cleanly"
echo

echo "== Shop room -> Shop scene -> LEAVE -> map smoke test =="
check_script "smoke_shop_map_flow" "res://tests/smoke/smoke_shop_map_flow.gd" 8 \
	"SMOKE TEST: shop map flow completed cleanly, back on the map"
echo

echo "== Shop buy/sell panel smoke test =="
check_script "smoke_shop" "res://tests/smoke/smoke_shop.gd" 8 \
	"SMOKE TEST: shop buy/sell flow completed cleanly"
echo

echo "== Battle smoke test (res://tests/smoke/smoke_battle.gd) =="
check_script "smoke_battle" "res://tests/smoke/smoke_battle.gd" 4 \
	"SMOKE TEST: battle booted through placement into PLAYER_TURN"
echo

echo "== Placement phase smoke test =="
check_script "smoke_placement" "res://tests/smoke/smoke_placement.gd" 5 \
	"SMOKE TEST: placement phase works end to end"
echo

echo "== Placement auto-fill/remove-all smoke test =="
check_script "smoke_placement_auto_fill" "res://tests/smoke/smoke_placement_auto_fill.gd" 5 \
	"SMOKE TEST: placement auto-fill/remove-all works end to end"
echo

echo "== Item use smoke test (battle_ui.use_item / extra_move) =="
check_script "smoke_item_use" "res://tests/smoke/smoke_item_use.gd" 4 \
	"SMOKE TEST: extra_move item used cleanly, moves incremented, inventory decremented"
echo

echo "== Item: barricade + flare smoke test =="
check_script "smoke_barricade_flare" "res://tests/smoke/smoke_barricade_flare.gd" 4 \
	"SMOKE TEST: barricade + flare items work"
echo

echo "== Ability activation smoke test =="
check_script "smoke_abilities" "res://tests/smoke/smoke_abilities.gd" 4 \
	"SMOKE TEST: ability activated cleanly and use count decremented"
echo

echo "== Ability UI pipeline smoke test (all 12 abilities via the real UI) =="
check_script "smoke_ability_ui_pipeline" "res://tests/smoke/smoke_ability_ui_pipeline.gd" 8 \
	"SMOKE TEST: all 12 abilities exercised cleanly through the real UI pipeline"
echo

echo "== Item: vicious_knights bonus move smoke test =="
check_script "smoke_vicious_knights" "res://tests/smoke/smoke_vicious_knights.gd" 4 \
	"SMOKE TEST: vicious_knights bonus move works, once-per-turn latch holds"
echo

echo "== Item: bounty mark + reward smoke test =="
check_script "smoke_bounty" "res://tests/smoke/smoke_bounty.gd" 4 \
	"SMOKE TEST: bounty mark + reward works"
echo

echo "== Item: spyglass risk tiles smoke test =="
check_script "smoke_spyglass" "res://tests/smoke/smoke_spyglass.gd" 4 \
	"SMOKE TEST: spyglass risk tiles work"
echo

echo "== Item: bloodhounds wolf spawn + autonomous action smoke test =="
check_script "smoke_bloodhounds" "res://tests/smoke/smoke_bloodhounds.gd" 8 \
	"SMOKE TEST: bloodhounds wolf spawn + autonomous action works"
echo

echo "== Item: divine_intervention rescue smoke test =="
check_script "smoke_divine_intervention" "res://tests/smoke/smoke_divine_intervention.gd" 10 \
	"SMOKE TEST: divine_intervention rescue works"
echo

echo "== Item: courier_package mark + victory reward smoke test =="
check_script "smoke_courier_package" "res://tests/smoke/smoke_courier_package.gd" 10 \
	"SMOKE TEST: courier_package mark + victory reward works"
echo

echo "== Item: castle king-protection smoke test =="
check_script "smoke_castle" "res://tests/smoke/smoke_castle.gd" 4 \
	"SMOKE TEST: castle item works"
echo

echo "== Item: mounted_hunters knight-jump smoke test =="
check_script "smoke_mounted_hunters" "res://tests/smoke/smoke_mounted_hunters.gd" 4 \
	"SMOKE TEST: mounted_hunters works"
echo

echo "== Item: fortress rook-house line smoke test =="
check_script "smoke_fortress" "res://tests/smoke/smoke_fortress.gd" 4 \
	"SMOKE TEST: fortress item works"
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

echo "== Enemy curses smoke test (frenzy/snowfall/stunning_gaze) =="
check_script "smoke_curses" "res://tests/smoke/smoke_curses.gd" 400 \
	"SMOKE_CURSES_OK"
echo

echo "== Enemy inspection smoke test (red preview + status panel) =="
check_script "smoke_inspect" "res://tests/smoke/smoke_inspect.gd" 4 \
	"SMOKE_INSPECT_OK"
echo

echo "== AI improvements smoke test (value-aware capture + danger avoidance) =="
check_script "smoke_ai" "res://tests/smoke/smoke_ai.gd" 4 \
	"SMOKE_AI_OK"
echo

echo "== AI difficulty minimax smoke test (defended-pawn trap) =="
check_script "smoke_ai_minimax" "res://tests/smoke/smoke_ai_minimax.gd" 8 \
	"SMOKE_AI_MINIMAX_OK"
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
