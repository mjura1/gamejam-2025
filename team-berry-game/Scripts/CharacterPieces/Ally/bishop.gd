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

# ----------------- SPOSOBNOSTI -----------------

const ABILITY_DEFS = [
	{
		"id": "longshot", "name": "Longshot", "needs_target": true,
		"base": {"uses": 1, "desc": "Capture one enemy piece within line of sight, without moving."},
		"upgraded": {"uses": 2, "desc": "Capture one enemy piece within line of sight, without moving."},
	},
	{
		"id": "traps", "name": "Traps", "needs_target": false,
		"base": {"uses": 1, "radius": 1, "desc": "Until this bishop moves, enemies within 3x3 of this tile cannot move at all."},
		"upgraded": {"uses": 2, "radius": 2, "desc": "Until this bishop moves, enemies within 5x5 of this tile cannot move at all."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func get_ability_targets(slot: int) -> Array[Vector2i]:
	if slot == 1:
		var positions: Array[Vector2i] = []
		for enemy in find_visible_enemies(move_range):
			positions.append(enemy.grid_pos)
		return positions
	return []

func _execute_ability(id: String, target) -> bool:
	match id:
		"longshot":
			return _do_longshot(target)
		"traps":
			return _do_traps(_tier_data(2).get("radius", 1))
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
func _do_traps(radius: int) -> bool:
	if owned_zone_id != -1:
		grid_manager.remove_zone(owned_zone_id)
	owned_zone_id = grid_manager.add_zone("freeze", grid_pos, radius, is_enemy)
	return true
