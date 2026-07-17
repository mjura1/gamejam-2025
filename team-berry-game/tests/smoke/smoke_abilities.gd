extends SceneTree

# Boots a real battle (same as smoke_battle.gd), then activates ability slot 1
# on the first placed ally directly (bypassing UI/map_behaviour) and checks
# that it succeeded and consumed one use. Default starting roster is all
# pawns (see PlayerManager.default_friends), so ability 1 here is always
# Pawn.Rally - a non-targeted ability - keeping this test simple. It isn't
# meant to exercise all 12 abilities individually, just to catch obvious
# null/reference crashes shared across every _execute_ability override.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_abilities.gd --quit-after 4

var battle_instance
var reported := false

func _initialize():
	print(">>> SMOKE TEST: booting battle for ability activation check <<<")
	battle_instance = BattleBoot.boot(self)

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if battle_controller and battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN:
		reported = true
		_run_check()

	return false

func _run_check():
	var grid_manager = battle_instance.get_node("GridManager")

	var piece: BaseCharacter = null
	for character in grid_manager.get_all_characters():
		if character is BaseCharacter and not character.is_enemy and not character.is_obstacle:
			piece = character
			break

	if piece == null:
		print("SMOKE TEST FAIL: no placed ally piece found to test abilities on")
		return

	var before: int = piece.ability_uses_remaining.get(1, 0)
	var ok: bool = piece.activate_ability(1)
	var after: int = piece.ability_uses_remaining.get(1, 0)

	if ok and after == before - 1:
		print(">>> SMOKE TEST: ability activated cleanly and use count decremented <<<")
	else:
		print("SMOKE TEST FAIL: activate_ability(1) ok=%s before=%d after=%d" % [ok, before, after])
