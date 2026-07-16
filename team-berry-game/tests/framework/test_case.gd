extends RefCounted
class_name TestCase

# Minimal assertion base class for pure-logic unit tests (no addon dependency).
# Subclass this, add methods named test_*, and run_unit_tests.gd auto-discovers them.

var _passed := 0
var _failed := 0
var _failures: Array[String] = []

func assert_true(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_failures.append(message)

func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)

func assert_eq(actual, expected, message: String) -> void:
	assert_true(actual == expected, "%s (got %s, expected %s)" % [message, actual, expected])

func summary() -> Dictionary:
	return {"passed": _passed, "failed": _failed, "failures": _failures}
