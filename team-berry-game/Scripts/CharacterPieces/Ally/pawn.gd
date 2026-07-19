extends BaseCharacter

# Koren battle scene - battle.gd nosi friendly_pieces slovar (ime -> scena),
# potreben za spawn nadgrajene figure ob Promotion (glej king.gd Heal za isti
# vzorec).
@onready var battle_root = get_node("..")

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
		"base": {"ally_count": 1, "desc": "Move the nearest allied piece onto a free tile adjacent to this pawn."},
		"mid": {"ally_count": 3, "desc": "Move the 3 closest allied pieces onto free tiles adjacent to this pawn."},
		"upgraded": {"ally_count": -1, "desc": "Move every other allied piece onto a free tile adjacent to this pawn."},
	},
	{
		"id": "lantern_signal", "name": "Lantern Signal", "needs_target": false,
		"base": {"shape": "square", "radius": 1, "desc": "Clear the snow in a 3x3 area around every allied piece."},
		"mid": {"shape": "plus", "desc": "Clear the snow in a 3x3 + cross-shaped area around every allied piece."},
		"upgraded": {"shape": "square", "radius": 2, "desc": "Clear the snow in a 5x5 area around every allied piece."},
	},
	{
		"id": "promotion", "name": "Promotion", "needs_target": false,
		"base": {"promote_to": "knight", "desc": "This pawn permanently becomes a knight for the rest of this battle."},
		"mid": {"promote_to": "rook", "desc": "This pawn permanently becomes a rook for the rest of this battle."},
		"upgraded": {"promote_to": "queen", "desc": "This pawn permanently becomes a queen for the rest of this battle."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func _execute_ability(id: String, _target) -> bool:
	match id:
		"rally":
			return _do_rally(_tier_data(1).get("ally_count", -1))
		"lantern_signal":
			return _do_lantern_signal(_tier_data(2))
		"promotion":
			return _do_promotion(_tier_data(3).get("promote_to", "knight"))
	return false

# Premakne najbližjih "ally_count" zavezniških figur na prosta polja tik ob
# tem pešcu (-1 pomeni "vse", glej ABILITY_DEFS).
func _do_rally(ally_count: int) -> bool:
	var candidates := _free_adjacent_tiles()
	if candidates.is_empty():
		return false

	var allies: Array[BaseCharacter] = []
	for ally in grid_manager.get_all_characters():
		if not is_instance_valid(ally) or not (ally is BaseCharacter):
			continue
		if ally == self or ally.is_enemy or ally.is_obstacle:
			continue
		allies.append(ally)

	allies.sort_custom(func(a, b): return grid_pos.distance_to(a.grid_pos) < grid_pos.distance_to(b.grid_pos))
	var chosen: Array[BaseCharacter] = allies if ally_count < 0 else allies.slice(0, ally_count)

	var moved_any := false
	for ally in chosen:
		if candidates.is_empty():
			break
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

# Razkrije meglo v obliki tier-ja (glej _area_tiles) okoli VSAKE žive
# zavezniške figure.
func _do_lantern_signal(tier: Dictionary) -> bool:
	var reveal_positions: Array[Vector2i] = []
	for ally in grid_manager.get_all_characters():
		if not is_instance_valid(ally) or not (ally is BaseCharacter):
			continue
		if ally.is_enemy or ally.is_obstacle:
			continue
		reveal_positions.append_array(_area_tiles(tier, ally.grid_pos))

	grid_manager.reveal_area(reveal_positions)
	return true

# Nadomesti tega pešca s "promote_to" figuro na istem polju za preostanek te
# bitke. Reuses the King.Cleanse/bloodhound-wolf temp-ally pathway (glej
# PlayerManager.add_temporary_ally): odstranitev pešca NE sme šteti kot smrt -
# is_converted_ally usmeri BaseCharacter.die() skozi
# PlayerManager.remove_converted_ally() namesto register_dead_character(), da
# dead_party (ki ga bere King.Heal) nikoli ne vidi "friendly_pawn".
func _do_promotion(promote_to: String) -> bool:
	var roster_name := "friendly_" + promote_to
	if not battle_root.friendly_pieces.has(roster_name):
		return false

	var spawn_pos: Vector2 = grid_manager.grid_to_world(grid_pos)
	var scene: PackedScene = battle_root.friendly_pieces[roster_name]

	is_converted_ally = true
	die()

	var promoted: BaseCharacter = grid_manager.spawn_character(scene, spawn_pos)
	promoted.is_converted_ally = true
	player_manager.add_temporary_ally(roster_name)
	return true
