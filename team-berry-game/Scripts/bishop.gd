extends "res://Scripts/base_character.gd"

func _ready():
	for x in range(1, 8):
		if x == 0:
			continue
		move_offsets.append(Vector2i(x, x))
		move_offsets.append(Vector2i(x, -x))
		move_offsets.append(Vector2i(-x, x))
		move_offsets.append(Vector2i(-x, -x))
	super._ready()
