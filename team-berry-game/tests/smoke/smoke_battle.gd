extends SceneTree

# Boots a real run (Start -> battle) headlessly, the same way a player would
# trigger it, then lets a few frames pass so _ready()/spawn errors surface.
# battle.tscn depends on PlayerManager state that only exists after Start is
# pressed - BattleBoot replicates that setup (and completes the placement
# phase through the battle UI's own API, like the player dragging pieces).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_battle.gd --quit-after 4
# Errors are engine-level (ERROR: ... lines on stderr/stdout) - grep the output,
# see tests/run_all.sh for the known-error bookkeeping across audit phases.

var battle_instance
var reported := false

func _initialize():
	print(">>> SMOKE TEST: starting a run and loading a battle <<<")
	battle_instance = BattleBoot.boot(self)
	print(">>> SMOKE TEST: battle instanced, letting it run a few frames <<<")

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	# Placement se dokonča deferred na prvem frame-u (glej BattleBoot.boot) -
	# počakamo, da bitka dejansko pride do igralčeve poteze.
	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if battle_controller and battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN:
		reported = true
		print(">>> SMOKE TEST: battle booted through placement into PLAYER_TURN <<<")
	return false
