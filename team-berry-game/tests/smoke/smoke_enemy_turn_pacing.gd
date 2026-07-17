extends SceneTree

# Drives a REAL enemy turn via BattleController.end_player_turn() (not a
# bypass like smoke_battle_end/loss use) to exercise the one-at-a-time AI
# pacing + move-flash visualization added for the "enemy move visualizer"
# feature. Confirms the async per-enemy delay loop actually completes and
# hands control back to the player, and that MoveHighlighter accumulated
# flashes for the moves that happened.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_enemy_turn_pacing.gd --quit-after 200

var triggered := false
var start_frame := 0
var frame_num := 0
var reported := false

func _initialize():
	print(">>> SMOKE TEST: enemy turn pacing / move visualizer <<<")
	BattleBoot.boot(self)

func _process(_delta: float) -> bool:
	frame_num += 1
	if reported:
		return false

	var battle_instance = root.get_node_or_null("Battle")
	if battle_instance == null:
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if battle_controller == null:
		return false

	if not triggered:
		if battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN and battle_controller.turn_count >= 1:
			print(">>> SMOKE TEST: triggering end_player_turn() (turn %d) <<<" % battle_controller.turn_count)
			triggered = true
			start_frame = frame_num
			battle_controller.end_player_turn()
		return false

	# Wait for control to return to the player - turn_count increments again
	# once start_player_turn() runs at the end of the enemy loop.
	if battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN and battle_controller.turn_count >= 2:
		reported = true
		var elapsed_frames = frame_num - start_frame
		print(">>> SMOKE TEST: enemy turn completed after %d frames (turn_count=%d) <<<" % [elapsed_frames, battle_controller.turn_count])

		var move_highlighter = battle_instance.get_node_or_null("MoveHighlighter")
		if is_instance_valid(move_highlighter):
			print(">>> SMOKE TEST: move_highlighter has %d accumulated flash(es) <<<" % move_highlighter.enemy_move_flashes.size())
		else:
			print(">>> SMOKE TEST FAIL: MoveHighlighter node not found <<<")
		return false

	return false
