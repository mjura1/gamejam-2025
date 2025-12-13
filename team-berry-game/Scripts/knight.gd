extends BaseCharacter

func get_valid_moves() -> Array[Vector2i]:
	return [
		grid_pos + Vector2i(1, 2),
		grid_pos + Vector2i(2, 1),
		grid_pos + Vector2i(-1, 2),
		grid_pos + Vector2i(-2, 1),
		grid_pos + Vector2i(1, -2),
		grid_pos + Vector2i(2, -1),
		grid_pos + Vector2i(-1, -2),
		grid_pos + Vector2i(-2, -1),
	]
