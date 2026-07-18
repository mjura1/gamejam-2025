extends SceneTree

# Item "bounty": boots a real battle with a single enemy pawn (so the mark
# is deterministic), grants bounty, checks the badge signal fired with that
# enemy, kills it, and checks the reward was paid. Complements
# test_battle_controller_path.gd's pure-logic on_enemy_died() unit tests
# with a real battle_ui.bounty_marked -> _set_board_badge wiring check and
# a real die() -> on_enemy_died() call.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_bounty.gd --quit-after 4

var battle_instance
var player_manager
var reported := false
var fails := 0

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _initialize():
	print(">>> SMOKE TEST: bounty mark + reward <<<")
	player_manager = root.get_node("PlayerManager")
	battle_instance = BattleBoot.boot(self)
	var enemies: Array[String] = ["enemy_pawn"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()
	player_manager.add_item("bounty", 1) # owned before the first start_player_turn() picks the mark

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	reported = true

	var grid_manager = battle_instance.get_node("GridManager")
	var enemy: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and c.is_enemy and not c.is_obstacle:
			enemy = c
			break

	if enemy == null:
		print("SMOKE TEST FAIL: no enemy pawn found on the board")
		return false

	_check("bounty marks the lone enemy as the target", battle_controller.bounty_target == enemy)
	_check("bounty badge label was attached to the marked enemy",
		is_instance_valid(enemy.get_node_or_null("SlotBadge")))

	var before: int = player_manager.upgrade_items
	enemy.die()
	_check("killing the marked (first-to-die) enemy pays the bounty reward",
		player_manager.upgrade_items == before + 1)
	_check("first_enemy_death_resolved latches after the first death",
		battle_controller.first_enemy_death_resolved)

	if fails == 0:
		print(">>> SMOKE TEST: bounty mark + reward works <<<")
	else:
		print("SMOKE TEST FAIL: %d bounty checks failed" % fails)

	return false
