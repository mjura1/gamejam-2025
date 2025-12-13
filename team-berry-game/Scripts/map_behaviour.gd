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
		
		# Highlight the clicked tile
		tile_selector.select_tile(clicked_grid)
		
		if selected_character:
			# Move the selected character if the tile is empty
			if not grid_manager.is_occupied(clicked_grid) and grid_manager.is_inside_boundary(clicked_grid, used_rect):
				
				if selected_character.try_move(clicked_grid):
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
