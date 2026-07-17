extends SceneTree
# Drives EVERY one of the 12 piece abilities through the REAL UI entry points
# (battle_ui._on_ability_pressed, map_behaviour.begin_ability_targeting,
# map_behaviour._resolve_pending_ability) instead of calling
# character.activate_ability() directly, since a real crash (reported by a
# teammate) turned out to be a UI-glue bug, not an ability-logic bug:
# begin_ability_targeting() internally cleared map_behaviour's board
# selection to swap highlight modes, which synchronously nulled out
# battle_ui._shown_character via _clear_detail_panel() before the caller
# read it again - crashing on any targeted ability (Longshot, Reposition).
# This test specifically checks that class of bug across all 12 abilities:
# does the detail panel stay populated with the right character right after
# pressing "Use Ability", for both targeted and non-targeted abilities - plus
# a basic functional sanity check per ability so a future regression in the
# ability logic itself would also surface here.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_ability_ui_pipeline.gd --quit-after 8

var battle_instance
var grid_manager
var battle_controller
var battle_ui
var map_behaviour
var player_manager
var fails := 0

func _initialize():
	print(">>> SMOKE TEST: exercising all 12 abilities through the real UI pipeline <<<")

	player_manager = root.get_node("PlayerManager")
	player_manager.setStarting()
	player_manager.resetActives()
	# active_enemies/active_party track pieces by NAME STRING, not instance -
	# this test spawns extra ad-hoc "enemy_pawn"s beyond the real roster and
	# kills several of them, which would otherwise exhaust the real 3-entry
	# active_enemies list and trigger a genuine (test-artifact) GAME_OVER
	# mid-run. Pad it so the actual win condition never fires here - this
	# test is checking the ability UI pipeline, not battle-end bookkeeping.
	for i in range(30):
		player_manager.active_enemies.append("enemy_pawn")

	var gf = root.get_node("GF")
	var map_scene: PackedScene = load("res://Scenes/Map/map.tscn")
	gf.current_map_instance = map_scene.instantiate()
	gf.current_map_instance.name = "MapInstance"
	gf.game_initialized = true

	var battle_scene: PackedScene = load("res://Scenes/Map/battle.tscn")
	battle_instance = battle_scene.instantiate()
	# instantiate() already builds the whole node structure synchronously
	# (only the _ready() cascade is deferred to the first frame - see the
	# note below), so this reference is safe to grab immediately.
	battle_controller = battle_instance.get_node("BattleController")
	# battle.gd._ready() ends by calling battle_controller.initialize_battle(),
	# which sets PLACEMENT or PLAYER_TURN and would otherwise race our own
	# state/budget overrides below (observed as flaky CI failures: if
	# initialize_battle() fires AFTER our test already spawned pieces and
	# set high budgets, _has_friendly_pieces() sees them and calls
	# start_player_turn(), silently resetting moves/abilities_remaining back
	# down mid-test). Connecting here, before add_child(), guarantees this
	# fires exactly once battle.gd's own _ready() has actually completed.
	battle_controller.state_changed.connect(_on_battle_initialized, CONNECT_ONE_SHOT)
	root.add_child(battle_instance)
	current_scene = battle_instance

func _on_battle_initialized(_new_state):
	# initialize_battle() has now run, but other siblings (BattleUI, Map)
	# may not have had THEIR _ready() called yet if they come later in
	# child order during this same first-frame cascade (see
	# tests/framework/battle_boot.gd's note on the same add_child() quirk) -
	# defer once more so everything is guaranteed ready before _run().
	call_deferred("_run")

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _spawn(piece_name: String, pos: Vector2i) -> BaseCharacter:
	var dict = battle_instance.friendly_pieces if piece_name.begins_with("friendly_") else battle_instance.enemy_pieces
	var scene: PackedScene = dict[piece_name]
	grid_manager.spawn_character(scene, grid_manager.grid_to_world(pos))
	return grid_manager.get_character_at(pos)

# Presses a NON-targeted ability button and checks the panel didn't get
# nulled out by the press (mirrors the exact bug class that was fixed).
func _press_no_target(character: BaseCharacter, slot: int, label: String):
	map_behaviour.select_character_via_ui(character)
	_check("%s: selectable + shown" % label, battle_ui._shown_character == character)
	battle_ui._on_ability_pressed(slot)
	_check("%s: panel still shows caster after press (no crash)" % label, battle_ui._shown_character == character)

# Presses a TARGETED ability button, checks the panel survives the press
# (the actual bug), then resolves the target and checks the panel survives
# resolution too.
func _press_targeted(character: BaseCharacter, slot: int, target: Vector2i, label: String):
	map_behaviour.select_character_via_ui(character)
	battle_ui._on_ability_pressed(slot)
	_check("%s: panel still shows caster right after press (the fixed bug)" % label, battle_ui._shown_character == character)
	_check("%s: pending_ability is waiting for a target click" % label, not map_behaviour.pending_ability.is_empty())
	map_behaviour._resolve_pending_ability(target)
	_check("%s: panel still shows caster after resolving" % label, battle_ui._shown_character == character)

