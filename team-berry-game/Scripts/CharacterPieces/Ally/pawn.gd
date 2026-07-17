extends BaseCharacter

func _ready():
	move_range = 2
	strName = "pawn"
	super._ready()

func get_move_directions() -> Array[Vector2i]:
	return [
		Vector2i( 1,  0),
		Vector2i(-1,  0),
		Vector2i( 0,  1),
		Vector2i( 0, -1),
		Vector2i( 1,  1),
		Vector2i( 1, -1),
		Vector2i(-1,  1),
		Vector2i(-1, -1),
	]

# ----------------- SPOSOBNOSTI -----------------

const ABILITY_DEFS = [
	{
		"id": "rally", "name": "Rally", "needs_target": false,
		"base": {"uses": 1, "desc": "Move every other allied piece onto a free tile adjacent to this pawn."},
		"upgraded": {"uses": 2, "desc": "Move every other allied piece onto a free tile adjacent to this pawn."},
	},
	{
		"id": "lantern_signal", "name": "Lantern Signal", "needs_target": false,
		"base": {"uses": 1, "radius": 2, "desc": "Clear the snow in a 5x5 area around every allied piece."},
		"upgraded": {"uses": 2, "radius": 3, "desc": "Clear the snow in a 7x7 area around every allied piece."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func _execute_ability(id: String, _target) -> bool:
	match id:
		"rally":
			return _do_rally()
		"lantern_signal":
			return _do_lantern_signal(_tier_data(2).get("radius", 2))
	return false

# Premakne vse ostale zavezniške figure na prosta polja tik ob tem pešcu.
func _do_rally() -> bool:
	var candidates := _free_adjacent_tiles()
	if candidates.is_empty():
		return false

	var moved_any := false
	for ally in grid_manager.get_all_characters():
		if candidates.is_empty():
			break
		if not is_instance_valid(ally) or not (ally is BaseCharacter):
			continue
		if ally == self or ally.is_enemy or ally.is_obstacle:
			continue
		var dest: Vector2i = candidates.pop_front()
		ally.execute_move(dest)
		moved_any = true

	return moved_any

func _free_adjacent_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var used_rect = tile_map.get_used_rect()
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var p := grid_pos + Vector2i(dx, dy)
			if grid_manager.is_inside_boundary(p, used_rect) and not grid_manager.is_occupied(p):
				tiles.append(p)
	return tiles

# Razkrije meglo v "radius" ploščic okoli VSAKE žive zavezniške figure.
func _do_lantern_signal(radius: int) -> bool:
	var reveal_positions: Array[Vector2i] = []
	for ally in grid_manager.get_all_characters():
		if not is_instance_valid(ally) or not (ally is BaseCharacter):
			continue
		if ally.is_enemy or ally.is_obstacle:
			continue
		reveal_positions.append_array(GridManager.square_radius_tiles(ally.grid_pos, radius))

	grid_manager.reveal_area(reveal_positions)
	return true
