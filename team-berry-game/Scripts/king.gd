extends "res://Scripts/base_character.gd"

var selected: bool = false

func _ready():
	for x in range(-1, 2):
		for y in range(-1, 2):
			if x == 0 and y == 0:
				continue
			move_offsets.append(Vector2i(x, y))
	super._ready()

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected = true
