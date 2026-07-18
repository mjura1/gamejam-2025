# res://Scripts/Items/barricade_item.gd
# Enkratna uporaba: postavi oviro (ista is_obstacle logika kot House, glej
# Scripts/Neutral/house.gd) na prazno polje - blokira sovražnikovo gibanje/
# pogled skozi to polje, a je ni mogoče zajeti (base_character.gd
# calculate_valid_targets izključi is_obstacle iz veljavnih tarč).
extends BaseItem

const OBSTACLE_SCENE: PackedScene = preload("res://Scenes/CharacterPiecesNodes/Neutral/House.tscn")

func _init():
	id = "barricade"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	if not is_instance_valid(battle_controller.grid_manager) or not is_instance_valid(battle_controller.tile_map):
		return false
	if not battle_controller.grid_manager.is_inside_boundary(grid_pos, battle_controller.tile_map.get_used_rect()):
		return false
	return not battle_controller.grid_manager.is_occupied(grid_pos)

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	battle_controller.grid_manager.spawn_character(OBSTACLE_SCENE, battle_controller.grid_manager.grid_to_world(grid_pos))
	return true
