extends SceneTree

# Enemy curses (Scripts/Curses/): boots a real battle, force-assigns each of
# the 3 curses onto a single lone enemy pawn (active_enemies overridden to
# just ["enemy_pawn"] so no other enemy dilutes the flash-count/AI checks),
# and exercises the real BattleController turn machinery. Also covers
# King.Cleanse's curse-clearing-on-conversion (base_character.clear_curse) -
# see _run_king_cleanse_stage for why that spawns its OWN separate enemy
# rather than reusing "enemy".
#
# frenzy and snowfall are driven through the REAL AI pipeline
# (battle_controller.start_enemy_turn()) since neither cares about allies.
# stunning_gaze is exercised by calling curse.on_action_taken() DIRECTLY
# instead: find_visible_enemies() (used by the curse to pick a stun target)
# uses the exact same direction/range geometry as calculate_valid_targets()'
# capture branch, so any ally close enough for the curse to "see" is also
# close enough for calculate_best_move()'s capture-priority step to just
# capture it outright on a real AI turn - killing the ally before the curse
# hook could stun it. Calling the hook directly tests the real effect code
# without that (correct, unrelated) AI behavior getting in the way.
#
# IMPORTANT (matches smoke_enemy_turn_pacing.gd/smoke_courier_package.gd's
# pattern, NOT smoke_item_use.gd's): BattleController.start_enemy_turn()/
# end_player_turn() are coroutines that `await get_tree().create_timer(...)`.
# `_process(delta) -> bool` is called directly by the engine's MainLoop, not
# through GDScript's own `await` call convention - if `_process()` itself
# contains an `await` that suspends, the engine never resumes it (the test
# just silently stalls after the first suspension, zero errors printed,
# looking like a hang). So this test is a FRAME-POLLED STATE MACHINE: each
# BattleController call is fired WITHOUT `await`, and `_process()` polls
# `current_state`/`turn_count` across subsequent, ordinary frames until the
# coroutine completes on the engine's own schedule - always returns false.
#
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_curses.gd --quit-after 400

var battle_instance
var player_manager
var curse_data # CurseData avtoload - ni bare identifikator, glej opombo v _initialize

var reported := false
var fails := 0

# Stanja te "state machine" - vsako se sproži enkrat, nato "poll" čaka na
# pogoj preden preide na naslednje.
enum Stage {
	WAIT_PLAYER_TURN,
	SETUP_FRENZY, WAIT_FRENZY,
	SETUP_SNOWFALL, WAIT_SNOWFALL,
	STUNNING_GAZE, # popolnoma sinhrono, glej _run_stunning_gaze_stage
	KING_CLEANSE, # popolnoma sinhrono, glej _run_king_cleanse_stage
	SETUP_TICK_DOWN, WAIT_TICK_DOWN,
	DONE,
}
var stage: int = Stage.WAIT_PLAYER_TURN
var turn_count_before: int = 0

