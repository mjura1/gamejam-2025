# res://Scripts/Items/frozen_rampart_item.gd
# Artefakt "frozen_rampart": ista ovira/pravila kot barricade (glej
# barricade_item.gd), a se NE porabi iz inventarja - battle_ui.gd.use_item()
# ima poseben primer za ta id (glej tam), ki namesto remove_item() postavi
# battle_controller.frozen_rampart_used_this_battle na true (enkrat na bitko,
# ne glede na to, koliko premikov/potez je minilo).
extends BaseItem

const OBSTACLE_SCENE: PackedScene = preload("res://Scenes/CharacterPiecesNodes/Neutral/House.tscn")

func _init():
	id = "frozen_rampart"

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
