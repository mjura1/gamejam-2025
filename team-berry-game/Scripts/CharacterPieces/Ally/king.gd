extends BaseCharacter

# Koren battle scene - battle.gd nosi friendly_pieces slovar (ime -> scena),
# potreben za ponovni spawn ob Heal.
@onready var battle_root = get_node("..")

func _ready():
	move_range = 12
	strName = "king"
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
		"id": "cleanse", "name": "Cleanse", "needs_target": false,
		"base": {"uses": 1, "desc": "Convert every enemy within this king's line of sight into a temporary ally for the rest of this battle."},
		"upgraded": {"uses": 2, "desc": "Convert every enemy within this king's line of sight into a temporary ally for the rest of this battle."},
	},
	{
		"id": "heal", "name": "Heal", "needs_target": false,
		"base": {"uses": 2, "revive_all": false, "desc": "Revive the most recently fallen ally onto an empty tile within this king's line of sight."},
		"upgraded": {"uses": 1, "revive_all": true, "desc": "Revive every fallen ally onto empty tiles within this king's line of sight."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func _execute_ability(id: String, _target) -> bool:
	match id:
		"cleanse":
			return _do_cleanse()
		"heal":
			return _do_heal(_tier_data(2).get("revive_all", false))
	return false

# Obrne vse vidne sovražnike na svojo stran - samo za to bitko (glej
# is_converted_ally in PlayerManager.convert_enemy_to_ally).
func _do_cleanse() -> bool:
	var enemies := find_visible_enemies(move_range)
	if enemies.is_empty():
		return false

	for target in enemies:
		player_manager.convert_enemy_to_ally("enemy_" + target.strName, "friendly_" + target.strName)
		target.is_enemy = false
		target.is_converted_ally = true

	return true

# Obudi padle zaveznike (iz player_manager.dead_party) na prosta polja v
# dosegu pogleda tega kralja - najbližja polja dobijo prednost.
func _do_heal(revive_all: bool) -> bool:
	if player_manager.dead_party.is_empty():
		return false

	var names: Array = player_manager.dead_party.duplicate() if revive_all else [player_manager.dead_party[-1]]

	var empty_tiles := get_empty_tiles_in_los(move_range)
	empty_tiles.sort_custom(func(a, b): return grid_pos.distance_to(a) < grid_pos.distance_to(b))

	var revived_any := false
	for character_name in names:
		if empty_tiles.is_empty():
			break
		if not battle_root.friendly_pieces.has(character_name):
			continue

		var tile: Vector2i = empty_tiles.pop_front()
		var scene: PackedScene = battle_root.friendly_pieces[character_name]
		grid_manager.spawn_character(scene, grid_manager.grid_to_world(tile))
		player_manager.revive_character(character_name)
		revived_any = true

	return revived_any
