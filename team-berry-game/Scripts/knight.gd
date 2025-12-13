extends "res://Scripts/base_character.gd"

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