func _run():
	grid_manager = battle_instance.get_node("GridManager")
	battle_ui = battle_instance.get_node("BattleUI")
	map_behaviour = battle_instance.get_node("Map")
	battle_controller._set_state(battle_controller.BattleState.PLAYER_TURN)
	# High budgets so the action-economy caps (covered by a separate concern)
	# never block these 12 activations - or the handful of plain moves this
	# test also drives (Reposition, Exterminate's own trigger move) - from
	# actually running.
	battle_controller.moves_remaining = 100
	battle_controller.abilities_remaining = 100

	# All test pieces live in rows 9-11 (bottom 3 rows) - battle.gd never
	# scatters random obstacles (rows 2-8) or default enemies (rows 0-1)
	# there, so these fixed coordinates can't collide with a random spawn.

	# ============================================================
	# PAWN: Rally (slot1, no target), Lantern Signal (slot2, no target)
	# ============================================================
	var pawn = _spawn("friendly_pawn", Vector2i(0, 9))
	var rally_target = _spawn("friendly_pawn", Vector2i(11, 9))
	_press_no_target(pawn, 1, "Pawn.Rally")
	_check("Pawn.Rally: other ally actually moved adjacent", rally_target.grid_pos.distance_to(pawn.grid_pos) <= 1.5)
	_press_no_target(pawn, 2, "Pawn.LanternSignal")

	# ============================================================
	# KNIGHT: Evade (slot1, no target), Reposition (slot2, targeted)
	# ============================================================
	var knight = _spawn("friendly_knight", Vector2i(2, 9))
	_press_no_target(knight, 1, "Knight.Evade")
	_check("Knight.Evade: is_capture_immune set", knight.is_capture_immune)
	_press_targeted(knight, 2, Vector2i(0, 10), "Knight.Reposition")
	_check("Knight.Reposition: knight actually moved", knight.grid_pos == Vector2i(0, 10))

	# ============================================================
	# BISHOP: Longshot (slot1, targeted), Traps (slot2, no target)
	# ============================================================
	var bishop = _spawn("friendly_bishop", Vector2i(4, 9))
	var enemy_longshot = _spawn("enemy_pawn", Vector2i(5, 10))
	var enemy_traps = _spawn("enemy_pawn", Vector2i(3, 10))
	_press_targeted(bishop, 1, Vector2i(5, 10), "Bishop.Longshot")
	_check("Bishop.Longshot: target actually died", grid_manager.get_character_at(Vector2i(5, 10)) == null)
	_press_no_target(bishop, 2, "Bishop.Traps")
	_check("Bishop.Traps: nearby enemy is frozen", grid_manager.is_frozen(enemy_traps.grid_pos, true))

	# ============================================================
	# ROOK: Lookout (slot1, no target), Reinforce (slot2, no target)
	# ============================================================
	var rook = _spawn("friendly_rook", Vector2i(6, 9))
	# (0,11) instead of near (7,10) - that tile sits inside the Queen
	# Exterminate blast radius tested right after this, which would kill it
	# as collateral before the Lookout assertions below even run.
	var enemy_lookout = _spawn("enemy_pawn", Vector2i(0, 11))
	grid_manager._spawn_fog_tile(enemy_lookout.grid_pos) # simulate it being fog-obscured
	_check("(setup) Lookout target is fogged before ability", grid_manager.fog_nodes.has(enemy_lookout.grid_pos))
	_press_no_target(rook, 1, "Rook.Lookout")
	_check("Rook.Lookout: fog cleared around revealed enemy", not grid_manager.fog_nodes.has(enemy_lookout.grid_pos))
	_press_no_target(rook, 2, "Rook.Reinforce")
	_check("Rook.Reinforce: adjacent tile now denies enemy entry", grid_manager.is_entry_denied(Vector2i(6, 10), true))

	# ============================================================
	# QUEEN: Exterminate (slot1, no target - arms), Lure (slot2, no target)
	# ============================================================
	var queen = _spawn("friendly_queen", Vector2i(8, 9))
	var enemy_exterminate = _spawn("enemy_pawn", Vector2i(9, 10))
	_press_no_target(queen, 1, "Queen.Exterminate")
	_check("Queen.Exterminate: armed", not battle_controller.exterminate_armed.is_empty())
	queen.execute_move(Vector2i(8, 10)) # "queen moves and clears enemies"
	_check("Queen.Exterminate: nearby enemy died on queen's own move", grid_manager.get_character_at(Vector2i(9, 10)) == null)
	var enemy_lure = _spawn("enemy_pawn", Vector2i(11, 10))
	_press_no_target(queen, 2, "Queen.Lure")
	_check("Queen.Lure: enemy registered as lured", enemy_lure in battle_controller.lured_enemies)

	# ============================================================
	# KING: Cleanse (slot1, no target), Heal (slot2, no target)
	# ============================================================
	var king = _spawn("friendly_king", Vector2i(10, 9))
	var enemy_cleanse = _spawn("enemy_pawn", Vector2i(10, 11))
	_press_no_target(king, 1, "King.Cleanse")
	_check("King.Cleanse: visible enemy converted", not enemy_cleanse.is_enemy and enemy_cleanse.is_converted_ally)

	rally_target.die() # populate dead_party so Heal has something to revive
	var dead_before = player_manager.dead_party.size()
	_press_no_target(king, 2, "King.Heal")
	_check("King.Heal: dead_party shrank (someone got revived)", player_manager.dead_party.size() == dead_before - 1)

	if fails == 0:
		print(">>> SMOKE TEST: all 12 abilities exercised cleanly through the real UI pipeline <<<")
	else:
		print(">>> SMOKE TEST FAIL: %d assertion(s) failed while exercising abilities through the UI pipeline <<<" % fails)
