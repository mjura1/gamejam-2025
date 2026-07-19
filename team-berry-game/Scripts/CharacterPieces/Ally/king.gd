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
		"base": {"enemy_count": 1, "desc": "Convert the closest enemy within this king's line of sight into a temporary ally for the rest of this battle."},
		"mid": {"enemy_count": 3, "desc": "Convert the 3 closest enemies within this king's line of sight into temporary allies for the rest of this battle."},
		"upgraded": {"enemy_count": -1, "desc": "Convert every enemy within this king's line of sight into a temporary ally for the rest of this battle."},
	},
	{
		"id": "heal", "name": "Heal", "needs_target": false,
		"base": {"revive_count": 1, "desc": "Revive the most recently fallen ally onto an empty tile within this king's line of sight."},
		"mid": {"revive_count": 3, "desc": "Revive up to 3 of the most recently fallen allies onto empty tiles within this king's line of sight."},
		"upgraded": {"revive_count": -1, "desc": "Revive every fallen ally onto empty tiles within this king's line of sight."},
	},
	{
		"id": "royal_decree", "name": "Royal Decree", "needs_target": false,
		"base": {"shape": "square", "radius": 1, "desc": "Allies within 3x3 of the king cannot be captured until your next turn."},
		"mid": {"shape": "plus", "desc": "Allies within a 3x3 + cross-shaped area of the king cannot be captured until your next turn."},
		"upgraded": {"all": true, "desc": "No ally can be captured until your next turn."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func _execute_ability(id: String, _target) -> bool:
	match id:
		"cleanse":
			return _do_cleanse(_tier_data(1).get("enemy_count", -1))
		"heal":
			return _do_heal(_tier_data(2).get("revive_count", 1))
		"royal_decree":
			return _do_royal_decree(_tier_data(3))
	return false

# Obrne najbližjih "enemy_count" vidnih sovražnikov na svojo stran - samo za
# to bitko (glej is_converted_ally in PlayerManager.convert_enemy_to_ally).
# enemy_count < 0 pomeni "vse" (glej ABILITY_DEFS).
func _do_cleanse(enemy_count: int) -> bool:
	var enemies := find_visible_enemies(move_range)
	if enemies.is_empty():
		return false

	enemies.sort_custom(func(a, b): return grid_pos.distance_to(a.grid_pos) < grid_pos.distance_to(b.grid_pos))
	var chosen: Array[BaseCharacter] = enemies if enemy_count < 0 else enemies.slice(0, enemy_count)

	for target in chosen:
		player_manager.convert_enemy_to_ally("enemy_" + target.strName, "friendly_" + target.strName)
		target.is_enemy = false
		target.is_converted_ally = true
		# Prekletstvo NE preide z obrnjeno figuro na igralčevo stran - očisti
		# stanje in vizualni marker/tint (glej base_character.clear_curse).
		if target.curse:
			target.clear_curse()

	return true

# Obudi padle zaveznike (iz player_manager.dead_party) na prosta polja v
# dosegu pogleda tega kralja - najbližja polja dobijo prednost. revive_count
# < 0 pomeni "obudi vse", sicer obudi zadnjih N padlih (glej ABILITY_DEFS).
func _do_heal(revive_count: int) -> bool:
	if player_manager.dead_party.is_empty():
		return false

	var dead: Array = player_manager.dead_party
	var names: Array = dead.duplicate() if revive_count < 0 else dead.slice(maxi(0, dead.size() - revive_count), dead.size())

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

# Zaščiti zaveznike pred zajetjem do začetka igralčeve naslednje poteze
# (is_capture_immune - generično preverjen ob zajetju, počiščen v
# BattleController._clear_expired_evade, glej Knight.Evade za isti mehanizem).
# tier.all == true (upgraded nivo) pomeni "vsi zavezniki", sicer samo tisti
# znotraj _area_tiles(tier, grid_pos) okoli kralja.
func _do_royal_decree(tier: Dictionary) -> bool:
	var affected := false
	if tier.get("all", false):
		for character in grid_manager.get_all_characters():
			if character is BaseCharacter and not character.is_enemy and not character.is_obstacle:
				character.is_capture_immune = true
				affected = true
	else:
		for pos in _area_tiles(tier, grid_pos):
			var target = grid_manager.get_character_at(pos)
			if target is BaseCharacter and not target.is_enemy and not target.is_obstacle:
				target.is_capture_immune = true
				affected = true
	return affected
