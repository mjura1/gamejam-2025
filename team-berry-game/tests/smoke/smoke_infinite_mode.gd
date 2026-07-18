extends SceneTree

# Smoke test for infinite mode: after the tier-2 boss, advance_map_tier()
# must NOT take the "beat all 3 tiers -> main menu" branch when
# PlayerManager.game_mode == "infinite" - it must generate a 4th map
# instead, reusing the tier-2 config (MapGenerator._configure_tier() clamps
# tier 3+ to the last TIER_CONFIGS entry: 9 floors, king boss, full pool).
# The classic branch would also reset current_map_tier to 0 via _end_run(),
# so tier staying at 3 doubles as proof the run was not ended.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_infinite_mode.gd --quit-after 8

var advanced := false
var checked := false

func _initialize():
	print(">>> SMOKE TEST: infinite mode advance_map_tier() past tier 3 <<<")
	var player_manager = root.get_node("PlayerManager")
	player_manager.setStarting("infinite")
	player_manager.current_map_tier = 2 # as if the tier-2 (final classic) boss just fell

func _process(_delta: float) -> bool:
	var gf = root.get_node_or_null("GF")
	var player_manager = root.get_node("PlayerManager")
	if gf == null:
		return false

	if not advanced:
		gf.advance_map_tier()
		advanced = true
		return false

	if checked:
		return false

	if not is_instance_valid(gf.current_map_instance):
		# The classic branch nulls current_map_instance via _end_run() - but a
		# frame later current_scene would be the main menu; keep waiting, the
		# checks below catch the failure once a scene exists.
		return false
	if not gf.current_map_instance.is_initialized:
		return false # waiting for MapController._ready() -> initialize_map()

	checked = true

	if player_manager.current_map_tier != 3:
		print(">>> SMOKE TEST FAIL: expected tier 3, got %d (run was ended?) <<<" % player_manager.current_map_tier)
		return true
	if current_scene != gf.current_map_instance:
		print(">>> SMOKE TEST FAIL: current scene is %s, not the new map instance <<<" % (current_scene.name if current_scene else "null"))
		return true
	if gf.current_map_instance.generator.FLOORS != 9:
		print(">>> SMOKE TEST FAIL: tier 3 map has %d floors, expected the clamped tier-2 config (9) <<<" % gf.current_map_instance.generator.FLOORS)
		return true

	print("SMOKE_INFINITE_MODE_OK (tier 3 map generated, 9 floors, no main-menu return)")
	return false
