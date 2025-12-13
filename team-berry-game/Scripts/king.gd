extends "res://Scripts/base_character.gd"

func _ready():
	for x in range(-1, 2):
		for y in range(-1, 2):
			if x == 0 and y == 0:
				continue
			move_offsets.append(Vector2i(x, y))
	super._ready()
