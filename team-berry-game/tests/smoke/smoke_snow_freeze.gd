extends SceneTree

# Snow rework (plans/SNOW_REWORK_PLAN.md): bug fix (reveal_area clears BOTH
# fog systems + Scorched Earth), single-tile move-clear, and the
# freeze/thaw/death mechanic. Every effect under test
# (reveal_area/cover_area/cover_area_curse/execute_move/
# update_fog_after_turn_start) is synchronous, EXCEPT die() which
# queue_free()s the character - that free only completes on a later frame,
# so the death case needs a real (short) frame-polled wait. Everything
# before it runs inline within one _process() call, same reasoning as
# smoke_curses.gd's synchronous stages.
#
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_snow_freeze.gd --quit-after 400

enum Stage { WAIT_PLAYER_TURN, RUN_SYNC_CASES, WAIT_DEATH_FRAME, DONE }
var stage: int = Stage.WAIT_PLAYER_TURN

var battle_instance
var player_manager
var grid_manager
var battle_controller
var used_rect: Rect2i
var death_pawn: BaseCharacter = null
var freeze_pawn: BaseCharacter = null

var reported := false
var fails := 0

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
	var roster: Array[String] = ["friendly_pawn", "friendly_pawn", "friendly_queen"]
	player_manager.friendly_party = roster
	# check_battle_end() (now also called from start_player_turn, see M3) would
	# declare an instant victory with zero enemies and tear down the whole
	# battle scene - keep one lone enemy alive, parked out of the way, so the
	# battle stays live for the whole test.
	var enemies: Array[String] = ["enemy_pawn"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()

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

	match stage:
		Stage.WAIT_PLAYER_TURN:
			if battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
				return false # still waiting for placement to complete

			grid_manager = battle_instance.get_node("GridManager")
			used_rect = battle_instance.get_node("Map/TileMapLayer").get_used_rect()

			# Every stage below teleports pieces onto hand-picked coordinates -
			# clear the randomly-spawned obstacles first, same reasoning as
			# smoke_curses.gd.
			for c in grid_manager.get_all_characters():
				if c is BaseCharacter and c.is_obstacle:
					grid_manager.vacate(c.grid_pos)
					c.queue_free()

			# Park the lone enemy (kept alive so check_battle_end() doesn't
			# declare an instant victory - see _initialize) in the far corner,
			# well away from every hand-picked test coordinate below.
			for c in grid_manager.get_all_characters():
				if c is BaseCharacter and c.is_enemy:
					_teleport(c, used_rect.end - Vector2i(1, 1))

			stage = Stage.RUN_SYNC_CASES

		Stage.RUN_SYNC_CASES:
			_run_bug_fix_case()
			_run_scorched_earth_case()
			_run_single_tile_clear_case()
			_run_fog_tile_click_through_case()
			_run_freeze_case()
			_run_same_turn_thaw_case()
			_run_death_case_setup()
			stage = Stage.WAIT_DEATH_FRAME

		Stage.WAIT_DEATH_FRAME:
			# die() calls queue_free() - the character stays is_instance_valid()
			# until the engine actually frees it on a later frame. Poll instead
			# of asserting immediately.
			if is_instance_valid(death_pawn):
				return false
			_check("piece surrounded 3 consecutive turn-starts dies",
				grid_manager.get_character_at(_death_pos()) == null)
			stage = Stage.DONE

		Stage.DONE:
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

# Case 2: Queen "Scorched Earth" (blast_clears_snow flag) clears the
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

func _first_pawn(exclude: Array = []) -> BaseCharacter:
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and not c.is_enemy and not c.is_obstacle \
				and c.strName != "queen" and not (c in exclude):
			return c
	return null

# Case 3: single-tile move clear (M2) - moving onto a snowed tile clears
# ONLY the landing tile, neighbors stay snowed (no more 3x3 auto-clear).
func _run_single_tile_clear_case() -> void:
	var pawn: BaseCharacter = _first_pawn()
	if pawn == null:
		print("SMOKE TEST FAIL: could not find a pawn ally for the single-tile clear case")
		fails += 1
		return

	var target := Vector2i(4, 4)
	_teleport(pawn, Vector2i(4, 5))

	grid_manager.clear_all_fog()
	grid_manager.clear_all_curse_fog()
	grid_manager.cover_area([target]) # ambientna megla na ciljnem polju
	var neighbors: Array[Vector2i] = [
		target + Vector2i(1, 0), target + Vector2i(-1, 0),
		target + Vector2i(0, 1), target + Vector2i(0, -1),
	]
	grid_manager.cover_area_curse(neighbors) # prekletstvena megla na vseh 4 sosedih

	pawn.execute_move(target)

	_check("landing tile is clear of ambient fog after the move",
		not grid_manager.fog_nodes.has(target))
	_check("landing tile is clear of curse fog after the move",
		not grid_manager.curse_fog_nodes.has(target))
	var all_neighbors_still_snowed := true
	for n in neighbors:
		if not grid_manager.curse_fog_nodes.has(n):
			all_neighbors_still_snowed = false
	_check("neighboring tiles remain snowed (no more 3x3 auto-clear)",
		all_neighbors_still_snowed)

	grid_manager.clear_all_fog()
	grid_manager.clear_all_curse_fog()

# Case 4: guards against the .tscn click-through edit being silently lost -
# full click simulation isn't practical headless (see plan §5), so this just
# asserts the ColorRect's mouse_filter stayed IGNORE.
func _run_fog_tile_click_through_case() -> void:
	var fog_node = GridManager.FOG_TILE_SCENE.instantiate()
	var color_rect = fog_node.get_node_or_null("ColorRect")
	_check("fog tile ColorRect is click-transparent (MOUSE_FILTER_IGNORE)",
		is_instance_valid(color_rect) and color_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	fog_node.queue_free()

const FREEZE_POS := Vector2i(6, 6)

func _ring_with_ambient_fog(pos: Vector2i) -> void:
	# Ambient fog never decays on its own - avoids decay interference between
	# the freeze/thaw checks below, and also proves ambient counts as snow
	# (decision 1 in the plan).
	grid_manager.clear_all_fog()
	grid_manager.clear_all_curse_fog()
	var neighbors: Array[Vector2i] = [
		pos + Vector2i(1, 0), pos + Vector2i(-1, 0),
		pos + Vector2i(0, 1), pos + Vector2i(0, -1),
	]
	grid_manager.cover_area(neighbors)

# Case 5: freeze - ringed for SNOW_FREEZE_TURNS consecutive turn-starts.
func _run_freeze_case() -> void:
	freeze_pawn = _first_pawn()
	if freeze_pawn == null:
		print("SMOKE TEST FAIL: could not find a pawn ally for the freeze case")
		fails += 1
		return

	_teleport(freeze_pawn, FREEZE_POS)
	freeze_pawn.snow_trapped_turns = 0
	freeze_pawn.snow_frozen = false
	_ring_with_ambient_fog(FREEZE_POS)

	battle_controller.update_fog_after_turn_start()

	_check("piece is snow_frozen after being ringed 1 turn-start",
		freeze_pawn.snow_frozen)
	_check("frozen ally has no valid move targets",
		freeze_pawn.calculate_valid_targets().is_empty())

# Case 6: same-turn thaw - breaking the ring immediately unfreezes, even
# mid-turn (no need to wait for the next turn start). Reuses the SAME pawn
# instance from the freeze case above - _first_pawn() picks off
# grid_manager.get_all_characters() (Dictionary.values()), whose iteration
# order shifts as pieces move, so re-deriving "the first pawn" here could
# silently grab a different (unfrozen) piece.
func _run_same_turn_thaw_case() -> void:
	if freeze_pawn == null or not is_instance_valid(freeze_pawn) or not freeze_pawn.snow_frozen:
		print("SMOKE TEST FAIL: freeze case did not leave a frozen pawn for the thaw case")
		fails += 1
		return

	# Breaking the ring on one side (e.g. a rescuing move revealing that
	# tile) must thaw immediately.
	grid_manager.reveal_area([FREEZE_POS + Vector2i(1, 0)])

	_check("is_snow_frozen_now() thaws immediately once the ring breaks",
		not freeze_pawn.is_snow_frozen_now())
	_check("thawed ally has valid move targets again",
		not freeze_pawn.calculate_valid_targets().is_empty())
	_check("snow_trapped_turns resets to 0 on thaw",
		freeze_pawn.snow_trapped_turns == 0)

	grid_manager.clear_all_fog()
	grid_manager.clear_all_curse_fog()

func _death_pos() -> Vector2i:
	return Vector2i(2, 2)

# Case 7: death - ringed for SNOW_DEATH_TURNS consecutive turn-starts.
func _run_death_case_setup() -> void:
	death_pawn = _first_pawn()
	if death_pawn == null:
		print("SMOKE TEST FAIL: could not find a pawn ally for the death case")
		fails += 1
		stage = Stage.DONE
		return

	_teleport(death_pawn, _death_pos())
	death_pawn.snow_trapped_turns = 0
	death_pawn.snow_frozen = false
	_ring_with_ambient_fog(_death_pos())

	for i in range(3):
		battle_controller.update_fog_after_turn_start()
