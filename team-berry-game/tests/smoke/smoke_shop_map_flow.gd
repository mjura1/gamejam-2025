extends SceneTree

# Drives the real "Start on tier 1 -> click shop room -> Shop scene -> LEAVE
# -> map" flow headlessly, the same way smoke_campfire_flow.gd covers
# campfire. Shop only exists on map tiers 1 and 2 (see MapGenerator
# TIER_CONFIGS shop_floor) - tier is forced to 1 before Start so the
# generated map is guaranteed to have one (setStarting() doesn't touch it).
# "Start" is now two presses since the Mode Select screen landed: PLAY opens
# the overlay, CLASSIC on it starts the game (see smoke_start_new_game.gd).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_shop_map_flow.gd --quit-after 8

var opened := false
var started := false
var clicked_shop := false
var left_shop := false
var checked_return := false

func _initialize():
	print(">>> SMOKE TEST: map shop room -> Shop scene -> LEAVE -> map <<<")
	root.get_node("PlayerManager").current_map_tier = 1
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

	if not clicked_shop:
		var map_instance = gf.current_map_instance
		if map_instance == null or not is_instance_valid(map_instance) or not map_instance.is_initialized:
			return false # still waiting for the deferred _initialize_game()

		var shop_floor: int = map_instance.generator.shop_floor
		if shop_floor < 0:
			push_error("SMOKE TEST FAILED: tier 1 map generated with no shop_floor configured")
			return true

		var shop_room = null
		for room in map_instance.map_data[shop_floor]:
			if room != null:
				shop_room = room
				break

		if shop_room == null:
			push_error("SMOKE TEST FAILED: no room found on the shop floor (%d)" % shop_floor)
			return true
		if shop_room.type != Room.RoomType.shop:
			push_error("SMOKE TEST FAILED: shop floor room has type %s, not shop" % Room.RoomTypeNames.get(shop_room.type, "?"))
			return true

		map_instance._on_room_selected(shop_room)
		clicked_shop = true
		return false

	if not left_shop:
		var shop_scene = current_scene
		if shop_scene == null or not shop_scene.has_method("_on_leave_pressed"):
			return false # still waiting for the deferred scene swap to Shop

		shop_scene._on_leave_pressed()
		left_shop = true
		return false

	if checked_return:
		return false

	if current_scene == null or current_scene != gf.current_map_instance:
		return false # still waiting for the deferred return_to_map()

	checked_return = true
	print(">>> SMOKE TEST: shop map flow completed cleanly, back on the map <<<")
	return false
