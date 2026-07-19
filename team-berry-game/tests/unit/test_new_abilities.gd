extends TestCase

# Happy-path testi za nove 3. sposobnosti (SKILL_TREE_PLAN.md §4/§7 item 3).
# Figure/GridManager se instancirajo direktno (.new(), brez scene/tree - glej
# test_battle_controller_path.gd za isti vzorec) in ročno žično povežejo
# (grid_manager, grid_pos) - _ready()/on_grid_manager_registered() se NE
# kličeta, zato so testirane samo _execute_ability poti, ne UI/targeting.

const KingScript = preload("res://Scripts/CharacterPieces/Ally/king.gd")
const BishopScript = preload("res://Scripts/CharacterPieces/Ally/bishop.gd")
const KnightScript = preload("res://Scripts/CharacterPieces/Ally/knight.gd")
const RookScript = preload("res://Scripts/CharacterPieces/Ally/rook.gd")
const QueenScript = preload("res://Scripts/CharacterPieces/Ally/queen.gd")
const BattleControllerScript = preload("res://Scripts/TileMap/BattleController.gd")
const PlayerManagerScript = preload("res://Scripts/Player/PlayerManager.gd")

# ----------------- King.Royal Decree -----------------

func test_royal_decree_base_immunizes_king_and_nearby_allies_only():
	var gm := GridManager.new()
	var king := KingScript.new()
	king.grid_pos = Vector2i(5, 5)
	king.grid_manager = gm
	gm.occupy(king.grid_pos, king)

	var ally_near := KnightScript.new()
	ally_near.grid_pos = Vector2i(6, 5) # within 3x3
	ally_near.grid_manager = gm
	gm.occupy(ally_near.grid_pos, ally_near)

	var ally_far := KnightScript.new()
	ally_far.grid_pos = Vector2i(8, 5) # outside 3x3
	ally_far.grid_manager = gm
	gm.occupy(ally_far.grid_pos, ally_far)

	var enemy_near := KnightScript.new()
	enemy_near.is_enemy = true
	enemy_near.grid_pos = Vector2i(5, 6) # within 3x3, but an enemy
	enemy_near.grid_manager = gm
	gm.occupy(enemy_near.grid_pos, enemy_near)

	var ok: bool = king._execute_ability("royal_decree", null)

	assert_true(ok, "royal_decree should succeed when it reaches at least one ally")
	assert_true(king.is_capture_immune, "the king itself is within its own base-tier 3x3")
	assert_true(ally_near.is_capture_immune, "an ally inside the 3x3 should become capture-immune")
	assert_false(ally_far.is_capture_immune, "an ally outside the 3x3 should be untouched at base tier")
	assert_false(enemy_near.is_capture_immune, "royal_decree must never immunize enemies")

func test_royal_decree_upgraded_tier_immunizes_every_ally():
	var gm := GridManager.new()
	var king := KingScript.new()
	king.grid_pos = Vector2i(5, 5)
	king.grid_manager = gm
	king.ability_levels[3] = 3 # upgraded tier -> {"all": true}
	gm.occupy(king.grid_pos, king)

	var ally_far := KnightScript.new()
	ally_far.grid_pos = Vector2i(11, 11) # far outside any area shape
	ally_far.grid_manager = gm
	gm.occupy(ally_far.grid_pos, ally_far)

	var enemy_far := KnightScript.new()
	enemy_far.is_enemy = true
	enemy_far.grid_pos = Vector2i(0, 0)
	enemy_far.grid_manager = gm
	gm.occupy(enemy_far.grid_pos, enemy_far)

	var ok: bool = king._execute_ability("royal_decree", null)

	assert_true(ok, "upgraded royal_decree should succeed")
	assert_true(ally_far.is_capture_immune, "upgraded tier ({all:true}) should reach every ally regardless of position")
	assert_false(enemy_far.is_capture_immune, "royal_decree must never immunize enemies, even at upgraded tier")

func test_royal_decree_immunity_expires_at_start_of_next_player_turn():
	var gm := GridManager.new()
	var king := KingScript.new()
	king.grid_pos = Vector2i(5, 5)
	king.grid_manager = gm
	gm.occupy(king.grid_pos, king)
	king._execute_ability("royal_decree", null)
	assert_true(king.is_capture_immune, "sanity check: royal_decree set the flag")

	var enemy := KnightScript.new()
	enemy.is_enemy = true
	enemy.is_capture_immune = true # never set by royal_decree, but confirms the loop is ally-only
	enemy.grid_pos = Vector2i(0, 0)
	enemy.grid_manager = gm
	gm.occupy(enemy.grid_pos, enemy)

	var bc := BattleControllerScript.new()
	bc.grid_manager = gm
	bc._clear_expired_evade()

	assert_false(king.is_capture_immune, "_clear_expired_evade (called at the next start_player_turn) should clear Royal Decree's immunity")
	assert_true(enemy.is_capture_immune, "_clear_expired_evade only loops allied pieces - enemy flags are untouched")