var grid_manager
var move_highlighter
var used_rect: Rect2i
var enemy: BaseCharacter = null
var ally: BaseCharacter = null
var king: BaseCharacter = null
var cleanse_target: BaseCharacter = null
var gaze # BaseCurse (stunning_gaze) instanca

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _initialize():
	print(">>> SMOKE TEST: enemy curses (frenzy/snowfall/stunning_gaze) <<<")
	player_manager = root.get_node("PlayerManager")
	# Avtoloadi (CurseData ipd.) niso vezani na goli identifikator v ENTRY
	# skripti --script zagona - root.get_node() namesto tega.
	curse_data = root.get_node("CurseData")
	battle_instance = BattleBoot.boot(self)
	var enemies: Array[String] = ["enemy_pawn"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()
	# A king (King.Cleanse) is needed alongside the default pawn ally, for
	# the curse-clearing-on-conversion check (see king.gd._do_cleanse).
	var roster: Array[String] = ["friendly_pawn", "friendly_king"]
	player_manager.friendly_party = roster

func _teleport(character: BaseCharacter, pos: Vector2i):
	grid_manager.vacate(character.grid_pos)
	character.grid_pos = pos
	grid_manager.occupy(pos, character)
	character.global_position = grid_manager.grid_to_world(pos)

func _stun_badge_visible(character: BaseCharacter) -> bool:
	var badge := character.get_node_or_null("StunBadge")
	return badge != null and badge.visible

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not is_instance_valid(battle_controller):
		return false

	match stage:
		Stage.WAIT_PLAYER_TURN:
			if battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
				return false # still waiting for placement to complete

			grid_manager = battle_instance.get_node("GridManager")
			move_highlighter = battle_instance.get_node("MoveHighlighter")
			used_rect = battle_instance.get_node("Map/TileMapLayer").get_used_rect()

			# Every stage below teleports pieces onto hand-picked coordinates -
			# clear the randomly-spawned obstacles first so an occasional house
			# landing on one of those tiles doesn't flake the test with a
			# "GridManager.occupy: polje already zasedeno" error.
			for c in grid_manager.get_all_characters():
				if c is BaseCharacter and c.is_obstacle:
					grid_manager.vacate(c.grid_pos)
					c.queue_free()

			for c in grid_manager.get_all_characters():
				if c is BaseCharacter and not c.is_obstacle:
					if c.is_enemy and enemy == null:
						enemy = c
					elif not c.is_enemy and c.strName == "king" and king == null:
						king = c
					elif not c.is_enemy and ally == null:
						ally = c

			if enemy == null or ally == null or king == null:
				print("SMOKE TEST FAIL: could not find an enemy pawn + a pawn ally + a king ally on the board")
				reported = true
				return false

			stage = Stage.SETUP_FRENZY

		Stage.SETUP_FRENZY:
			enemy.apply_curse(curse_data.create_curse("frenzy"))
			_check("frenzy curse assigned", enemy.curse != null and enemy.curse.id == "frenzy")

			# Open tile with plenty of room below it - blind-seek chases toward
			# the board's vertical center, so a lone pawn in the open always
			# has a valid move as long as it isn't pinned against an edge/obstacle.
			_teleport(enemy, Vector2i(used_rect.position.x, used_rect.position.y))

			turn_count_before = battle_controller.turn_count
			battle_controller.start_enemy_turn() # fire-and-forget, see header note
			stage = Stage.WAIT_FRENZY

		Stage.WAIT_FRENZY:
			if not (battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN \
					and battle_controller.turn_count > turn_count_before):
				return false # enemy turn still in progress

			_check("frenzied enemy produced 2 move flashes (1 base + 1 extra action)",
				move_highlighter.enemy_move_flashes.size() == 2)
			stage = Stage.SETUP_SNOWFALL

		Stage.SETUP_SNOWFALL:
			grid_manager.clear_all_fog()
			enemy.curse = curse_data.create_curse("snowfall")
			_teleport(enemy, Vector2i(used_rect.position.x, used_rect.position.y))

			turn_count_before = battle_controller.turn_count
			battle_controller.start_enemy_turn() # fire-and-forget
			stage = Stage.WAIT_SNOWFALL

		Stage.WAIT_SNOWFALL:
			if not (battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN \
					and battle_controller.turn_count > turn_count_before):
				return false # enemy turn still in progress

			_check("fog_nodes is non-empty after a snowfall-cursed enemy moved",
				not grid_manager.fog_nodes.is_empty())
			_check("snowfall covered the enemy's own landing tile",
				grid_manager.fog_nodes.has(enemy.grid_pos))
			stage = Stage.STUNNING_GAZE

		Stage.STUNNING_GAZE:
			_run_stunning_gaze_stage(battle_controller)
			stage = Stage.KING_CLEANSE

		Stage.KING_CLEANSE:
			_run_king_cleanse_stage()
			stage = Stage.SETUP_TICK_DOWN

		Stage.SETUP_TICK_DOWN:
			# Remove the enemy first - it's adjacent to the ally, and
			# end_player_turn() cascades into a real start_enemy_turn() which
			# would otherwise just capture the ally we're about to inspect
			# (unrelated, correct AI behavior - just not what this checks).
			grid_manager.vacate(enemy.grid_pos)
			enemy.queue_free()
			ally.stunned_turns = 1

			turn_count_before = battle_controller.turn_count
			battle_controller.end_player_turn() # fire-and-forget
			stage = Stage.WAIT_TICK_DOWN

		Stage.WAIT_TICK_DOWN:
			if not (battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN \
					and battle_controller.turn_count > turn_count_before):
				return false # cascade still in progress

			_check("end_player_turn ticks stunned_turns down to 0",
				is_instance_valid(ally) and ally.stunned_turns == 0)
			stage = Stage.DONE

		Stage.DONE:
			reported = true
			if fails == 0:
				print(">>> SMOKE_CURSES_OK <<<")
			else:
				print("SMOKE TEST FAIL: %d curse checks failed" % fails)

	return false

# stunning_gaze je popolnoma sinhrona (curse.on_action_taken ne await-a
# ničesar) - varno jo je pognati v celoti znotraj enega _process() klica.
func _run_stunning_gaze_stage(battle_controller) -> void:
	gaze = curse_data.create_curse("stunning_gaze")
	enemy.curse = gaze
	_teleport(enemy, Vector2i(3, 3))
	_teleport(ally, Vector2i(4, 3)) # adjacent, in enemy's line of sight

	ally.stunned_turns = 0
	gaze.on_action_taken(enemy, battle_controller)
	_check("stunning_gaze stunned the closest visible ally",
		ally.stunned_turns == curse_data.get_param("stunning_gaze", "duration", 1))
	_check("stunning_gaze set its own cooldown",
		gaze.cooldown_left == curse_data.get_param("stunning_gaze", "cooldown", 2))
	_check("stunned ally has no valid targets", ally.calculate_valid_targets().is_empty())
	_check("stunned ally cannot activate abilities", not ally.activate_ability(1))
	_check("battle_ui set the StunBadge on the stunned ally", _stun_badge_visible(ally))

	# Cooldown valve: re-triggering the hook immediately must NOT re-stun.
	ally.stunned_turns = 0
	var cooldown_before: int = gaze.cooldown_left
	gaze.on_action_taken(enemy, battle_controller)
	_check("cooldown blocks an immediate re-stun", ally.stunned_turns == 0)
	_check("cooldown ticked down by 1", gaze.cooldown_left == cooldown_before - 1)

	# Exhaust the cooldown, then confirm the gaze can stun again.
	while gaze.cooldown_left > 0:
		gaze.on_action_taken(enemy, battle_controller)
	ally.stunned_turns = 0
	gaze.on_action_taken(enemy, battle_controller)
	_check("stunning_gaze can stun again once its cooldown is exhausted", ally.stunned_turns > 0)

# King.Cleanse: converted enemies must NOT keep their curse as an ally (glej
# king.gd._do_cleanse -> base_character.clear_curse). Spawns a FRESH, SEPARATE
# second enemy (enemy_bishop) just for this stage instead of reusing "enemy"
# (the pawn used by every earlier stage) for two reasons:
#   1. Converting the board's ONLY enemy would empty player_manager.active_enemies
#      and trigger a real, immediate victory (enemyGone()), tearing down the
#      whole battle scene mid-test.
#   2. Having it exist from the start (like "enemy") would make it act during
#      the earlier frenzy/snowfall start_enemy_turn() calls too, polluting
#      move_highlighter.enemy_move_flashes and breaking those stages' counts.
# Fully synchronous (activate_ability -> _execute_ability -> _do_cleanse has
# no awaits), safe to run inline within one _process() call.
func _run_king_cleanse_stage() -> void:
	# Move the primary enemy out of the way FIRST - it may currently be
	# sitting on (3,3)/(3,5) from the stunning_gaze stage above.
	_teleport(enemy, Vector2i(used_rect.position.x, used_rect.end.y - 1))

	var bishop_scene: PackedScene = battle_instance.enemy_pieces["enemy_bishop"]
	grid_manager.spawn_character(bishop_scene, grid_manager.grid_to_world(Vector2i(3, 5)))
	cleanse_target = grid_manager.get_character_at(Vector2i(3, 5))
	# king.gd._do_cleanse calls player_manager.convert_enemy_to_ally("enemy_bishop", ...),
	# which only does its bookkeeping if "enemy_bishop" is actually a
	# tracked active enemy - register it, matching what battle.gd's normal
	# spawn loop does for every enemy it places.
	player_manager.active_enemies.append("enemy_bishop")

	cleanse_target.apply_curse(curse_data.create_curse("frenzy"))
	_check("cleanse target has a curse going into the cleanse", cleanse_target.curse != null)
	_check("cleanse target has a CurseMarker before cleanse",
		cleanse_target.get_node_or_null("CurseMarker") != null)

	_teleport(king, Vector2i(3, 3)) # 2 tiles north of cleanse_target, unblocked LOS

	var ok: bool = king.activate_ability(1) # slot 1 = Cleanse (king.gd.ABILITY_DEFS[0])
	_check("King.Cleanse activates successfully", ok)
	_check("cleanse target is converted to an ally",
		is_instance_valid(cleanse_target) and not cleanse_target.is_enemy)
	_check("cleansed piece no longer carries its curse",
		is_instance_valid(cleanse_target) and cleanse_target.curse == null)
	_check("cleansed piece's CurseMarker is gone",
		is_instance_valid(cleanse_target) and cleanse_target.get_node_or_null("CurseMarker") == null)
	_check("the primary enemy is untouched and battle continues",
		is_instance_valid(enemy) and enemy.is_enemy and is_instance_valid(battle_instance))
