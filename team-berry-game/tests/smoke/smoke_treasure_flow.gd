extends SceneTree

# Drives the real "Start -> click item room -> Treasure scene -> click chest ->
# ChestRewardPanel -> CONTINUE -> map" flow headlessly, mirroring
# smoke_shop_map_flow.gd. Unlike the shop (fixed shop_floor index), item rooms
# are placed by a flat per-floor chance roll with no seed (MapGenerator
# ITEM_ROOM_CHANCE) - so every floor/room in map_data is scanned for one
# instead of indexing a known floor. No item room on this particular random
# map is treated as a rare, acceptable flake (like smoke_shop_map_flow /
# smoke_campfire_flow on tier-0-generated maps), not something to chase - see
# plans/TREASURE_CHEST_PLAN.md §2f.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_treasure_flow.gd --quit-after 8

var opened := false
var started := false
var clicked_item_room := false
var opened_chest := false
var continued := false
var checked_return := false

func _initialize():
	print(">>> SMOKE TEST: map item room -> Treasure scene -> chest -> reveal -> map <<<")
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

	if not clicked_item_room:
		var map_instance = gf.current_map_instance
		if map_instance == null or not is_instance_valid(map_instance) or not map_instance.is_initialized:
			return false # still waiting for the deferred _initialize_game()

		var item_room = null
		for floor_rooms in map_instance.map_data:
			for room in floor_rooms:
				if room != null and room.type == Room.RoomType.item:
					item_room = room
					break
			if item_room != null:
				break

		if item_room == null:
			print(">>> SMOKE TEST: no item room on this randomly generated map - acceptable flake, skipping <<<")
			return true

		map_instance._on_room_selected(item_room)
		clicked_item_room = true
		return false

	if not opened_chest:
		var treasure_scene = current_scene
		if treasure_scene == null or not treasure_scene.has_method("_on_chest_pressed"):
			return false # still waiting for the deferred scene swap to Treasure

		treasure_scene._on_chest_pressed()
		opened_chest = true
		return false

	if not continued:
		var panel = root.find_child("ChestRewardPanelNode", true, false)
		if panel == null or not is_instance_valid(panel):
			return false # still waiting for the reveal panel to be added

		panel._on_continue_pressed()
		continued = true
		return false

	if checked_return:
		return false

	if current_scene == null or current_scene != gf.current_map_instance:
		return false # still waiting for the deferred return_to_map()

	checked_return = true
	print(">>> SMOKE TEST: treasure flow completed cleanly, back on the map <<<")
	return false
