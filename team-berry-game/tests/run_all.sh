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

# --- Known, not-yet-fixed engine errors ------------------------------------
# These are audit findings with a planned fix later in FIX_TODO.md.
# When you land the matching task, delete its line here so run_all.sh starts
# hard-failing on any regression instead of silently tolerating it.
# Currently empty - all known audit findings that used to hit the battle
# smoke test (C2, M3/House) are fixed. Add lines back here if a new,
# understood-but-not-yet-fixed finding starts showing up in this test.
KNOWN_BATTLE_ERROR_PATTERNS=()

check_scene() {
	local label="$1" scene_path="$2"
	local out
	out=$("$GODOT" --headless --path . --scene "$scene_path" --quit-after 2 2>&1)
	local errors
	errors=$(echo "$out" | grep "^ERROR" | grep -v "resources still in use at exit" || true)
	if [ -z "$errors" ]; then
		echo "PASS: $label"
	else
		echo "FAIL: $label"
		echo "$errors" | sed 's/^/    /'
		OVERALL_FAIL=1
	fi
}

echo "== Scene load smoke tests =="
check_scene "main_menu.tscn" "res://Scenes/Menu/main_menu.tscn"
check_scene "map.tscn" "res://Scenes/Map/map.tscn"
echo

echo "== Battle smoke test (res://tests/smoke/smoke_battle.gd) =="
BATTLE_OUT=$("$GODOT" --headless --path . --script res://tests/smoke/smoke_battle.gd --quit-after 4 2>&1)
# "resources still in use at exit" is a harmless engine-shutdown artifact
# (confirmed unrelated to game logic), not a real finding - excluded up
# front so it never counts toward "known outstanding" or fails the build.
BATTLE_ERRORS=$(echo "$BATTLE_OUT" | grep "^ERROR" | grep -v "resources still in use at exit" || true)
UNKNOWN_ERRORS="$BATTLE_ERRORS"
for pattern in "${KNOWN_BATTLE_ERROR_PATTERNS[@]}"; do
	UNKNOWN_ERRORS=$(echo "$UNKNOWN_ERRORS" | grep -vE "$pattern" || true)
done

KNOWN_COUNT=$(( $(echo "$BATTLE_ERRORS" | grep -c "^ERROR" || true) - $(echo "$UNKNOWN_ERRORS" | grep -c "^ERROR" || true) ))
if [ -n "$(echo "$UNKNOWN_ERRORS" | tr -d '[:space:]')" ]; then
	echo "FAIL: smoke_battle - unexpected errors found"
	echo "$UNKNOWN_ERRORS" | sed 's/^/    /'
	OVERALL_FAIL=1
else
	echo "PASS: smoke_battle ($KNOWN_COUNT known outstanding error lines tolerated - see KNOWN_BATTLE_ERROR_PATTERNS)"
fi
echo

if [ "$OVERALL_FAIL" -ne 0 ]; then
	echo "=== RESULT: FAIL ==="
else
	echo "=== RESULT: PASS ==="
fi
exit $OVERALL_FAIL
