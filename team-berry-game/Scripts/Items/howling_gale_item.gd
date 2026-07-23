# res://Scripts/Items/howling_gale_item.gd
# Enkratna uporaba: brainstorm pravi "clear a full row OR column" (igralčeva
# izbira) - ta UI nima orientacijskega izbirnika (drag-drop je en sam grid_pos
# klik/spust, brez modifikatorja/drugega gumba za "row vs column"), zato
# DEVIACIJA: vedno cela VRSTICA skozi grid_pos.y, stolpec ni ponujen. Enostaven,
# deterministicen privzetek namesto ugibanja UI-ja, ki ne obstaja.
extends BaseItem

func _init():
	id = "howling_gale"

func _row_tiles(battle_controller, grid_pos: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not is_instance_valid(battle_controller.tile_map):
		return tiles
	var used_rect: Rect2i = battle_controller.tile_map.get_used_rect()
	for x in range(used_rect.position.x, used_rect.end.x):
		tiles.append(Vector2i(x, grid_pos.y))
	return tiles

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	battle_controller.grid_manager.reveal_area(_row_tiles(battle_controller, grid_pos))
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return []
