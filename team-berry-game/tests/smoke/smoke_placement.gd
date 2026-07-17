extends SceneTree

# Placement-phase smoke test: a freshly booted battle sits in PLACEMENT with
# no allies on the board, pieces can only be placed in the bottom 3 rows
# (which fog never covers, even on the deepest floor), placed pieces can be
# moved and removed, the roster/5-piece limits hold, and confirming starts
# the battle with active_party = exactly the placed pieces.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_placement.gd --quit-after 5

var all_ok := true
var battle
var ran := false

func _check(condition: bool, label: String):
	if condition:
		print("    ok: %s" % label)
	else:
		all_ok = false
		print("    FAILED: %s" % label)

func _initialize():
	print(">>> SMOKE TEST: placement phase <<<")

	var player_manager = root.get_node("PlayerManager")
	# Najgloblje nadstropje -> največ megle. Spodnje 3 vrstice (placement
	# cona) morajo kljub temu ostati čiste.
	player_manager.current_map_floor = 14

	battle = BattleBoot.boot_placement_only(self)

# Vse preverbe tečejo v _process: v -s skripti se _ready() scene (in s tem
# initialize_battle) zgodi šele na prvem frame-u, ne že med _initialize().
func _process(_delta: float) -> bool:
	if ran:
		return false

	var battle_controller = battle.get_node("BattleController")
	if battle_controller.current_state == battle_controller.BattleState.INITIALIZING:
		return false # scena se še prebuja
	ran = true

	var player_manager = root.get_node("PlayerManager")
	var grid_manager = battle.get_node("GridManager")
	var battle_ui = battle.get_node("BattleUI")

	_check(battle_controller.current_state == battle_controller.BattleState.PLACEMENT,
		"battle boots into PLACEMENT state")
	_check(battle_ui._placed_characters().is_empty(),
		"no allies auto-spawned on the board")

	var fog_in_zone := 0
	for fog_pos in grid_manager.fog_nodes.keys():
		if fog_pos.y >= 9:
			fog_in_zone += 1
	_check(grid_manager.fog_nodes.size() > 0, "fog exists on floor 14")
	_check(fog_in_zone == 0, "fog never covers the bottom 3 rows")

	_check(not battle_ui.place_piece("friendly_pawn", Vector2i(0, 5)),
		"placing outside the bottom 3 rows is rejected")
	_check(battle_ui.place_piece("friendly_pawn", Vector2i(0, 11)),
		"placing in the bottom rows works")
	_check(not battle_ui.place_piece("friendly_pawn", Vector2i(0, 11)),
		"placing on an occupied cell is rejected")
	_check(battle_ui.place_piece("friendly_pawn", Vector2i(1, 11)),
		"placing a second piece works")

	var first_piece = grid_manager.get_character_at(Vector2i(0, 11))
	_check(battle_ui.move_placed_piece(first_piece, Vector2i(2, 9)),
		"moving a placed piece inside the zone works")
	_check(not grid_manager.is_occupied(Vector2i(0, 11)),
		"old cell is vacated after the move")

	_check(battle_ui.place_piece("friendly_pawn", Vector2i(3, 11)),
		"placing the third roster piece works")
	_check(not battle_ui.place_piece("friendly_pawn", Vector2i(4, 11)),
		"placing more pieces than the roster owns is rejected")

	var third_piece = grid_manager.get_character_at(Vector2i(3, 11))
	battle_ui.remove_placed_piece(third_piece)
	_check(not grid_manager.is_occupied(Vector2i(3, 11)),
		"removing a placed piece vacates its cell")
	_check(battle_ui._placed_characters().size() == 2, "2 pieces placed after removal")

	battle_ui.confirm_placement()
	_check(battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN,
		"confirm starts the player turn")
	_check(player_manager.active_party.size() == 2,
		"active_party is exactly the placed pieces")

	player_manager.current_map_floor = 0

	if all_ok:
		print(">>> SMOKE TEST: placement phase works end to end <<<")
	else:
		print(">>> SMOKE TEST: placement phase FAILED - see checks above <<<")
	return false
