extends SceneTree

# Auto-discovers every res://tests/unit/test_*.gd, runs its test_* methods,
# prints a summary, and exits with code 1 if anything failed (0 otherwise).
# Run with: godot4 --headless --path . --script res://tests/run_unit_tests.gd --quit-after 1

func _initialize():
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

	quit(1 if total_failed > 0 else 0)
