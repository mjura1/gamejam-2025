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
	NEW_CURSES, # popolnoma sinhrono, glej _run_new_curses_stage (fey_step/changeling/abduction/entangle/wraith_cloak/contagion)
	SETUP_BLOODLUST, WAIT_BLOODLUST,
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

func _root_badge_visible(character: BaseCharacter) -> bool:
	var badge := character.get_node_or_null("RootBadge")
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
			grid_manager.clear_all_curse_fog()
			enemy.curse = curse_data.create_curse("snowfall")
			_teleport(enemy, Vector2i(used_rect.position.x, used_rect.position.y))

			turn_count_before = battle_controller.turn_count
			battle_controller.start_enemy_turn() # fire-and-forget
			stage = Stage.WAIT_SNOWFALL

		Stage.WAIT_SNOWFALL:
			if not (battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN \
					and battle_controller.turn_count > turn_count_before):
				return false # enemy turn still in progress

			_check("curse_fog_nodes is non-empty after a snowfall-cursed enemy moved",
				not grid_manager.curse_fog_nodes.is_empty())
			_check("snowfall covered the enemy's own landing tile",
				grid_manager.curse_fog_nodes.has(enemy.grid_pos))
			stage = Stage.STUNNING_GAZE

		Stage.STUNNING_GAZE:
			_run_stunning_gaze_stage(battle_controller)
			stage = Stage.NEW_CURSES

		Stage.NEW_CURSES:
			_run_new_curses_stage(battle_controller)
			stage = Stage.SETUP_BLOODLUST

		Stage.SETUP_BLOODLUST:
			_run_setup_bloodlust_stage(battle_controller)
			stage = Stage.WAIT_BLOODLUST

		Stage.WAIT_BLOODLUST:
			if not (battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN \
					and battle_controller.turn_count > turn_count_before):
				return false # enemy turn still in progress

			_check("bloodlust-cursed enemy produced 2 move flashes (1 capture + 1 bonus action)",
				move_highlighter.enemy_move_flashes.size() == 2)
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

