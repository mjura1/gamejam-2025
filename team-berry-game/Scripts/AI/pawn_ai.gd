extends "res://Scripts/base_character.gd"

func _ready():
	super._ready()

func take_turn(friendly_units: Array[Node]):
	if friendly_units.size() == 0:
		return

	var closest: Node = null
	var min_dist := 9999.0
	for f in friendly_units:
		var dist := grid_pos.distance_to(f.grid_pos)
		if dist < min_dist:
			min_dist = dist
			closest = f

	if closest == null:
		return

	var best_move: Vector2i
	var best_dist := min_dist

	for target in get_valid_moves():
		var d := target.distance_to(closest.grid_pos)
		if d < best_dist:
			best_dist = d
			best_move = target

	if best_move != null:
		try_move(best_move)
