extends TestCase

# Regression test for the reported bug: "Divine Intervention returns you to
# the map, but the stage you fled from is never playable again." Root cause:
# MapController._update_reachable_rooms() marks a room selected/locked the
# moment it's clicked, BEFORE the battle is even played - so when the player
# flees a loss via Divine Intervention (instead of winning), the room is left
# in the same state as if it had been won. revert_current_room_selection()
# undoes that premature mutation; these tests drive it directly (no live
# scene tree needed - only map_data/Room state is touched by the code under
# test, not the @onready camera/UI nodes).

const MapControllerScript = preload("res://Scripts/Map/MapController.gd")
const MapGeneratorScript = preload("res://Scripts/Map/MapGenerator.gd")

func _first_room(floor_rooms: Array) -> Room:
	for room in floor_rooms:
		if room != null:
			return room
	return null

func _make_controller() -> Node:
	var mc = MapControllerScript.new()
	mc.generator = MapGeneratorScript.new()
	mc.map_data = mc.generator.generate_map(0)
	mc._set_initial_state()
	return mc

func test_revert_after_fleeing_first_room_makes_it_playable_again():
	var mc = _make_controller()
	var start_room = _first_room(mc.map_data[0])

	mc.previous_room = mc.current_room # null - mirrors _on_room_selected's bookkeeping
	mc._update_reachable_rooms(start_room)
	assert_true(start_room.selected, "selecting a room should mark it selected immediately, before the battle plays out")
	assert_false(start_room.is_unlocked, "a selected room should look locked/played while its battle is in progress")

	mc.revert_current_room_selection()

	assert_false(start_room.selected, "Divine Intervention revert should unselect the room fled from")
	assert_true(start_room.is_unlocked, "Divine Intervention revert should make the fled-from room playable again")

func test_revert_after_fleeing_second_room_restores_previous_room_as_current():
	var mc = _make_controller()
	var start_room = _first_room(mc.map_data[0])

	mc.previous_room = mc.current_room
	mc._update_reachable_rooms(start_room)

	assert_true(not start_room.next_rooms.is_empty(), "test setup expects the start room to connect onward")
	var second_room: Room = start_room.next_rooms[0]

	mc.previous_room = mc.current_room # = start_room
	mc._update_reachable_rooms(second_room)
	assert_true(second_room.selected, "selecting the second room should mark it selected immediately")
	assert_true(start_room.selected, "the room already passed through should remain marked cleared")

	mc.revert_current_room_selection()

	assert_false(second_room.selected, "the room fled from should become selectable again")
	assert_true(second_room.is_unlocked, "the room fled from should be playable again after Divine Intervention")
	assert_true(start_room.selected, "a room the player didn't flee from should be unaffected by the revert")
	assert_eq(mc.current_room, start_room, "current_room should move back to the room before the one fled from")

func test_revert_with_no_current_room_is_a_safe_no_op():
	var mc = _make_controller()
	mc.revert_current_room_selection() # current_room is still null - must not error
	assert_eq(mc.current_room, null, "reverting with nothing selected should stay a no-op")
