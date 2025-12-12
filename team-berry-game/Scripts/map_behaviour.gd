extends Node2D

@onready var tile_selector = get_node("/root/Node/TileSelector")
@onready var grid_manager = get_node("/root/Node/GridManager")
@onready var tile_map = get_node("/root/Node/Map/TileMapLayer")

var selected_character: Node = null  # currently selected character

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		var clicked_grid = grid_manager.world_to_grid(mouse_pos)
		var used_rect = tile_map.get_used_rect()
		
		var used_rect_x_min = used_rect.position.x
		var used_rect_y_min = used_rect.position.y
		var used_rect_x_max = used_rect.size.x
		var used_rect_y_max = used_rect.size.y
		
		# Highlight the clicked tile
		tile_selector.select_tile(clicked_grid)
		
		if selected_character:
			# Move the selected character if the tile is empty
			if not grid_manager.is_occupied(clicked_grid) and clicked_grid.x >= used_rect_x_min and clicked_grid.x <= used_rect_x_max and clicked_grid.y >= used_rect_y_min and clicked_grid.y <= used_rect_y_max:
				
				# Vacate old tile
				grid_manager.vacate(selected_character.grid_pos)
				# Update grid position
				selected_character.grid_pos = clicked_grid
				grid_manager.occupy(clicked_grid, selected_character)
				# Move the character visually
				selected_character.global_position = grid_manager.grid_to_world(clicked_grid)
				
				# Deselect after moving
				selected_character.selected = false
				selected_character = null
			else:
				# If clicked another character, switch selection
				var occupant = grid_manager.occupied.get(clicked_grid, null)
				if occupant:
					if selected_character != occupant:
						selected_character.selected = false
						selected_character = occupant
						occupant.selected = true
						print("Character selected at ", clicked_grid)
		else:
			# No character selected yet, select one if it exists
			var occupant = grid_manager.occupied.get(clicked_grid, null)
			if occupant:
				selected_character = occupant
				occupant.selected = true
				print("Character selected at ", clicked_grid)
