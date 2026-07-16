extends SceneTree

# Boots a real run (Start -> battle) headlessly, the same way a player would
# trigger it, then lets a few frames pass so _ready()/spawn errors surface.
# battle.tscn depends on PlayerManager state that only exists after Start is
# pressed, so we replicate that setup here instead of loading the scene directly.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_battle.gd --quit-after 4
# Errors are engine-level (ERROR: ... lines on stderr/stdout) - grep the output,
# see tests/run_all.sh for the known-error bookkeeping across audit phases.

func _initialize():
	print(">>> SMOKE TEST: starting a run and loading a battle <<<")
	var player_manager = root.get_node("PlayerManager")
	player_manager.setStarting()
	player_manager.resetActives()

	var battle_scene: PackedScene = load("res://Scenes/Map/battle.tscn")
	var battle_instance = battle_scene.instantiate()
	root.add_child(battle_instance)
	print(">>> SMOKE TEST: battle instanced, letting it run a few frames <<<")

func _process(_delta: float) -> bool:
	return false
