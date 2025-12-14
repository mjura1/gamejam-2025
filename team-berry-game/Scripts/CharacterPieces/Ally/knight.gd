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
