extends BaseCharacter

func _ready():
	move_range = 8
	strName = "queen"
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

# Item "mounted_hunters": igralčeva kraljica se lahko premakne/zajme tudi kot
# vitez (pravi skoki, ne drsenje - is_enemy vrata pomembna, ker sovražnikova
# kraljica deli isto skripto, glej §0 gotcha v SHOP_V2_PLAN.md).
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
		"id": "exterminate", "name": "Exterminate", "needs_target": false,
		"base": {"shape": "square", "radius": 1, "desc": "Arms this queen. The next move made by any piece triggers a blast that destroys all enemies within 3x3 of her."},
		"mid": {"shape": "plus", "desc": "Arms this queen. The next move made by any piece triggers a blast that destroys all enemies within a 3x3 + cross-shaped area of her."},
		"upgraded": {"shape": "square", "radius": 2, "desc": "Arms this queen. The next move made by any piece triggers a blast that destroys all enemies within 5x5 of her."},
	},
	{
		"id": "lure", "name": "Lure", "needs_target": false,
		"base": {"enemy_count": 1, "desc": "Forces the closest enemy to move toward this queen on their next move, but they cannot capture her."},
		"mid": {"enemy_count": 3, "desc": "Forces the 3 closest enemies to move toward this queen on their next move, but they cannot capture her."},
		"upgraded": {"enemy_count": -1, "desc": "Every enemy is forced to move toward this queen on their next move, but cannot capture her."},
	},
	{
		"id": "command", "name": "Command", "needs_target": true,
		"base": {"los": true, "desc": "A chosen ally in this queen's line of sight may immediately make a free move."},
		"mid": {"los": false, "desc": "Any chosen ally may immediately make a free move."},
		"upgraded": {"los": false, "desc": "Any chosen ally may immediately make a free move."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func get_ability_targets(slot: int) -> Array[Vector2i]:
	if slot == 3:
		return _command_targets(_tier_data(3))
	return []

func _command_targets(tier: Dictionary) -> Array[Vector2i]:
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
		targets.append(ally.grid_pos)
	return targets

func _execute_ability(id: String, target) -> bool:
	match id:
		"exterminate":
			return _do_exterminate(_tier_data(1))
		"lure":
			return _do_lure(_tier_data(2).get("enemy_count", -1))
		"command":
			return _do_command(target)
	return false

func _do_exterminate(tier: Dictionary) -> bool:
	if not is_instance_valid(battle_controller):
		return false
	battle_controller.exterminate_armed = {
		"tiles": _area_tiles(tier, grid_pos),
		"owner": self,
		"owner_is_enemy": is_enemy,
	}
	return true

# Prisili najbližjih "enemy_count" sovražnikov, da gredo proti tej kraljici
# (glej base_character._lured_move). enemy_count < 0 pomeni "vse".
func _do_lure(enemy_count: int) -> bool:
	if not is_instance_valid(battle_controller):
		return false

	var enemies: Array[BaseCharacter] = []
	for character in grid_manager.get_all_characters():
		if is_instance_valid(character) and character is BaseCharacter and character.is_enemy != is_enemy and not character.is_obstacle:
			enemies.append(character)

	if enemies.is_empty():
		return false

	enemies.sort_custom(func(a, b): return grid_pos.distance_to(a.grid_pos) < grid_pos.distance_to(b.grid_pos))
	var chosen: Array[BaseCharacter] = enemies if enemy_count < 0 else enemies.slice(0, enemy_count)

	battle_controller.lured_enemies = chosen
	battle_controller.lure_source = self
	return true

# Podeli tarčnemu zavezniku brezplačen premik za TO potezo - naslednjič, ko se
# ta zaveznik premakne/zajame, map_behaviour.gd's consume_move_for() (glej
# BattleController.free_move_character) preskoči porabo proračuna premikov.
# NAMERNO ne mirroring Reposition (glej SKILL_TREE_PLAN.md §4.5 popravek): ne
# premakne nikogar sama, samo označi, kdo dobi brezplačen premik.
func _do_command(target: Vector2i) -> bool:
	if not is_instance_valid(battle_controller):
		return false
	var ally = grid_manager.get_character_at(target)
	if not (ally is BaseCharacter) or ally.is_enemy != is_enemy or ally == self:
		return false
	battle_controller.free_move_character = ally
	return true
