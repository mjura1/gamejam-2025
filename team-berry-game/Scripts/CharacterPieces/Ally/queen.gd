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
		"base": {"uses": 1, "radius": 1, "desc": "Arms this queen. The next move made by any piece triggers a blast that destroys all enemies within 3x3 of her."},
		"upgraded": {"uses": 1, "radius": 2, "desc": "Arms this queen. The next move made by any piece triggers a blast that destroys all enemies within 5x5 of her."},
	},
	{
		"id": "lure", "name": "Lure", "needs_target": false,
		"base": {"uses": 1, "desc": "Every enemy is forced to move toward this queen on their next move, but cannot capture her."},
		"upgraded": {"uses": 2, "desc": "Every enemy is forced to move toward this queen on their next move, but cannot capture her."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func _execute_ability(id: String, _target) -> bool:
	match id:
		"exterminate":
			return _do_exterminate(_tier_data(1).get("radius", 1))
		"lure":
			return _do_lure()
	return false

func _do_exterminate(radius: int) -> bool:
	if not is_instance_valid(battle_controller):
		return false
	battle_controller.exterminate_armed = {
		"center": grid_pos,
		"radius": radius,
		"owner": self,
		"owner_is_enemy": is_enemy,
	}
	return true

func _do_lure() -> bool:
	if not is_instance_valid(battle_controller):
		return false

	var enemies: Array[BaseCharacter] = []
	for character in grid_manager.get_all_characters():
		if is_instance_valid(character) and character is BaseCharacter and character.is_enemy != is_enemy and not character.is_obstacle:
			enemies.append(character)

	if enemies.is_empty():
		return false

	battle_controller.lured_enemies = enemies
	battle_controller.lure_source = self
	return true
