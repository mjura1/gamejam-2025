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
		"base": {"uses": 2, "radius": 1, "desc": "Reveal the closest fog-obscured enemy and clear the snow in 3x3 around them."},
		"upgraded": {"uses": 3, "radius": 2, "desc": "Reveal the closest fog-obscured enemy and clear the snow in 5x5 around them."},
	},
	{
		"id": "reinforce", "name": "Reinforce", "needs_target": false,
		"base": {"uses": 1, "radius": 1, "desc": "Until this rook moves, no enemy can move onto any tile within 3x3 of this tile."},
		"upgraded": {"uses": 2, "radius": 2, "desc": "Until this rook moves, no enemy can move onto any tile within 5x5 of this tile."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func _execute_ability(id: String, _target) -> bool:
	match id:
		"lookout":
			return _do_lookout(_tier_data(1).get("radius", 1))
		"reinforce":
			return _do_reinforce(_tier_data(2).get("radius", 1))
	return false

# Poišče najbližjega sovražnika, ki stoji na trenutno zamegljenem polju, in
# razkrije meglo okoli njega.
func _do_lookout(radius: int) -> bool:
	var closest: BaseCharacter = null
	var closest_dist := INF

	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character) or not (character is BaseCharacter):
			continue
		if character.is_enemy == is_enemy or character.is_obstacle:
			continue
		if not grid_manager.fog_nodes.has(character.grid_pos):
			continue

		var d = grid_pos.distance_to(character.grid_pos)
		if d < closest_dist:
			closest_dist = d
			closest = character

	if not is_instance_valid(closest):
		return false

	grid_manager.reveal_area(GridManager.square_radius_tiles(closest.grid_pos, radius))
	return true

# Postavi (ali obnovi) cono, ki sovražnikom prepove premik na polja znotraj nje.
func _do_reinforce(radius: int) -> bool:
	if owned_zone_id != -1:
		grid_manager.remove_zone(owned_zone_id)
	owned_zone_id = grid_manager.add_zone("deny_entry", grid_pos, radius, is_enemy)
	return true
