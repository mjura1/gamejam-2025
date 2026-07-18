extends SceneTree

# Smoke test for the Mode Select overlay (Scenes/Menu/mode_select_menu.tscn):
# PLAY on the main menu must instance the overlay and hide the menu's own
# VBoxContainer/Title, and BACK must free the overlay and show them again -
# same open/close contract the settings overlay follows. This drives the
# handlers directly (like smoke_start_new_game) rather than clicking pixels.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_mode_select.gd --quit-after 5

var opened := false
var closed := false
var checked := false
var overlay: Control = null

func _initialize():
	print(">>> SMOKE TEST: main menu Play -> Mode Select overlay open/close <<<")
	var main_menu: PackedScene = load("res://Scenes/Menu/main_menu.tscn")
	var instance = main_menu.instantiate()
	root.add_child(instance)
	current_scene = instance

func _process(_delta: float) -> bool:
	if not opened:
		if current_scene == null or not current_scene.has_method("_on_play_pressed"):
			return false
		current_scene._on_play_pressed()
		opened = true
		return false

	if not closed:
		overlay = current_scene._mode_select_instance
		if not is_instance_valid(overlay):
			print(">>> SMOKE TEST FAIL: PLAY did not create a Mode Select overlay <<<")
			return true
		if current_scene.get_node("VBoxContainer").visible:
			print(">>> SMOKE TEST FAIL: main menu VBoxContainer still visible under the overlay <<<")
			return true
		current_scene._on_mode_select_back()
		closed = true
		return false # give queue_free() a frame to actually free the overlay

	if checked:
		return false
	checked = true

	if is_instance_valid(overlay):
		print(">>> SMOKE TEST FAIL: overlay still alive after BACK (queue_free missing?) <<<")
		return true
	if not current_scene.get_node("VBoxContainer").visible:
		print(">>> SMOKE TEST FAIL: main menu VBoxContainer not restored after BACK <<<")
		return true

	print("SMOKE_MODE_SELECT_OK")
	return false