# Novih 6 prekletstev (fey_step/entangle/changeling/abduction/wraith_cloak/
# contagion) - vse popolnoma sinhrone (nobena od njihovih on_action_taken/
# on_applied ne await-a ničesar), varno jih je pognati v celoti znotraj enega
# _process() klica, enako kot _run_stunning_gaze_stage zgoraj. bloodlust je
# IZLOČEN v svoj lasten SETUP/WAIT par (glej spodaj) - potrebuje pravi
# start_enemy_turn()/AI pipeline, ne direktnega hook klica, in "ally" bi bila
# ob zajetju uničena (queue_free), zato porabi SVOJO začasno figuro namesto
# skupne "ally" spremenljivke, ki jo potrebujejo poznejše faze.
func _run_new_curses_stage(battle_controller) -> void:
	# --- fey_step: nosilec ne sme zajemati ---
	var fey = curse_data.create_curse("fey_step") # BaseCurse - glej "gaze" opombo zgoraj, zakaj netipizirano
	enemy.curse = fey
	_teleport(enemy, Vector2i(5, 5))
	_teleport(ally, Vector2i(5, 6)) # sosednje polje - bi bilo sicer zajemljivo
	enemy.has_spotted_player = true
	enemy.last_known_player_pos = ally.grid_pos
	var fey_action: Dictionary = enemy.calculate_best_move()
	_check("fey_step-cursed enemy never offers a capture on an adjacent ally",
		fey_action.get("target_pos", Vector2i(-999, -999)) != ally.grid_pos)

	# --- fey_step: blink (forsiran na 100% verjetnost, da ni flaky) ---
	var original_blink_chance = curse_data.get_param("fey_step", "blink_chance", 0.5)
	curse_data._curses["fey_step"]["blink_chance"] = 1.0
	_teleport(enemy, Vector2i(used_rect.position.x, used_rect.position.y))
	var before_blink: Vector2i = enemy.grid_pos
	fey.on_action_taken(enemy, battle_controller)
	_check("fey_step blink (100% forced) moved the enemy to a new tile",
		is_instance_valid(enemy) and enemy.grid_pos != before_blink)
	_check("grid_manager occupancy follows the fey_step blink",
		grid_manager.get_character_at(enemy.grid_pos) == enemy)
	curse_data._curses["fey_step"]["blink_chance"] = original_blink_chance

	# --- entangle: ukorenini najbližjega vidnega zaveznika ---
	var tangle = curse_data.create_curse("entangle") # BaseCurse - glej "gaze" opombo zgoraj, zakaj netipizirano
	enemy.curse = tangle
	_teleport(enemy, Vector2i(3, 3))
	_teleport(ally, Vector2i(4, 3)) # sosednje, v sovražnikovem vidnem polju
	ally.rooted_turns = 0
	tangle.on_action_taken(enemy, battle_controller)
	_check("entangle rooted the closest visible ally",
		ally.rooted_turns == curse_data.get_param("entangle", "duration", 1))
	_check("battle_ui set the RootBadge on the rooted ally", _root_badge_visible(ally))

	var remaining_targets: Array = ally.calculate_valid_targets()
	var only_captures := true
	for pos in remaining_targets:
		var t = grid_manager.get_character_at(pos)
		if t == null or t.is_enemy == ally.is_enemy:
			only_captures = false
	_check("rooted ally's remaining valid targets (if any) are capture-only", only_captures)
	ally.rooted_turns = 0

	# --- changeling: zamenja mesto z najbližjim soborcem ---
	var bishop_scene: PackedScene = battle_instance.enemy_pieces["enemy_bishop"]
	grid_manager.spawn_character(bishop_scene, grid_manager.grid_to_world(Vector2i(2, 2)))
	var partner: BaseCharacter = grid_manager.get_character_at(Vector2i(2, 2))
	_teleport(enemy, Vector2i(1, 1))
	var change = curse_data.create_curse("changeling") # BaseCurse - glej "gaze" opombo zgoraj, zakaj netipizirano
	enemy.curse = change
	var enemy_pos_before: Vector2i = enemy.grid_pos
	var partner_pos_before: Vector2i = partner.grid_pos
	change.on_action_taken(enemy, battle_controller)
	_check("changeling swapped positions with its closest fellow enemy",
		enemy.grid_pos == partner_pos_before and partner.grid_pos == enemy_pos_before)
	_check("grid_manager occupancy reflects the changeling swap",
		grid_manager.get_character_at(enemy_pos_before) == partner \
			and grid_manager.get_character_at(partner_pos_before) == enemy)
	grid_manager.vacate(partner.grid_pos)
	partner.queue_free()

	# --- abduction: zamenja mesto z najbližjim vidnim zaveznikom ---
	_teleport(enemy, Vector2i(3, 3))
	_teleport(ally, Vector2i(4, 3))
	var abduct = curse_data.create_curse("abduction") # BaseCurse - glej "gaze" opombo zgoraj, zakaj netipizirano
	enemy.curse = abduct
	var enemy_pos_before2: Vector2i = enemy.grid_pos
	var ally_pos_before2: Vector2i = ally.grid_pos
	abduct.on_action_taken(enemy, battle_controller)
	_check("abduction swapped positions with the closest visible ally",
		enemy.grid_pos == ally_pos_before2 and ally.grid_pos == enemy_pos_before2)
	# Po zamenjavi je "enemy" na (4,3) in "ally" na (3,3) - KING_CLEANSE
	# stopnja spodaj rabi (3,3)/(3,5) prosta, SETUP_TICK_DOWN pa rabi "ally"
	# pravilno registriranega v grid_managerju. NAJPREJ umaknemo sovražnika,
	# ŠELE NATO zaveznika na (4,3) - obratni vrstni red bi trčil (zaveznik bi
	# poskušal zasesti polje, ki ga sovražnik še vedno zaseda, kar
	# grid_manager.occupy samo tiho zavrne - "ally" bi ostal brez veljavnega
	# grid_pos vpisa v occupied slovarju).
	_teleport(enemy, Vector2i(used_rect.position.x, used_rect.position.y))
	_teleport(ally, Vector2i(4, 3))

	# --- wraith_cloak: on_applied TAKOJ pokrije lastno polje ---
	grid_manager.clear_all_curse_fog()
	_teleport(enemy, Vector2i(used_rect.position.x, used_rect.position.y))
	enemy.apply_curse(curse_data.create_curse("wraith_cloak"))
	_check("wraith_cloak covers its own tile the instant it's applied",
		grid_manager.curse_fog_nodes.has(enemy.grid_pos))
	grid_manager.clear_all_curse_fog()

	# --- contagion: pokrije + območje IN označi svoja polja kot "spreading" ---
	var contagion = curse_data.create_curse("contagion") # BaseCurse - glej "gaze" opombo zgoraj, zakaj netipizirano
	enemy.curse = contagion
	_teleport(enemy, Vector2i(used_rect.position.x, used_rect.position.y))
	contagion.on_action_taken(enemy, battle_controller)
	_check("contagion covered the enemy's own landing tile",
		grid_manager.curse_fog_nodes.has(enemy.grid_pos))
	_check("contagion registered its tile as spreading",
		grid_manager.curse_fog_spread.has(enemy.grid_pos))
	grid_manager.clear_all_curse_fog()

# Prekletstvo "bloodlust": porabi SVOJO začasno zavezniško figuro (ne skupno
# "ally"), ker jo bo sovražnik dejansko zajel - "ally" mora preživeti do
# SETUP_TICK_DOWN stopnje spodaj. Vodeno skozi PRAVI start_enemy_turn()
# pipeline (ne direkten hook klic) - bonus akcija je vezana v
# BattleController.start_enemy_turn()-ovo zanko, ne v curse.on_action_taken.
var bloodlust_target: BaseCharacter = null

func _run_setup_bloodlust_stage(battle_controller) -> void:
	grid_manager.clear_all_curse_fog()

	var pawn_scene: PackedScene = battle_instance.friendly_pieces["friendly_pawn"]
	grid_manager.spawn_character(pawn_scene, grid_manager.grid_to_world(Vector2i(used_rect.position.x + 1, used_rect.position.y)))
	bloodlust_target = grid_manager.get_character_at(Vector2i(used_rect.position.x + 1, used_rect.position.y))

	enemy.curse = curse_data.create_curse("bloodlust")
	enemy.has_spotted_player = true
	_teleport(enemy, Vector2i(used_rect.position.x, used_rect.position.y))
	enemy.last_known_player_pos = bloodlust_target.grid_pos

	turn_count_before = battle_controller.turn_count
	battle_controller.start_enemy_turn() # fire-and-forget, see header note

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
