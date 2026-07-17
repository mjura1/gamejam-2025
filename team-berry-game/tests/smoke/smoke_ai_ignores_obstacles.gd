extends SceneTree

# Regression test for a pre-existing bug found via final code review (present
# on main unchanged, just renamed char->nearby_char during this session's N7
# cleanup without noticing the missing filter): calculate_best_move()'s
# "closest currently-visible player" scan did not exclude obstacles (Houses),
# unlike its sibling can_see_player() a few lines above which does filter
# is_obstacle. A House sitting within move_range of an enemy that has already
# spotted a real player once could get picked as "closest_player," setting
# is_panicking and overwriting last_known_player_pos with the house's static
# position - the AI would panic/chase furniture instead of the real target.
#
# This forces the exact scenario: an enemy with has_spotted_player already
# true (skips the one-time wake-up branch), with a House within move_range
# and no real ally anywhere nearby. Confirms calculate_best_move() leaves
# last_known_player_pos untouched (there is nothing valid to track) instead
# of snapping to the house's position.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_ai_ignores_obstacles.gd --quit-after 10

var triggered := false

func _initialize():
	print(">>> SMOKE TEST: AI closest-player scan must ignore obstacles <<<")
	var player_manager = root.get_node("PlayerManager")
	player_manager.setStarting()
	player_manager.resetActives()

	var battle_scene: PackedScene = load("res://Scenes/Map/battle.tscn")
	var battle_instance = battle_scene.instantiate()
	root.add_child(battle_instance)
	current_scene = battle_instance

func _process(_delta: float) -> bool:
	if triggered:
		return false

	var battle_instance = root.get_node_or_null("Battle")
	if battle_instance == null:
		return false

	var grid_manager = battle_instance.get_node_or_null("GridManager")
	if grid_manager == null:
		return false

	var enemies: Array = []
	var houses: Array = []
	for character in grid_manager.get_all_characters():
		if character is BaseCharacter:
			if character.is_enemy:
				enemies.append(character)
			elif character.is_obstacle:
				houses.append(character)

	if enemies.is_empty() or houses.is_empty():
		return false # still spawning, or this random map has no house yet

	triggered = true

	# Move a house right next to an enemy; nothing else (no ally) is
	# anywhere near either of them at their fresh spawn positions. Try every
	# enemy/house pair and all 8 neighboring tiles of each, in case the
	# first-found pair happens to be fully boxed in by other randomly-spawned
	# pieces on this run.
	var enemy = null
	var house = null
	var house_pos := Vector2i(-1, -1)
	for candidate_enemy in enemies:
		for candidate_house in houses:
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var candidate = candidate_enemy.grid_pos + offset
				if not grid_manager.is_occupied(candidate) or candidate == candidate_house.grid_pos:
					enemy = candidate_enemy
					house = candidate_house
					house_pos = candidate
					break
			if house_pos != Vector2i(-1, -1):
				break
		if house_pos != Vector2i(-1, -1):
			break

	if house_pos == Vector2i(-1, -1):
		print(">>> SMOKE TEST: no free tile adjacent to any enemy this run, retry needed <<<")
		return false

	grid_manager.vacate(house.grid_pos)
	house.grid_pos = house_pos
	grid_manager.occupy(house_pos, house)
	house.global_position = grid_manager.grid_to_world(house_pos)

	# Skip the one-time wake-up branch so section 4 (closest-player scan)
	# actually runs instead of returning early.
	enemy.has_spotted_player = true
	var untouched_pos = enemy.last_known_player_pos

	enemy.calculate_best_move()

	if enemy.last_known_player_pos == house_pos:
		print(">>> SMOKE TEST FAIL: obstacle was picked as closest_player (last_known_player_pos snapped to the house) <<<")
	elif enemy.last_known_player_pos == untouched_pos:
		print(">>> SMOKE TEST: obstacle correctly ignored - last_known_player_pos untouched <<<")
	else:
		print(">>> SMOKE TEST FAIL: last_known_player_pos changed to something unexpected: %s <<<" % enemy.last_known_player_pos)
	return false
