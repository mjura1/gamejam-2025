extends SceneTree

# Drives a battle to a LOSS (all allies dead) headlessly - the exact path
# T5.2 fixed: GameFlow.game_over() used to null out current_map_instance
# while it was detached from the tree, leaking the map (+ ~50 room icons)
# on every lost run. Confirms the detached map instance is actually freed.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_battle_loss.gd --quit-after 15
#
# IMPORTANT: MainLoop._process() returning true TERMINATES the loop, false
# continues it - this script always returns false and lets --quit-after cut
# it off, so deferred calls (call_deferred, queue_free) get frames to
# actually take effect before the process ever stops.

var killed_allies := false
var summary_handled := false
var old_map_instance: Node = null
var frames_since_transition := 0
var checked_result := false

func _initialize():
	print(">>> SMOKE TEST: battle-end LOSS path (C8/T5.2) <<<")
	BattleBoot.boot(self)
	old_map_instance = root.get_node("GF").current_map_instance

func _process(_delta: float) -> bool:
	var battle_instance = root.get_node_or_null("Battle")

	if battle_instance == null:
		# queue_free() takes effect at end-of-frame - give it a couple frames
		# before checking, since _end_run() queues the free synchronously but
		# the actual deletion is deferred.
		frames_since_transition += 1
		if frames_since_transition == 1:
			print(">>> SMOKE TEST: Battle scene left the tree - transition happened cleanly <<<")
		if frames_since_transition >= 3 and not checked_result:
			checked_result = true
			if is_instance_valid(old_map_instance):
				print(">>> SMOKE TEST FAIL: old map instance was NOT freed (leak) <<<")
			else:
				print(">>> SMOKE TEST: old (detached) map instance was freed - no leak <<<")
		return false

	if not killed_allies:
		var grid_manager = battle_instance.get_node_or_null("GridManager")
		var battle_controller = battle_instance.get_node_or_null("BattleController")
		if grid_manager == null or battle_controller == null:
			return false # still spawning

		var allies: Array = []
		for character in grid_manager.get_all_characters():
			if character is BaseCharacter and not character.is_enemy and not character.is_obstacle:
				allies.append(character)

		if allies.is_empty():
			return false # pieces haven't spawned yet

		print(">>> SMOKE TEST: killing %d allies to force a LOSS <<<" % allies.size())
		for ally in allies:
			ally.die()
		killed_allies = true

		# Same check the real turn loop runs right after an action resolves.
		battle_controller.check_battle_end()
		return false

	if not summary_handled:
		# check_battle_end() now shows the post-battle summary instead of
		# calling game_over() directly - the Battle scene stays in the tree
		# until BACK is driven, which is what actually triggers game_over()
		# (and therefore _end_run()'s map-instance cleanup this test checks).
		var summary_layer = root.get_node_or_null("PostBattleSummaryLayer")
		if summary_layer == null or summary_layer.get_child_count() == 0:
			return false # summary overlay not up yet
		print(">>> SMOKE TEST: post-battle summary shown, emitting back_pressed <<<")
		summary_layer.get_child(0).back_pressed.emit()
		summary_handled = true
		return false

	return false
