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
	{
		"id": "castling", "name": "Castling", "needs_target": true,
		"base": {"who": "king", "los": true, "desc": "Swap positions with your king if he is in this rook's line of sight."},
		"mid": {"who": "any", "los": true, "desc": "Swap positions with any ally in this rook's line of sight."},
		"upgraded": {"who": "any", "los": false, "desc": "Swap positions with any allied piece anywhere."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func get_ability_targets(slot: int) -> Array[Vector2i]:
	if slot == 3:
		return _castling_targets(_tier_data(3))
	return []

# Zbere zaveznike, ki so veljavne Castling tarče: LOS-omejeno (find_visible_allies,
# glej base_character.gd) ali celotna plošča, glede na tier.los, nato po
# potrebi filtrira na samo kralja (tier.who == "king").
func _castling_targets(tier: Dictionary) -> Array[Vector2i]:
	var who: String = tier.get("who", "king")
	var candidates: Array[BaseCharacter] = []
	if tier.get("los", true):
		candidates = find_visible_allies(move_range)
	else:
		for character in grid_manager.get_all_characters():
			if not is_instance_valid(character) or not (character is BaseCharacter):
				continue
			if character == self or character.is_enemy != is_enemy or character.is_obstacle:
				continue
			candidates.append(character)

	var targets: Array[Vector2i] = []
	for ally in candidates:
		if who == "king" and ally.strName != "king":
			continue
		targets.append(ally.grid_pos)
	return targets

func _execute_ability(id: String, target) -> bool:
	match id:
		"lookout":
			return _do_lookout(_tier_data(1))
		"reinforce":
			return _do_reinforce(_tier_data(2))
		"castling":
			return _do_castling(target)
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

# Zamenja polji s ciljnim zaveznikom - grid_manager.swap_characters() že
# opravi vse (vakacija/okupacija obeh polj + drsenje), glej SKILL_TREE_PLAN.md
# §4.4. Cilj je bil že filtriran skozi get_ability_targets(3) (glej
# Knight._do_ambush za isti "UI že filtrirala klik" vzorec) - tu samo minimalna
# zaščita, da je na polju res zaveznik.
func _do_castling(target: Vector2i) -> bool:
	var ally = grid_manager.get_character_at(target)
	if not (ally is BaseCharacter) or ally.is_enemy != is_enemy or ally == self:
		return false
	grid_manager.swap_characters(self, ally)
	return true
