extends Node2D

@onready var tile_selector = get_node("/root/Node/TileSelector")
@onready var grid_manager = get_node("/root/Node/GridManager")
@onready var tile_map = get_node("/root/Node/Map/TileMapLayer")

var selected_character: Node = null  # currently selected character

func _unhandled_input(event):
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var clicked_grid = grid_manager.world_to_grid(get_global_mouse_position())
	var used_rect = tile_map.get_used_rect()

	tile_selector.select_tile(clicked_grid)
	
	print(grid_manager.is_occupied(clicked_grid))
	
	var clicked_character = grid_manager.get_character_at(clicked_grid)

	# CLICK ON CHARACTER
	if clicked_character:
		# Clicking the same character → deselect
		if selected_character == clicked_character:
			selected_character.selected = false
			selected_character = null
			return

		# Switching characters
		if selected_character:
			selected_character.selected = false

		selected_character = clicked_character
		selected_character.selected = true
		return


	# CLICK ON EMPTY TILE → MOVE
	if selected_character and grid_manager.is_inside_boundary(clicked_grid, used_rect):
		if selected_character.try_move(clicked_grid):
			selected_character.selected = false
			selected_character = null
