# res://Scenes/test_sandbox.gd
# Root script for the dev/test sandbox scene. Unlike the live battle.tscn
# (whose battle.gd spawns pieces from the player's roster, then registers
# them and starts the battle), this scene's pieces are pre-placed by hand
# directly in the .tscn - nothing was ever wired to actually register them
# on the grid or start the turn loop. This just does that part.
extends Node

@onready var grid_manager = $GridManager
@onready var battle_controller = $BattleController

func _ready() -> void:
	if is_instance_valid(grid_manager):
		grid_manager.register_all_characters_in_scene()

	if is_instance_valid(battle_controller):
		battle_controller.initialize_battle()
