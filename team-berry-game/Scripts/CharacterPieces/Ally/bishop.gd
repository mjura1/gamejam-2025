extends BaseCharacter

func _ready():
	move_range = 8
	strName = "bishop"
	super._ready()

func get_move_directions() -> Array[Vector2i]:
	return [
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]

const CROSS_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

# Item "mounted_hunters": igralčev lovec se lahko premakne/zajme tudi kot
# vitez (pravi skoki, ne drsenje - is_enemy vrata pomembna, ker sovražnikov
# lovec deli isto skripto, glej §0 gotcha v SHOP_V2_PLAN.md).
func calculate_valid_targets() -> Array[Vector2i]:
	var targets := super.calculate_valid_targets()
	if is_enemy or not player_manager.has_passive("mounted_hunters"):
		return targets
	if grid_manager.is_frozen(grid_pos, is_enemy): # super je za to že vrnil []
		return targets
	for offset in KNIGHT_OFFSETS:
		var pos := grid_pos + offset
		if pos in targets: continue
		if not grid_manager.is_inside_boundary(pos, tile_map.get_used_rect()): continue
		if grid_manager.is_entry_denied(pos, is_enemy): continue
		var c = grid_manager.get_character_at(pos)
		if c == null:
			targets.append(pos)
		elif c.is_enemy != is_enemy and not c.is_obstacle and not c.is_capture_immune \
				and not c.is_castle_protected():
			targets.append(pos)
	return targets

# ----------------- SPOSOBNOSTI -----------------

const ABILITY_DEFS = [
	{
		"id": "longshot", "name": "Longshot", "needs_target": true,
		"base": {"cross": false, "desc": "Capture one enemy piece diagonally within line of sight (X pattern), without moving."},
		"mid": {"cross": true, "desc": "Capture one enemy piece within line of sight (diagonal or straight), without moving."},
		"upgraded": {"cross": true, "desc": "Capture one enemy piece within line of sight (diagonal or straight), without moving."},
	},
	{
		"id": "traps", "name": "Traps", "needs_target": false,
		"base": {"shape": "square", "radius": 1, "desc": "Until this bishop moves, enemies within 3x3 of this tile cannot move at all."},
		"mid": {"shape": "plus", "desc": "Until this bishop moves, enemies within a 3x3 + cross-shaped area of this tile cannot move at all."},
		"upgraded": {"shape": "square", "radius": 2, "desc": "Until this bishop moves, enemies within 5x5 of this tile cannot move at all."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

# Lv1: samo diagonalne smeri (X). Lv2+: diagonale + ravne smeri (X in +).
func _longshot_directions() -> Array[Vector2i]:
	if not _tier_data(1).get("cross", false):
		return get_move_directions()
	var dirs: Array[Vector2i] = get_move_directions().duplicate()
	dirs.append_array(CROSS_DIRECTIONS)
	return dirs

func get_ability_targets(slot: int) -> Array[Vector2i]:
	if slot == 1:
		var positions: Array[Vector2i] = []
		for enemy in find_visible_enemies(move_range, _longshot_directions()):
			positions.append(enemy.grid_pos)
		return positions
	return []

func _execute_ability(id: String, target) -> bool:
	match id:
		"longshot":
			return _do_longshot(target)
		"traps":
			return _do_traps(_tier_data(2))
	return false

# Zajame vidnega sovražnika, ne da bi se lovec premaknil (mimo capture(), ki
# vedno premakne napadalca na tarčino polje).
func _do_longshot(target) -> bool:
	var target_char = grid_manager.get_character_at(target)
	if not (target_char is BaseCharacter) or target_char.is_enemy == is_enemy:
		return false
	if target_char.is_capture_immune: # Knight.Evade
		return false
	target_char.die()
	if take_sound: take_sound.play()
	return true

# Postavi (ali obnovi) zamrznitveno cono na trenutnem polju lovca.
func _do_traps(tier: Dictionary) -> bool:
	if owned_zone_id != -1:
		grid_manager.remove_zone(owned_zone_id)
	var shape_offsets: Array[Vector2i] = []
	if tier.get("shape", "square") == "plus":
		shape_offsets = _area_offsets(tier)
	owned_zone_id = grid_manager.add_zone("freeze", grid_pos, tier.get("radius", 1), is_enemy, shape_offsets)
	return true
