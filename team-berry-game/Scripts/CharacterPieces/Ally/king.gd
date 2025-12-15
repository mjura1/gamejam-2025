extends BaseCharacter

func _ready():
	move_range = 12
	strName = "king"
	super._ready()

func get_move_directions() -> Array[Vector2i]:
	return [
		Vector2i( 1,  0), 
		Vector2i(-1,  0), 
		Vector2i( 0,  1), 
		Vector2i( 0, -1),
		Vector2i( 1,  1), 
		Vector2i( 1, -1),
		Vector2i(-1,  1),
		Vector2i(-1, -1),
	]
