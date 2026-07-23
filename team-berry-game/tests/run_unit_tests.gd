extends SceneTree

# Auto-discovers every res://tests/unit/test_*.gd, runs its test_* methods,
# prints a summary, and exits with code 1 if anything failed (0 otherwise).
# Run with: godot4 --headless --path . --script res://tests/run_unit_tests.gd --quit-after 1

func _initialize():
	# Autoloads (e.g. ItemData) don't run _ready() until the engine processes
	# its first frame - _initialize() itself runs before that frame, so any
	# test touching an autoload's loaded data would silently see empty
	# dictionaries (falling back to hardcoded defaults) without this await.
	await process_frame

	# MetaProgress is a real persistent autoload (user://progress.cfg) - the
	# same file the actual game reads/writes. test_meta_progression.gd's
	# try_buy_upgrade() calls exercise the real save_progress(), so without
	# this snapshot/restore, running the unit suite silently corrupts the
	# player's real Legacy save (points spent, upgrades marked unlocked) even
	# though the test only resets its own in-memory fields. Snapshot what
	# load_progress() loaded at startup, then restore + re-save it once every
	# test has run so disk ends up exactly where it started.
	var meta_progress := root.get_node("MetaProgress")
	var meta_snapshot := {
		"tutorial_seen": meta_progress.tutorial_seen,
		"tutorial_reward_granted": meta_progress.tutorial_reward_granted,
		"final_boss_beaten": meta_progress.final_boss_beaten,
		"legacy_points": meta_progress.legacy_points,
		"upgrade_levels": meta_progress.upgrade_levels.duplicate(),
	}

	var dir := DirAccess.open("res://tests/unit")
	if dir == null:
		printerr("run_unit_tests: could not open res://tests/unit")
		quit(1)
		return

	var total_passed := 0
	var total_failed := 0
	var all_failures: Array[String] = []

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with("test_") and file_name.ends_with(".gd"):
			var script: Script = load("res://tests/unit/%s" % file_name)
			var instance: TestCase = script.new()

			for method in script.get_script_method_list():
				var method_name: String = method["name"]
				if method_name.begins_with("test_"):
					instance.call(method_name)

			var result := instance.summary()
			total_passed += result["passed"]
			total_failed += result["failed"]
			for failure in result["failures"]:
				all_failures.append("%s: %s" % [file_name, failure])
		file_name = dir.get_next()
	dir.list_dir_end()

	print("--- Unit test summary: %d passed, %d failed ---" % [total_passed, total_failed])
	for failure in all_failures:
		print("FAILED: %s" % failure)

	meta_progress.tutorial_seen = meta_snapshot["tutorial_seen"]
	meta_progress.tutorial_reward_granted = meta_snapshot["tutorial_reward_granted"]
	meta_progress.final_boss_beaten = meta_snapshot["final_boss_beaten"]
	meta_progress.legacy_points = meta_snapshot["legacy_points"]
	meta_progress.upgrade_levels = meta_snapshot["upgrade_levels"]
	meta_progress.save_progress()

	quit(1 if total_failed > 0 else 0)
