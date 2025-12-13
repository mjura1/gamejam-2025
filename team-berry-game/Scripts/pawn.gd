extends "res://Scripts/base_character.gd"

func _ready():
	super._ready() 

func get_valid_moves() -> Array[Vector2i]:
	var moves: Array[Vector2i] = []

	for x in range(-2, 3):
		for y in range(-2, 3):
			if x == 0 and y == 0:
				continue
			var target := grid_pos + Vector2i(x, y)
			if grid_manager.is_occupied(target):
				continue  # optional: block moves past other units
			moves.append(target)

	return moves
