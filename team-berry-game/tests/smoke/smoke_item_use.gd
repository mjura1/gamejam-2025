extends SceneTree

# Boots a real battle through placement into PLAYER_TURN (same as
# smoke_battle.gd), grants an extra_move item, then drives the real
# battle_ui.use_item() path (the same function the item drawer's drag-drop
# calls, see battle_ui.gd._resolve_item_drop) and checks moves_remaining
# increments and the item is consumed exactly once.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_item_use.gd --quit-after 4

var battle_instance
var player_manager
var reported := false

func _initialize():
	print(">>> SMOKE TEST: item use (extra_move) via battle_ui.use_item() <<<")
	battle_instance = BattleBoot.boot(self)
	player_manager = root.get_node("PlayerManager")

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	reported = true

	player_manager.add_item("extra_move", 1)
	var battle_ui = battle_instance.get_node("BattleUI")

	var moves_before: int = battle_controller.moves_remaining
	var ok: bool = battle_ui.use_item("extra_move", Vector2i.ZERO)

	var fails := 0
	if not ok:
		print("FAIL: use_item should return true for a fresh extra_move")
		fails += 1
	if battle_controller.moves_remaining != moves_before + 1:
		print("FAIL: moves_remaining should increment by 1 (was %d, now %d)" % [moves_before, battle_controller.moves_remaining])
		fails += 1
	if player_manager.get_item_count("extra_move") != 0:
		print("FAIL: extra_move should be consumed from inventory after use")
		fails += 1

	var ok_again: bool = battle_ui.use_item("extra_move", Vector2i.ZERO)
	if ok_again:
		print("FAIL: use_item should refuse when the player owns none")
		fails += 1

	if fails == 0:
		print(">>> SMOKE TEST: extra_move item used cleanly, moves incremented, inventory decremented <<<")
	else:
		print("SMOKE TEST FAIL: %d item-use checks failed" % fails)

	return false
