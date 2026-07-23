# res://Scripts/Items/bastion_item.gd
# Enkratna uporaba: kot barricade (glej barricade_item.gd) - ista ovira/
# pravila - a postavi DVE oviri namesto ene: eno na izbrano polje, eno na
# naključno prazno sosednje polje (8 smeri okoli prve). Če ni prostega
# sosednjega polja, ostane veljavna uporaba z eno samo oviro.
extends BaseItem

const OBSTACLE_SCENE: PackedScene = preload("res://Scenes/CharacterPiecesNodes/Neutral/House.tscn")

func _init():
	id = "bastion"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	if not is_instance_valid(battle_controller.grid_manager) or not is_instance_valid(battle_controller.tile_map):
		return false
	if not battle_controller.grid_manager.is_inside_boundary(grid_pos, battle_controller.tile_map.get_used_rect()):
		return false
	return not battle_controller.grid_manager.is_occupied(grid_pos)

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	grid_manager.spawn_character(OBSTACLE_SCENE, grid_manager.grid_to_world(grid_pos))

	var used_rect: Rect2i = battle_controller.tile_map.get_used_rect()
	var candidates: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var pos := grid_pos + Vector2i(dx, dy)
			if grid_manager.is_inside_boundary(pos, used_rect) and not grid_manager.is_occupied(pos):
				candidates.append(pos)
	if not candidates.is_empty():
		grid_manager.spawn_character(OBSTACLE_SCENE, grid_manager.grid_to_world(candidates.pick_random()))
	return true
