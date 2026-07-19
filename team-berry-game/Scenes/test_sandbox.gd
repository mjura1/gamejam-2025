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

	# BattleController.check_battle_end() now runs at the start of every
	# player turn (snow-freeze deaths must end the battle immediately, see
	# SNOW_REWORK_PLAN.md) - PlayerManager.enemyGone()/activeGone()
	# unconditionally return true for an EMPTY active_enemies/active_party,
	# neither of which this scene ever populates (its 3 hand-placed pieces
	# are wired directly into the .tscn, unlike a real battle.gd spawn, which
	# always sets both before initialize_battle()). Without this, the
	# sandbox now instantly ends the battle and tears down the scene the
	# moment it opens.
	if is_instance_valid(PlayerManager):
		if PlayerManager.active_enemies.is_empty():
			PlayerManager.active_enemies = ["sandbox_placeholder"]
		if PlayerManager.active_party.is_empty():
			PlayerManager.active_party = ["sandbox_placeholder"]

	if is_instance_valid(battle_controller):
		battle_controller.initialize_battle()
