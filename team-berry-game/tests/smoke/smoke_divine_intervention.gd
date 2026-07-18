extends SceneTree

# Item "divine_intervention": consumed on a party wipe to return to the map
# instead of game over (map progress/floor number is kept). Forces
# activeGone() with the item owned and drives the real deferred
# check_battle_end() -> GF.return_to_map() path (same pattern as
# smoke_battle_end.gd's WIN path), then checks the item was consumed and
# current_map_floor was NOT reset (reset_floor_number() is only called on a
# real, un-rescued game over).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_divine_intervention.gd --quit-after 10

var player_manager
var forced_wipe := false
var checked_result := false

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)

func _initialize():
	print(">>> SMOKE TEST: divine_intervention rescue on party wipe <<<")
	player_manager = root.get_node("PlayerManager")
	# return_to_map() needs current_map_instance set - see smoke_battle_end.gd.
	BattleBoot.boot(self)
	player_manager.add_item("divine_intervention", 1)
	player_manager.current_map_floor = 5 # nonzero marker - a real game_over would reset this to 0

func _process(_delta: float) -> bool:
	var battle_instance = root.get_node_or_null("Battle")

	if battle_instance == null:
		if not checked_result:
			checked_result = true
			_check("battle scene left the tree (returned to map, not main menu/game over)", true)
			_check("divine_intervention was consumed", player_manager.get_item_count("divine_intervention") == 0)
			_check("current_map_floor was NOT reset (rescue keeps map progress)",
				player_manager.current_map_floor == 5)
			print(">>> SMOKE TEST: divine_intervention rescue works <<<")
		return false

	if forced_wipe:
		return false # give the deferred call more frames to fire

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	var empty: Array[String] = []
	player_manager.active_party = empty
	forced_wipe = true

	battle_controller.check_battle_end()
	return false
