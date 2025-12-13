extends "res://Scripts/base_character.gd"

var selected: bool = false

func _ready():
	move_offsets = [
		Vector2i( 1,  2),
		Vector2i( 2,  1),
		Vector2i(-1,  2),
		Vector2i(-2,  1),
		Vector2i( 1, -2),
		Vector2i( 2, -1),
		Vector2i(-1, -2),
		Vector2i(-2, -1),
	]	
	super._ready()

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected = true
