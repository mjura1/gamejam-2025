extends SceneTree

# Regression test: GF._initialize_game() sets MapController.pending_tier
# synchronously right after instantiate() (before the node is added to the
# tree), then relies on _ready() to call initialize_map(pending_tier). This
# is the ONLY test that drives the real "Start" button flow end to end -
# BattleBoot.boot() (used by the other smoke tests) deliberately bypasses
# GF._initialize_game(). It's what a manual playtest caught but no automated
# test did: initialize_map() used to be called directly before add_child(),
# while it still needed an @onready var (map_camera) that isn't populated
# until the node is actually inside the tree - a Nil-object crash in
# _center_and_zoom_camera() that no other smoke test surfaced.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_start_new_game.gd --quit-after 5

var pressed := false
var checked := false

func _initialize():
	print(">>> SMOKE TEST: main menu Start -> GameFlow._initialize_game() <<<")
	var main_menu: PackedScene = load("res://Scenes/Menu/main_menu.tscn")
	var instance = main_menu.instantiate()
	root.add_child(instance)
	current_scene = instance

func _process(_delta: float) -> bool:
	if not pressed:
		if current_scene != null and current_scene.has_method("_on_start_pressed"):
			current_scene._on_start_pressed()
			pressed = true
		return false

	if checked:
		return false

	var gf = root.get_node_or_null("GF")
	if gf == null or not is_instance_valid(gf.current_map_instance):
		return false # still waiting for the deferred _initialize_game()

	var map_instance = gf.current_map_instance
	if not map_instance.is_initialized:
		return false # waiting for MapController._ready() -> initialize_map()

	checked = true
	var player_manager = root.get_node("PlayerManager")
	print(">>> SMOKE TEST: map initialized cleanly via the real Start flow (tier %d, %d floors) <<<" % [player_manager.current_map_tier, map_instance.generator.FLOORS])
	return false
