extends "res://Scripts/base_character.gd"

func _ready():
	for x in range(-8, 8):
		if x == 0:
			continue
		move_offsets.append(Vector2i(x, 0))
		move_offsets.append(Vector2i(0, x))
	super._ready()
