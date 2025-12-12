# In World.tscn script
extends Node2D

@onready var tile_selector = get_node("/root/Node/TileSelector")
@onready var grid_manager = get_node("/root/Node/GridManager")
var selected_character: Node = null
 
func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		var clicked_grid = grid_manager.world_to_grid(mouse_pos)

		# Check if a character is selected
		if selected_character:
			# Move the selected character
			if not grid_manager.is_occupied(clicked_grid):
				# Vacate old grid
				grid_manager.vacate(selected_character.grid_pos)
				# Update grid position
				selected_character.grid_pos = clicked_grid
				grid_manager.occupy(clicked_grid, selected_character)
				selected_character.global_position = grid_manager.grid_to_world(clicked_grid)
				
				# Deselect after moving
				selected_character.selected = false
				selected_character = null
		else:
			# Check if a character exists at this tile
			var occupant = grid_manager.occupied.get(clicked_grid, null)
			if occupant and occupant.has_method("selected"):
				selected_character = occupant
				occupant.selected = true
				print("Character selected at ", clicked_grid)
