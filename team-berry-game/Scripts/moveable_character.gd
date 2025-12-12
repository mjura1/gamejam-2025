extends "res://Scripts/base_character.gd"

var selected: bool = false

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected = true
		print("Character selected at ", grid_pos)
