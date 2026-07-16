extends SceneTree

# Regression test: test_sandbox.tscn's pre-placed pieces (Bishop, King, Queen)
# looked fine and loaded with zero errors, but were NEVER actually registered
# on the grid - register_all_characters_in_scene() is only ever called from
# inside grid_manager.spawn_character() (used by real, dynamically-spawned
# battles), and initialize_battle() is only ever called from the live
# battle.tscn's battle.gd. The sandbox's root had no script to trigger either
# one, so every piece just sat at its raw un-snapped .tscn position with
# grid_manager still null - "zero ERROR: lines" was hiding a completely
# non-functional scene. Fixed by giving the root a script (test_sandbox.gd)
# that does both. This confirms grid_pos/position are actually set, not just
# that the scene loads without errors.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_test_sandbox.gd --quit-after 3

func _initialize():
	print(">>> SMOKE TEST: test_sandbox.tscn piece registration <<<")
	var sandbox: PackedScene = load("res://Scenes/test_sandbox.tscn")
	var instance = sandbox.instantiate()
	root.add_child(instance)
	current_scene = instance

var reported := false

func _process(_delta: float) -> bool:
	if reported:
		return false
	reported = true

	var chars = get_nodes_in_group("characters")
	if chars.is_empty():
		print(">>> SMOKE TEST FAIL: no characters found in the group at all <<<")
		return false

	var all_registered = true
	for c in chars:
		if not is_instance_valid(c.grid_manager):
			print(">>> SMOKE TEST FAIL: %s was never registered (grid_manager is null) <<<" % c.name)
			all_registered = false

	if all_registered:
		print(">>> SMOKE TEST: all %d sandbox pieces registered with a valid grid_manager <<<" % chars.size())
	return false
