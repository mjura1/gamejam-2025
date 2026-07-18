extends SceneTree

# Item "courier_package": mirrors bounty for allies, resolved at victory
# instead of on death. Boots a real battle with a single enemy pawn (for a
# deterministic victory), grants courier_package, checks the real mark +
# badge wiring, kills the enemy to force a WIN, and checks the reward was
# paid once the real (deferred) check_battle_end() victory branch runs -
# same pattern as smoke_battle_end.gd's WIN path. Complements
# test_battle_controller_path.gd's pure _maybe_pay_courier_reward() tests
# (survive/died/no-courier) with the real end-to-end wiring.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_courier_package.gd --quit-after 10

var player_manager
var picked := false
var killed_enemy := false
var checked_result := false

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)

func _initialize():
	print(">>> SMOKE TEST: courier_package mark + victory reward <<<")
	player_manager = root.get_node("PlayerManager")
	BattleBoot.boot(self)
	var enemies: Array[String] = ["enemy_pawn"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()
	player_manager.add_item("courier_package", 1) # owned before the first start_player_turn() picks the courier

func _process(_delta: float) -> bool:
	var battle_instance = root.get_node_or_null("Battle")

	if battle_instance == null:
		if not checked_result:
			checked_result = true
			_check("battle scene left the tree (victory transition happened)", true)
			var item_data = root.get_node("ItemData") # autoloads aren't global identifiers in --script mode
			_check("courier_package reward was paid on victory",
				player_manager.upgrade_items == player_manager.UPGRADE_ITEMS_PER_WIN \
					+ item_data.get_reward("courier_package"))
			print(">>> SMOKE TEST: courier_package mark + victory reward works <<<")
		return false

	if killed_enemy:
		return false # give the deferred victory transition more frames to fire

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	if not picked:
		picked = true
		var courier = battle_controller.courier
		_check("courier_package marks a living ally as the courier", is_instance_valid(courier))
		_check("courier badge label was attached", is_instance_valid(courier) \
			and is_instance_valid(courier.get_node_or_null("SlotBadge")))
		return false

	var grid_manager = battle_instance.get_node("GridManager")
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and c.is_enemy and not c.is_obstacle:
			c.die()
	killed_enemy = true
	battle_controller.check_battle_end()
	return false
