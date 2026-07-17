extends BaseCharacter

func _ready():
	# Vitez se premika le za en korak v smeri "L"
	move_range = 1
	strName = "knight"
	super._ready()

# KLJUČNA SPREMEMBA: Sedaj implementira get_move_directions()
func get_move_directions() -> Array[Vector2i]:
	return [
		Vector2i(1, 2),
		Vector2i(2, 1),
		Vector2i(-1, 2),
		Vector2i(-2, 1),
		Vector2i(1, -2),
		Vector2i(2, -1),
		Vector2i(-1, -2),
		Vector2i(-2, -1),
	]
# calculate_valid_targets() se podeduje

# ----------------- SPOSOBNOSTI -----------------

const ABILITY_DEFS = [
	{
		"id": "evade", "name": "Evade", "needs_target": false, "ends_turn": true,
		"base": {"uses": 2, "desc": "This knight cannot be captured until your next turn."},
		"upgraded": {"uses": 3, "desc": "This knight cannot be captured until your next turn."},
	},
	{
		"id": "reposition", "name": "Reposition", "needs_target": true, "ends_turn": false,
		"base": {"uses": 1, "desc": "Make an extra move with this knight without ending your turn."},
		"upgraded": {"uses": 2, "desc": "Make an extra move with this knight without ending your turn."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func get_ability_targets(slot: int) -> Array[Vector2i]:
	if slot == 2:
		return calculate_valid_targets()
	return []

func _execute_ability(id: String, target) -> bool:
	match id:
		"evade":
			is_capture_immune = true
			return true
		"reposition":
			return _do_reposition(target)
	return false

# Enak premik/zajetje kot try_move(), a brez END TURN posledic - to
# ureja map_behaviour._resolve_pending_ability glede na ends_turn=false.
func _do_reposition(target) -> bool:
	var target_char = grid_manager.get_character_at(target)
	if target_char and target_char.is_enemy != is_enemy:
		capture(target_char)
	else:
		execute_move(target)
	return true