# ----------------- Bishop.Sanctify -----------------

func test_sanctify_clears_curses_in_area_only():
	var gm := GridManager.new()
	var bishop := BishopScript.new()
	bishop.grid_pos = Vector2i(4, 4)
	bishop.grid_manager = gm
	gm.occupy(bishop.grid_pos, bishop)

	var cursed_near := KnightScript.new()
	cursed_near.grid_pos = Vector2i(4, 5) # within base 3x3
	cursed_near.grid_manager = gm
	cursed_near.curse = CurseData.create_curse("snowfall")
	gm.occupy(cursed_near.grid_pos, cursed_near)

	var cursed_far := KnightScript.new()
	cursed_far.grid_pos = Vector2i(7, 7) # outside base 3x3
	cursed_far.grid_manager = gm
	cursed_far.curse = CurseData.create_curse("frenzy")
	gm.occupy(cursed_far.grid_pos, cursed_far)

	var cursed_enemy := KnightScript.new()
	cursed_enemy.is_enemy = true
	cursed_enemy.grid_pos = Vector2i(5, 4) # within base 3x3, but an enemy
	cursed_enemy.grid_manager = gm
	cursed_enemy.curse = CurseData.create_curse("blizzard")
	gm.occupy(cursed_enemy.grid_pos, cursed_enemy)

	var ok: bool = bishop._execute_ability("sanctify", null)

	assert_true(ok, "sanctify should succeed when it clears at least one curse")
	assert_true(cursed_near.curse == null, "an allied curse inside the 3x3 should be cleared")
	assert_false(cursed_far.curse == null, "an allied curse outside the 3x3 should be untouched")
	assert_false(cursed_enemy.curse == null, "sanctify must never clear an enemy's curse")

func test_sanctify_returns_false_when_no_curse_in_range():
	var gm := GridManager.new()
	var bishop := BishopScript.new()
	bishop.grid_pos = Vector2i(4, 4)
	bishop.grid_manager = gm
	gm.occupy(bishop.grid_pos, bishop)

	var uncursed_near := KnightScript.new()
	uncursed_near.grid_pos = Vector2i(4, 5)
	uncursed_near.grid_manager = gm
	gm.occupy(uncursed_near.grid_pos, uncursed_near)

	var ok: bool = bishop._execute_ability("sanctify", null)
	assert_false(ok, "sanctify with no curses in range should report no valid use")

# ----------------- Knight.Ambush -----------------

func test_ambush_moves_knight_to_target_tile():
	var gm := GridManager.new()
	var knight := KnightScript.new()
	knight.grid_pos = Vector2i(5, 5)
	knight.grid_manager = gm
	knight.settings_manager = SettingsManager
	gm.occupy(knight.grid_pos, knight)

	var target := Vector2i(7, 5) # within base radius 3, empty, no curse fog
	var was_reduced_motion: bool = SettingsManager.reduced_motion
	SettingsManager.reduced_motion = true # skip create_tween(), which needs a live scene tree
	var ok: bool = knight._execute_ability("ambush", target)
	SettingsManager.reduced_motion = was_reduced_motion

	assert_true(ok, "ambush onto an empty tile should succeed")
	assert_eq(knight.grid_pos, target, "the knight should land exactly on the ambush target tile")
	assert_false(gm.is_occupied(Vector2i(5, 5)), "the knight's old tile should be vacated")
	assert_true(gm.get_character_at(target) == knight, "the grid should track the knight at its new tile")

func test_ambush_fails_onto_occupied_tile():
	var gm := GridManager.new()
	var knight := KnightScript.new()
	knight.grid_pos = Vector2i(5, 5)
	knight.grid_manager = gm
	gm.occupy(knight.grid_pos, knight)

	var blocker := KnightScript.new()
	blocker.grid_pos = Vector2i(7, 5)
	blocker.grid_manager = gm
	gm.occupy(blocker.grid_pos, blocker)

	var ok: bool = knight._execute_ability("ambush", Vector2i(7, 5))

	assert_false(ok, "ambush onto an occupied tile should fail")
	assert_eq(knight.grid_pos, Vector2i(5, 5), "a failed ambush should not move the knight")

