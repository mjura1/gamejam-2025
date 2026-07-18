extends SceneTree

# Drives the real "Start -> click campfire room -> REST -> BACK -> map"
# flow headlessly. Unit tests only check MapGenerator's data (which floor
# gets type == campfire) - they never instantiate campfire.tscn, so they
# can't catch a broken @onready node path inside campfire.gd (the same
# class of bug smoke_start_new_game.gd was added to catch for map_camera).
# "Start" is now two presses since the Mode Select screen landed: PLAY opens
# the overlay, CLASSIC on it starts the game (see smoke_start_new_game.gd).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_campfire_flow.gd --quit-after 8

var opened := false
var started := false
var clicked_campfire := false
var rested := false
var checked_return := false

func _initialize():
	print(">>> SMOKE TEST: map campfire room -> Campfire scene -> REST -> BACK -> map <<<")
	var main_menu: PackedScene = load("res://Scenes/Menu/main_menu.tscn")
	var instance = main_menu.instantiate()
	root.add_child(instance)
	current_scene = instance

func _process(_delta: float) -> bool:
	if not opened:
		if current_scene != null and current_scene.has_method("_on_play_pressed"):
			current_scene._on_play_pressed()
			opened = true
		return false

	if not started:
		var overlay = current_scene._mode_select_instance
		if not is_instance_valid(overlay):
			return false # keep waiting; --quit-after fails the test if it never shows
		overlay._on_classic_pressed()
		started = true
		return false

	var gf = root.get_node("GF")

	if not clicked_campfire:
		var map_instance = gf.current_map_instance
		if map_instance == null or not is_instance_valid(map_instance) or not map_instance.is_initialized:
			return false # still waiting for the deferred _initialize_game()

		var campfire_floor = map_instance.generator.FLOORS - 2
		var campfire_room = null
		for room in map_instance.map_data[campfire_floor]:
			if room != null:
				campfire_room = room
				break

		if campfire_room == null:
			push_error("SMOKE TEST FAILED: no room found on the forced campfire floor (%d)" % campfire_floor)
			return true
		if campfire_room.type != Room.RoomType.campfire:
			push_error("SMOKE TEST FAILED: forced campfire floor room has type %s, not campfire" % Room.RoomTypeNames.get(campfire_room.type, "?"))
			return true

		map_instance._on_room_selected(campfire_room)
		clicked_campfire = true
		return false

	if not rested:
		var campfire_scene = current_scene
		if campfire_scene == null or not campfire_scene.has_method("_on_rest_and_back_pressed"):
			return false # still waiting for the deferred scene swap to Campfire

		# Party/Upgrade buttons: CampfirePartyPanel.gd previously crashed on
		# open (it read PlayerManager.dead_party/.food, which don't exist) -
		# click them here so a future regression is caught, not just manually.
		campfire_scene._on_party_pressed()
		campfire_scene._on_ugrade_pressed()

		# STATE_REST -> perform_rest_action() + advance to STATE_RETURN
		campfire_scene._on_rest_and_back_pressed()
		# STATE_RETURN -> return_to_map_action() -> GF.return_to_map()
		campfire_scene._on_rest_and_back_pressed()
		rested = true
		return false

	if checked_return:
		return false

	if current_scene == null or current_scene != gf.current_map_instance:
		return false # still waiting for the deferred return_to_map()

	checked_return = true
	print(">>> SMOKE TEST: campfire flow completed cleanly, back on the map <<<")
	return false
