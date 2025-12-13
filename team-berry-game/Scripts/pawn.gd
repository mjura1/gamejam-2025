extends "res://Scripts/base_character.gd"

func _ready():
	for x in range(-2, 3):
		for y in range(-2, 3):
			if x == 0 and y == 0:
				continue
			move_offsets.append(Vector2i(x, y))
	super._ready()
