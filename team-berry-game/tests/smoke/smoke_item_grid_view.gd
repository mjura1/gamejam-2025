extends SceneTree

# Boots a real battle through placement into PLAYER_TURN (same as
# smoke_battle.gd), grants a couple of items, drives battle_ui's item-toggle
# handler directly (same "drive handlers directly" style as
# smoke_mode_select.gd/smoke_post_battle_summary.gd) and checks:
# - the item grid builds one icon per owned item type
# - selecting an ally piece afterward closes the item view (§3.3's confirmed
#   "selection always wins" precedence rule, see
#   BATTLE_UI_CONTEXTUAL_PANEL_PLAN.md)
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_item_grid_view.gd --quit-after 4

var battle_instance
var player_manager
var reported := false

func _initialize():
	print(">>> SMOKE TEST: item grid view + selection-closes-item-view precedence <<<")
	battle_instance = BattleBoot.boot(self)
	player_manager = root.get_node("PlayerManager")

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	reported = true

	var battle_ui = battle_instance.get_node("BattleUI")
	var map_behaviour = battle_instance.get_node("Map")

	# Direct dict mutation (not add_item()) deliberately avoids emitting
	# items_changed here - that signal is already connected to
	# _rebuild_item_grid() (see _ready()), and queue_free() on the grid's old
	# children is deferred to end-of-frame, so triggering multiple rebuilds
	# synchronously in the same frame (as repeated add_item() calls would)
	# leaves stale not-yet-freed children counted alongside the new ones.
	# Setting the dict directly and doing exactly ONE explicit
	# _rebuild_item_grid() call below avoids that same-frame pileup.
	player_manager.owned_items["extra_move"] = 2
	player_manager.owned_items["blink_step"] = 1
	var expected_types := 0
	for id in player_manager.owned_items:
		if player_manager.owned_items[id] > 0:
			expected_types += 1

	var fails := 0

	battle_ui._on_item_toggle_pressed()
	if not battle_ui._item_view_open:
		print("FAIL: item view should be open after toggling")
		fails += 1
	# queue_free() defers actual removal to end-of-frame - a stale child from
	# an EARLIER rebuild (e.g. the "NO ITEMS" label _ready() builds when the
	# battle starts with an empty inventory) is still attached right after
	# this synchronous call, so filter out anything already queued for
	# deletion instead of trusting get_child_count() directly.
	var item_grid = battle_ui.get_node("%ItemGrid")
	var live_count := 0
	for c in item_grid.get_children():
		if not c.is_queued_for_deletion():
			live_count += 1
	if live_count != expected_types:
		print("FAIL: item grid should have %d icons (one per owned item type), has %d" % [expected_types, live_count])
		fails += 1

	var placed: Array = battle_ui._placed_characters()
	if placed.is_empty():
		print("FAIL: expected at least one placed ally to select")
		fails += 1
	else:
		map_behaviour.select_character_via_ui(placed[0])
		if battle_ui._item_view_open:
			print("FAIL: selecting an ally should close the item view")
			fails += 1

	if fails == 0:
		print(">>> SMOKE TEST: item grid builds correctly and selection closes it <<<")
	else:
		print("SMOKE TEST FAIL: %d item-grid-view checks failed" % fails)

	return false