# ----------------- Rook.Castling -----------------

func test_castling_swaps_positions_with_ally_target():
	var gm := GridManager.new()
	var rook := RookScript.new()
	rook.grid_pos = Vector2i(5, 5)
	rook.grid_manager = gm
	rook.settings_manager = SettingsManager
	gm.occupy(rook.grid_pos, rook)

	var ally := KnightScript.new()
	ally.grid_pos = Vector2i(5, 2)
	ally.grid_manager = gm
	ally.settings_manager = SettingsManager
	gm.occupy(ally.grid_pos, ally)

	var was_reduced_motion: bool = SettingsManager.reduced_motion
	SettingsManager.reduced_motion = true # skip create_tween(), which needs a live scene tree
	var ok: bool = rook._execute_ability("castling", ally.grid_pos)
	SettingsManager.reduced_motion = was_reduced_motion

	assert_true(ok, "castling with a valid ally target should succeed")
	assert_eq(rook.grid_pos, Vector2i(5, 2), "the rook should land on the ally's former tile")
	assert_eq(ally.grid_pos, Vector2i(5, 5), "the ally should land on the rook's former tile")
	assert_true(gm.get_character_at(Vector2i(5, 2)) == rook, "grid should track the rook at its new tile after castling")
	assert_true(gm.get_character_at(Vector2i(5, 5)) == ally, "grid should track the ally at its new tile after castling")

func test_castling_fails_against_enemy_target():
	var gm := GridManager.new()
	var rook := RookScript.new()
	rook.grid_pos = Vector2i(5, 5)
	rook.grid_manager = gm
	gm.occupy(rook.grid_pos, rook)

	var enemy := KnightScript.new()
	enemy.is_enemy = true
	enemy.grid_pos = Vector2i(5, 2)
	enemy.grid_manager = gm
	gm.occupy(enemy.grid_pos, enemy)

	var ok: bool = rook._execute_ability("castling", enemy.grid_pos)

	assert_false(ok, "castling should never swap positions with an enemy piece")
	assert_eq(rook.grid_pos, Vector2i(5, 5), "a failed castling attempt should not move the rook")

# ----------------- Queen.Command -----------------

func test_command_marks_free_move_character_and_skips_its_next_move_cost():
	var gm := GridManager.new()
	var queen := QueenScript.new()
	queen.grid_pos = Vector2i(5, 5)
	queen.grid_manager = gm
	gm.occupy(queen.grid_pos, queen)

	var ally := KnightScript.new()
	ally.grid_pos = Vector2i(5, 6)
	ally.grid_manager = gm
	gm.occupy(ally.grid_pos, ally)

	var bc := BattleControllerScript.new()
	bc.grid_manager = gm
	bc.player_manager = PlayerManagerScript.new()
	queen.battle_controller = bc

	var ok: bool = queen._execute_ability("command", ally.grid_pos)

	assert_true(ok, "command should succeed when targeting a valid ally")
	assert_true(bc.free_move_character == ally, "command should mark the targeted ally as the battle controller's free-move character")

	bc.moves_remaining = 1
	bc.consume_move_for(ally)
	assert_eq(bc.moves_remaining, 1, "the free move should not consume the moves budget")
	assert_true(bc.free_move_character == null, "the free move should be cleared once it has been used")

	bc.moves_remaining = 1
	bc.consume_move_for(queen)
	assert_eq(bc.moves_remaining, 0, "a move by a different character should consume the budget as normal")

func test_command_fails_against_enemy_target():
	var gm := GridManager.new()
	var queen := QueenScript.new()
	queen.grid_pos = Vector2i(5, 5)
	queen.grid_manager = gm
	gm.occupy(queen.grid_pos, queen)

	var enemy := KnightScript.new()
	enemy.is_enemy = true
	enemy.grid_pos = Vector2i(5, 6)
	enemy.grid_manager = gm
	gm.occupy(enemy.grid_pos, enemy)

	var bc := BattleControllerScript.new()
	bc.grid_manager = gm
	bc.player_manager = PlayerManagerScript.new()
	queen.battle_controller = bc

	var ok: bool = queen._execute_ability("command", enemy.grid_pos)

	assert_false(ok, "command should never grant a free move to an enemy piece")
	assert_true(bc.free_move_character == null, "a failed command should not set free_move_character")
