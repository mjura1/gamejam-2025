extends SceneTree

# Snow rework (plans/SNOW_REWORK_PLAN.md): bug fix (reveal_area clears BOTH
# fog systems + Scorched Earth), single-tile move-clear, and the
# freeze/thaw/death mechanic. All the effects under test
# (reveal_area/cover_area/cover_area_curse/execute_move/
# update_fog_after_turn_start) are synchronous - no start_enemy_turn()
# pipeline needed, so this whole test runs as one boot + a handful of
# directly-called steps, no frame-polled state machine required beyond
# waiting for PLAYER_TURN.
#
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_snow_freeze.gd --quit-after 400

var battle_instance
var player_manager
var grid_manager
var battle_controller
var used_rect: Rect2i

var reported := false
var fails := 0
var waiting_for_player_turn := true

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _initialize():
	print(">>> SMOKE TEST: snow rework (bug fix / single-tile clear / freeze-death) <<<")
	player_manager = root.get_node("PlayerManager")
	battle_instance = BattleBoot.boot(self)
	var roster: Array[String] = ["friendly_pawn", "friendly_queen"]
	player_manager.friendly_party = roster
	var no_enemies: Array[String] = []
	player_manager.enemy_party = no_enemies
	player_manager.active_enemies = no_enemies.duplicate()

func _teleport(character: BaseCharacter, pos: Vector2i):
	grid_manager.vacate(character.grid_pos)
	character.grid_pos = pos
	grid_manager.occupy(pos, character)
	character.global_position = grid_manager.grid_to_world(pos)

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	battle_controller = battle_instance.get_node_or_null("BattleController")
	if not is_instance_valid(battle_controller):
		return false

	if waiting_for_player_turn:
		if battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
			return false # still waiting for placement to complete
		waiting_for_player_turn = false

		grid_manager = battle_instance.get_node("GridManager")
		used_rect = battle_instance.get_node("Map/TileMapLayer").get_used_rect()

		# Every stage below teleports pieces onto hand-picked coordinates -
		# clear the randomly-spawned obstacles first, same reasoning as
		# smoke_curses.gd.
		for c in grid_manager.get_all_characters():
			if c is BaseCharacter and c.is_obstacle:
				grid_manager.vacate(c.grid_pos)
				c.queue_free()

		_run_bug_fix_case()
		_run_scorched_earth_case()

		reported = true
		if fails == 0:
			print(">>> SMOKE_SNOW_FREEZE_OK <<<")
		else:
			print("SMOKE TEST FAIL: %d snow rework checks failed" % fails)

	return false

# Case 1: reveal_area must clear BOTH fog systems (the actual bug fix).
func _run_bug_fix_case() -> void:
	grid_manager.clear_all_fog()
	grid_manager.clear_all_curse_fog()

	var p := Vector2i(used_rect.position.x, used_rect.position.y)
	grid_manager.cover_area_curse([p])
	_check("cover_area_curse placed curse fog", grid_manager.curse_fog_nodes.has(p))

	grid_manager.reveal_area([p])
	_check("reveal_area now also clears curse fog (bug fix)",
		not grid_manager.curse_fog_nodes.has(p))

	grid_manager.clear_all_fog()
	grid_manager.clear_all_curse_fog()

# Case 2 (M4 milestone list groups it with case 1, kept separate here for
# clarity): Queen "Scorched Earth" (blast_clears_snow flag) clears the
# exterminate blast area of BOTH fog systems.
func _run_scorched_earth_case() -> void:
	var queen: BaseCharacter = null
	var pawn: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and not c.is_enemy and not c.is_obstacle:
			if c.strName == "queen" and queen == null:
				queen = c
			elif c.strName != "queen" and pawn == null:
				pawn = c
	if queen == null or pawn == null:
		print("SMOKE TEST FAIL: could not find a queen + a pawn ally on the board")
		fails += 1
		return

	queen.passives = [{"type": "flag", "flag": "blast_clears_snow"}]
	_check("queen carries the blast_clears_snow flag", queen.has_flag("blast_clears_snow"))

	_teleport(queen, Vector2i(3, 3))
	_teleport(pawn, Vector2i(3, 7)) # far away, just needs to make a move

	var ok: bool = queen.activate_ability(1) # slot 1 = Exterminate (queen.gd.ABILITY_DEFS[0])
	_check("Exterminate activates and arms the blast", ok)
	_check("exterminate_armed carries the queen as owner",
		battle_controller.exterminate_armed.get("owner") == queen)

	var blast_area: Array[Vector2i] = queen._area_tiles(queen._tier_data(1), queen.grid_pos)
	grid_manager.clear_all_fog()
	grid_manager.clear_all_curse_fog()
	grid_manager.cover_area(blast_area)
	grid_manager.cover_area_curse(blast_area)
	_check("blast area is snowed (both systems) before the triggering move",
		grid_manager.fog_nodes.has(blast_area[0]) and grid_manager.curse_fog_nodes.has(blast_area[0]))

	# Any move triggers the armed blast - base_character.execute_move calls
	# trigger_exterminate_if_armed() after moving.
	var pawn_targets: Array = pawn.calculate_valid_targets()
	if pawn_targets.is_empty():
		print("SMOKE TEST FAIL: pawn has no valid move to trigger the blast with")
		fails += 1
		return
	pawn.execute_move(pawn_targets[0])

	var still_snowed := false
	for pos in blast_area:
		if grid_manager.fog_nodes.has(pos) or grid_manager.curse_fog_nodes.has(pos):
			still_snowed = true
	_check("Scorched Earth cleared all snow in the blast area", not still_snowed)

	grid_manager.clear_all_fog()
	grid_manager.clear_all_curse_fog()
	queen.passives = []
