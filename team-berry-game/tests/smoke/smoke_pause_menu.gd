extends SceneTree

# Drives GF's persistent pause-menu overlay through a real Escape-key toggle
# during a live battle, to confirm the wiring added this session actually
# works end-to-end (menu hidden+unpaused at start, visible+paused after one
# Escape press, hidden+unpaused again after a second Escape press once the
# resume() blur-out animation finishes) rather than just "compiles without
# errors."
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_pause_menu.gd --quit-after 80

var frame_num := 0
var phase := 0
var phase_start_frame := 0
var reported := false

func _initialize():
	print(">>> SMOKE TEST: pause menu wiring <<<")
	BattleBoot.boot(self)

func _process(_delta: float) -> bool:
	frame_num += 1
	if reported:
		return false

	var pause_menu = root.get_node_or_null("PauseMenuLayer/PauseMenu")
	if pause_menu == null:
		return false

	match phase:
		0:
			if pause_menu.visible or paused:
				print(">>> SMOKE TEST FAIL: pause menu should start hidden and tree unpaused <<<")
				reported = true
				return false
			Input.action_press("escape")
			phase = 1
			phase_start_frame = frame_num
		1:
			if paused and pause_menu.visible:
				print(">>> SMOKE TEST: escape opened the pause menu and paused the tree <<<")
				Input.action_release("escape")
				phase = 2
				phase_start_frame = frame_num
			elif frame_num - phase_start_frame > 10:
				print(">>> SMOKE TEST FAIL: escape never paused the tree / opened the menu <<<")
				reported = true
		2:
			# Hold the paused state a few frames before resuming.
			if frame_num - phase_start_frame >= 5:
				Input.action_press("escape")
				phase = 3
				phase_start_frame = frame_num
		3:
			Input.action_release("escape")
			phase = 4
			phase_start_frame = frame_num
		4:
			if not paused and not pause_menu.visible:
				print(">>> SMOKE TEST: escape resumed - menu hidden and tree unpaused again <<<")
				reported = true
			elif frame_num - phase_start_frame > 60:
				print(">>> SMOKE TEST FAIL: pause menu never resumed/hid after second escape <<<")
				reported = true

	return false
