extends SceneTree

# AUTO FILL / REMOVE ALL smoke test: the two placement-phase buttons should
# only be visible during PLACEMENT, AUTO FILL should place pieces from the
# roster (including duplicate types) up to the 5-piece cap, REMOVE ALL should
# clear the board back to the roster, and both buttons should disappear once
# the battle is confirmed and PLAYER_TURN starts.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_placement_auto_fill.gd --quit-after 5

var all_ok := true
var battle
var ran := false

func _check(condition: bool, label: String):
	if condition:
		print("    ok: %s" % label)
	else:
		all_ok = false
		print("    FAILED: %s" % label)

func _initialize():
	print(">>> SMOKE TEST: placement auto-fill/remove-all <<<")
	battle = BattleBoot.boot_placement_only(self)

	# 6-piece roster (2x pawn + 4 distinct types) so auto-fill has to both
	# handle duplicate types AND stop at the 5-piece cap with 1 piece left over.
	var player_manager = root.get_node("PlayerManager")
	var roster: Array[String] = [
		"friendly_pawn", "friendly_pawn", "friendly_rook",
		"friendly_bishop", "friendly_knight", "friendly_queen",
	]
	player_manager.friendly_party = roster

func _process(_delta: float) -> bool:
	if ran:
		return false

	var battle_controller = battle.get_node("BattleController")
	if battle_controller.current_state == battle_controller.BattleState.INITIALIZING:
		return false # scena se še prebuja
	ran = true

	var battle_ui = battle.get_node("BattleUI")

	_check(battle_ui.placement_actions_row.visible,
		"AUTO FILL/REMOVE ALL row is visible during placement")
	_check(not battle_ui.auto_fill_button.disabled,
		"AUTO FILL starts enabled (board empty, pieces available)")
	_check(battle_ui.remove_all_button.disabled,
		"REMOVE ALL starts disabled (nothing placed yet)")

	battle_ui._on_auto_fill_pressed()
	_check(battle_ui._placed_characters().size() == 5,
		"AUTO FILL places up to the 5-piece cap (6-piece roster)")
	_check(battle_ui.auto_fill_button.disabled,
		"AUTO FILL disables itself once the cap is reached")
	_check(not battle_ui.remove_all_button.disabled,
		"REMOVE ALL enables itself once something is placed")

	battle_ui._on_remove_all_pressed()
	_check(battle_ui._placed_characters().is_empty(),
		"REMOVE ALL clears every placed piece back to the roster")
	_check(not battle_ui.auto_fill_button.disabled,
		"AUTO FILL re-enables itself after REMOVE ALL")
	_check(battle_ui.remove_all_button.disabled,
		"REMOVE ALL disables itself again once the board is empty")

	battle_ui._on_auto_fill_pressed()
	battle_ui.confirm_placement()
	_check(battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN,
		"confirm_placement starts the player turn")
	_check(not battle_ui.placement_actions_row.visible,
		"AUTO FILL/REMOVE ALL row hides once the battle starts")

	if all_ok:
		print(">>> SMOKE TEST: placement auto-fill/remove-all works end to end <<<")
	else:
		print(">>> SMOKE TEST: placement auto-fill/remove-all FAILED - see checks above <<<")
	return false
