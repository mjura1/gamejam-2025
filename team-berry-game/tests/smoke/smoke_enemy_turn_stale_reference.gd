extends SceneTree

# Regression test for a crash found via manual playtest: BattleController's
# start_enemy_turn() iterates a SNAPSHOT (grid_manager.get_all_characters())
# taken once at the top of the loop. Before the enemy-move-visualizer change
# added a real await between enemy actions, the whole loop resolved in one
# synchronous frame, so a piece captured mid-loop (queue_free()'d) was still
# technically alive in memory for the rest of that same frame. With the
# await, real frames pass, so a piece captured earlier in the loop can be
# genuinely deallocated by the time the loop reaches its now-stale entry
# later in the snapshot - which happens whenever a piece was repositioned
# earlier in the battle (moving re-inserts its dict entry, shifting where
# it lands in the Dictionary's insertion/iteration order) and a different,
# earlier-iterated enemy then captures it.
#
# This script forces exactly that: repositions an enemy and then an ally
# (in that order, so the enemy's occupied-dict entry - and therefore its
# position in get_all_characters()'s snapshot - comes BEFORE the ally's),
# places them adjacent so the AI's "capture has absolute priority" logic
# is guaranteed to target the ally, then drives a real enemy turn and
# confirms no crash ("Left operand of 'is' is a previously freed instance").
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_enemy_turn_stale_reference.gd --quit-after 60

var triggered := false
var reported := false

func _initialize():
	print(">>> SMOKE TEST: stale-reference capture during enemy turn <<<")
	BattleBoot.boot(self)

func _process(_delta: float) -> bool:
	if reported:
		return false

	var battle_instance = root.get_node_or_null("Battle")
	if battle_instance == null:
		return false

	var grid_manager = battle_instance.get_node_or_null("GridManager")
	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if grid_manager == null or battle_controller == null:
		return false

	if not triggered:
		var allies: Array = []
		var enemies: Array = []
		for character in grid_manager.get_all_characters():
			if character is BaseCharacter and not character.is_obstacle:
				if character.is_enemy:
					enemies.append(character)
				else:
					allies.append(character)

		if allies.is_empty() or enemies.is_empty():
			return false # still spawning

		triggered = true
		var ally = allies[0]
		var enemy = enemies[0]

		# Reposition the ENEMY first, then the ALLY - each vacate+occupy
		# re-inserts that piece's dict entry at the "end" of occupied's
		# iteration order, so doing enemy-then-ally guarantees the enemy is
		# snapshotted BEFORE the ally, exactly like a real battle where the
		# player already moved a piece earlier in the fight.
		# Try a few candidate tiles near center / adjacent, since spawn
		# positions (allies, enemies, and randomly-placed Houses) vary run
		# to run and could already occupy the first candidate.
		grid_manager.vacate(enemy.grid_pos)
		var enemy_new_pos := Vector2i(-1, -1)
		for candidate in [Vector2i(6, 6), Vector2i(5, 6), Vector2i(7, 6), Vector2i(6, 5), Vector2i(6, 7)]:
			if not grid_manager.is_occupied(candidate):
				enemy_new_pos = candidate
				break
		if enemy_new_pos == Vector2i(-1, -1):
			print(">>> SMOKE TEST: no free tile near center this run, retry needed <<<")
			return false
		enemy.grid_pos = enemy_new_pos
		grid_manager.occupy(enemy_new_pos, enemy)
		enemy.global_position = grid_manager.grid_to_world(enemy_new_pos)

		grid_manager.vacate(ally.grid_pos)
		var ally_new_pos := Vector2i(-1, -1)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var candidate = enemy_new_pos + offset
			if not grid_manager.is_occupied(candidate):
				ally_new_pos = candidate
				break
		if ally_new_pos == Vector2i(-1, -1):
			print(">>> SMOKE TEST: no free tile adjacent to enemy this run, retry needed <<<")
			return false
		ally.grid_pos = ally_new_pos
		grid_manager.occupy(ally_new_pos, ally)
		ally.global_position = grid_manager.grid_to_world(ally_new_pos)

		# Skip the one-time "wake-up turn" so the capture happens on this
		# very call instead of a no-op spotting turn.
		enemy.has_spotted_player = true

		print(">>> SMOKE TEST: forced enemy at %s, ally adjacent at %s - triggering enemy turn <<<" % [enemy_new_pos, ally_new_pos])
		battle_controller.start_enemy_turn()
		return false

	if battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN:
		reported = true
		print(">>> SMOKE TEST: enemy turn completed without crashing - stale reference handled correctly <<<")
		return false

	return false
