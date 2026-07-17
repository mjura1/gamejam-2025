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
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func _execute_ability(id: String, _target) -> bool:
	match id:
		"exterminate":
			return _do_exterminate(_tier_data(1))
		"lure":
			return _do_lure(_tier_data(2).get("enemy_count", -1))
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
