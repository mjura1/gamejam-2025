# res://Scripts/Items/blizzard_ender_item.gd
# Snow-clear chain: Flare(C, 3x3) -> bonfire_flare(U, 5x5) -> Wildfire
# Flare(R, existing) -> blizzard_ender (E, entire battlefield) -> Aurora
# Flare(L, existing, same "whole board" scope - see its own comment).
# RESOLVED research (NEW_ITEMS_WAVE2_PLAN.md Phase 5): "room" in this
# codebase (Scripts/Map/map_point.gd) is a strategic-map graph node only,
# zero tile data - a battle's tile_map is always ONE undivided grid, so
# "the current room" at battle time already just means the whole board.
# Effect is therefore identical to aurora_flare_item.gd's apply() - kept as
# a separate file (not a subclass) to match this codebase's "1 item = 1
# script" convention (see item_data.gd ITEM_SCRIPTS comment).
extends BaseItem

func _init():
	id = "blizzard_ender"

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	var used_rect: Rect2i = battle_controller.tile_map.get_used_rect()
	var all_tiles: Array[Vector2i] = []
	for x in range(used_rect.position.x, used_rect.end.x):
		for y in range(used_rect.position.y, used_rect.end.y):
			all_tiles.append(Vector2i(x, y))
	grid_manager.reveal_area(all_tiles)
	return true
