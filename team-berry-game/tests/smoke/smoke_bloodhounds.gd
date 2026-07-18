extends SceneTree

# Item "bloodhounds": a friendly wolf spawns on the first player turn and
# acts on its own right after the player ends their turn. Boots a real
# battle with bloodhounds owned and a single enemy pawn seeded right next
# to where the wolf will land, ends the turn, and checks the wolf captured
# it before the enemy turn even started (BattleController.end_player_turn's
# _move_autonomous_allies() runs before start_enemy_turn()).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_bloodhounds.gd --quit-after 6

var battle_instance
var player_manager
var reported := false
var acted := false
var fails := 0

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _initialize():
	print(">>> SMOKE TEST: bloodhounds wolf spawn + autonomous action <<<")
	player_manager = root.get_node("PlayerManager")
	battle_instance = BattleBoot.boot(self)
	var enemies: Array[String] = ["enemy_pawn"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()
	player_manager.add_item("bloodhounds", 1) # owned before the first start_player_turn() spawns it

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	if not acted:
		acted = true

		var grid_manager = battle_instance.get_node("GridManager")
		var wolf: BaseCharacter = null
		var enemy: BaseCharacter = null
		for c in grid_manager.get_all_characters():
			if c is BaseCharacter and not c.is_obstacle:
				if c.is_enemy:
					enemy = c
				elif c.strName == "wolf":
					wolf = c

		_check("a wolf spawned on the first player turn", wolf != null)
		_check("the wolf is registered as a temporary ally (active_party)",
			player_manager.active_party.has("friendly_wolf"))
		_check("exactly one wolf spawned regardless of item count",
			_count_wolves(grid_manager) == 1)

		if wolf == null or enemy == null:
			print("SMOKE TEST FAIL: missing wolf or enemy - aborting")
			return false

		# Teleportiraj sovražnika točno ob volka, znotraj njegovega dosega
		# (move_range 2, 8 smeri - glej wolf.gd), da ga avtonomna akcija
		# zagotovo zajame.
		var target_pos: Vector2i = wolf.grid_pos + Vector2i(1, 0)
		var used_rect: Rect2i = battle_instance.get_node("Map/TileMapLayer").get_used_rect()
		if not grid_manager.is_inside_boundary(target_pos, used_rect):
			target_pos = wolf.grid_pos + Vector2i(-1, 0)

		grid_manager.vacate(enemy.grid_pos)
		enemy.grid_pos = target_pos
		grid_manager.occupy(target_pos, enemy)
		enemy.global_position = grid_manager.grid_to_world(target_pos)

		battle_controller.end_player_turn()
		return false

	# Poll: čakamo, da avtonomna akcija (in morebiten prehod v sovražnikovo
	# potezo) mine, ne da bi preverjali natančno število frameov.
	var grid_manager = battle_instance.get_node("GridManager")
	var enemy_alive := false
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and c.is_enemy and not c.is_obstacle:
			enemy_alive = true
			break

	if enemy_alive and battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN:
		return false # avtonomna akcija (in morda sovražnikova poteza) je še v teku

	reported = true
	_check("the wolf autonomously captured the adjacent enemy", not enemy_alive)

	if fails == 0:
		print(">>> SMOKE TEST: bloodhounds wolf spawn + autonomous action works <<<")
	else:
		print("SMOKE TEST FAIL: %d bloodhounds checks failed" % fails)

	return false

func _count_wolves(grid_manager) -> int:
	var count := 0
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and not c.is_enemy and not c.is_obstacle and c.strName == "wolf":
			count += 1
	return count
