extends SceneTree

# Regression test: GF._initialize_game() sets MapController.pending_tier
# synchronously right after instantiate() (before the node is added to the
# tree), then relies on _ready() to call initialize_map(pending_tier). This
# is the ONLY test that drives the real button-press flow end to end -
# BattleBoot.boot() (used by the other smoke tests) deliberately bypasses
# GF._initialize_game(). It's what a manual playtest caught but no automated
# test did: initialize_map() used to be called directly before add_child(),
# while it still needed an @onready var (map_camera) that isn't populated
# until the node is actually inside the tree - a Nil-object crash in
# _center_and_zoom_camera() that no other smoke test surfaced.
# Since the Mode Select screen landed, "start a game" is two presses:
# PLAY opens the Mode Select overlay (main_menu._mode_select_instance),
# CLASSIC on that overlay is what actually calls setStarting() +
# GF.start_new_game() - so this test drives both, same as a real player.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_start_new_game.gd --quit-after 5

var opened := false
var pressed := false
var checked := false

func _initialize():
	print(">>> SMOKE TEST: main menu Play -> Mode Select CLASSIC -> GameFlow._initialize_game() <<<")
	var main_menu: PackedScene = load("res://Scenes/Menu/main_menu.tscn")
	var instance = main_menu.instantiate()
	root.add_child(instance)
	current_scene = instance

func _process(_delta: float) -> bool:
	if not opened:
		if current_scene != null and current_scene.has_method("_on_play_pressed"):
			current_scene._on_play_pressed()
			opened = true
		return false

	if not pressed:
		# _on_play_pressed() instanced the overlay synchronously via add_child.
		var overlay = current_scene._mode_select_instance
		if not is_instance_valid(overlay):
			return false # keep waiting; --quit-after fails the test if it never shows
		overlay._on_classic_pressed()
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
	print(">>> SMOKE TEST: map initialized cleanly via the real Start flow (tier %d, %d floors, mode %s) <<<" % [player_manager.current_map_tier, map_instance.generator.FLOORS, player_manager.game_mode])
	return false
