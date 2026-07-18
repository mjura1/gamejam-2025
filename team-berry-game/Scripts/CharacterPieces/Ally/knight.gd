extends BaseCharacter

func _ready():
	# Vitez se premika le za en korak v smeri "L"
	move_range = 1
	strName = "knight"
	super._ready()

# KLJUČNA SPREMEMBA: Sedaj implementira get_move_directions()
func get_move_directions() -> Array[Vector2i]:
	return KNIGHT_OFFSETS
# calculate_valid_targets() se podeduje

# ----------------- SPOSOBNOSTI -----------------

const ABILITY_DEFS = [
	{
		"id": "evade", "name": "Evade", "needs_target": false,
		"base": {"desc": "This knight cannot be captured until your next turn."},
		"mid": {"desc": "This knight cannot be captured until your next turn."},
		"upgraded": {"desc": "This knight cannot be captured until your next turn."},
	},
	{
		"id": "reposition", "name": "Reposition", "needs_target": true,
		"base": {"desc": "Make an extra move with this knight without ending your turn."},
		"mid": {"desc": "Make an extra move with this knight without ending your turn."},
		"upgraded": {"desc": "Make an extra move with this knight without ending your turn."},
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

# Enak premik/zajetje kot try_move(), le da gre skozi ability sistem (porabi
# 1 uporabo Reposition za to bitko, ne navadnega premika).
func _do_reposition(target) -> bool:
	var target_char = grid_manager.get_character_at(target)
	if target_char and target_char.is_enemy != is_enemy:
		capture(target_char)
	else:
		execute_move(target)
	return true
