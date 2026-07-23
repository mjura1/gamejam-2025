# res://Scripts/Items/decoy_item.gd
# Enkratna uporaba: postavi vabo (glej decoy.tscn - navaden BaseCharacter,
# is_decoy=true, brez svojih premikov/sposobnosti - glej base_character.gd
# is_decoy deklaracijo za celoten seznam posebnih obravnav) na prazno polje.
# Ista "spawn_character na prazno polje" logika kot barricade_item.gd, a
# figura je resnično zajemljiva (za razliko od barricade/House, ki sta
# is_obstacle in torej izključena iz zajetja).
extends BaseItem

const DECOY_SCENE: PackedScene = preload("res://Scenes/CharacterPiecesNodes/Neutral/decoy.tscn")

func _init():
	id = "decoy"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	if not is_instance_valid(battle_controller.grid_manager) or not is_instance_valid(battle_controller.tile_map):
		return false
	if not battle_controller.grid_manager.is_inside_boundary(grid_pos, battle_controller.tile_map.get_used_rect()):
		return false
	return not battle_controller.grid_manager.is_occupied(grid_pos)

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	battle_controller.grid_manager.spawn_character(DECOY_SCENE, battle_controller.grid_manager.grid_to_world(grid_pos))
	var placed = battle_controller.grid_manager.get_character_at(grid_pos)
	if placed is BaseCharacter:
		battle_controller.decoys_active.append(placed)
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
