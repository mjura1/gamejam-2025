extends TestCase

# Happy-path testi za nove 3. sposobnosti (SKILL_TREE_PLAN.md §4/§7 item 3).
# Figure/GridManager se instancirajo direktno (.new(), brez scene/tree - glej
# test_battle_controller_path.gd za isti vzorec) in ročno žično povežejo
# (grid_manager, grid_pos) - _ready()/on_grid_manager_registered() se NE
# kličeta, zato so testirane samo _execute_ability poti, ne UI/targeting.

const KingScript = preload("res://Scripts/CharacterPieces/Ally/king.gd")
const KnightScript = preload("res://Scripts/CharacterPieces/Ally/knight.gd")
const BattleControllerScript = preload("res://Scripts/TileMap/BattleController.gd")

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
