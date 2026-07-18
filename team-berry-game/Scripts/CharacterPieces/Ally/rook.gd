extends BaseCharacter

func _ready():
	move_range = 8
	strName = "rook"
	super._ready()

func get_move_directions() -> Array[Vector2i]:
	return [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]
# calculate_valid_targets() se podeduje

# ----------------- SPOSOBNOSTI -----------------

const ABILITY_DEFS = [
	{
		"id": "lookout", "name": "Lookout", "needs_target": false,
		"base": {"shape": "square", "radius": 1, "desc": "Reveal the closest fog-obscured enemy and clear the snow in 3x3 around them."},
		"mid": {"shape": "plus", "desc": "Reveal the closest fog-obscured enemy and clear the snow in a 3x3 + cross-shaped area around them."},
		"upgraded": {"shape": "square", "radius": 2, "desc": "Reveal the closest fog-obscured enemy and clear the snow in 5x5 around them."},
	},
	{
		"id": "reinforce", "name": "Reinforce", "needs_target": false,
		"base": {"shape": "square", "radius": 1, "desc": "Until this rook moves, no enemy can move onto any tile within 3x3 of this tile."},
		"mid": {"shape": "plus", "desc": "Until this rook moves, no enemy can move onto any tile within a 3x3 + cross-shaped area of this tile."},
		"upgraded": {"shape": "square", "radius": 2, "desc": "Until this rook moves, no enemy can move onto any tile within 5x5 of this tile."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func _execute_ability(id: String, _target) -> bool:
	match id:
		"lookout":
			return _do_lookout(_tier_data(1))
		"reinforce":
			return _do_reinforce(_tier_data(2))
	return false

# Poišče najbližjega sovražnika, ki stoji na trenutno zamegljenem polju, in
# razkrije meglo okoli njega (v obliki tier-ja, glej _area_tiles).
func _do_lookout(tier: Dictionary) -> bool:
	var closest: BaseCharacter = null
	var closest_dist := INF

	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character) or not (character is BaseCharacter):
			continue
		if character.is_enemy == is_enemy or character.is_obstacle:
			continue
		if not grid_manager.fog_nodes.has(character.grid_pos) and not grid_manager.curse_fog_nodes.has(character.grid_pos):
			continue

		var d = grid_pos.distance_to(character.grid_pos)
		if d < closest_dist:
			closest_dist = d
			closest = character

	if not is_instance_valid(closest):
		return false

	var area: Array[Vector2i] = _area_tiles(tier, closest.grid_pos)
	grid_manager.reveal_area(area)
	grid_manager.clear_curse_fog_area(area)
	return true

# Postavi (ali obnovi) cono, ki sovražnikom prepove premik na polja znotraj nje.
func _do_reinforce(tier: Dictionary) -> bool:
	if owned_zone_id != -1:
		grid_manager.remove_zone(owned_zone_id)
	var shape_offsets: Array[Vector2i] = []
	if tier.get("shape", "square") == "plus":
		shape_offsets = _area_offsets(tier)
	owned_zone_id = grid_manager.add_zone("deny_entry", grid_pos, tier.get("radius", 1), is_enemy, shape_offsets)
	return true
