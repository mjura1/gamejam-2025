extends SceneTree

# Smoke test for the Legacy shop gating + navigation (Scenes/Menu/legacy_shop_menu.tscn):
# doesn't attempt to simulate an actual tier-2 boss clear (heavy, see
# plans/META_PROGRESSION_PLAN.md §2g) - instead forces MetaProgress.final_boss_beaten
# and drives Main Menu -> Mode Select -> Legacy button visible -> Legacy shop ->
# BACK -> Main Menu, mirroring smoke_mode_select.gd's handler-driven style.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_legacy_shop_flow.gd --quit-after 5

var forced_final_boss_beaten := false
var opened_mode_select := false
var opened_legacy_shop := false
var back_at_main_menu := false
var checked := false
var mode_select: Control = null

func _initialize():
	print(">>> SMOKE TEST: Main Menu -> Mode Select -> Legacy shop -> BACK <<<")
	var main_menu: PackedScene = load("res://Scenes/Menu/main_menu.tscn")
	var instance = main_menu.instantiate()
	root.add_child(instance)
	current_scene = instance

func _process(_delta: float) -> bool:
	if not forced_final_boss_beaten:
		# Autoload _ready()/load_progress() runs AFTER _initialize() (see
		# tests-harness memory gotcha #4) - forcing this here instead would
		# get clobbered by load_progress() on the first process frame. Also
		# use root.get_node() instead of the bare "MetaProgress" identifier -
		# a bare autoload reference in a --script entry file fails to compile
		# (gotcha #5).
		root.get_node("MetaProgress").final_boss_beaten = true
		forced_final_boss_beaten = true
		return false

	if not opened_mode_select:
		if current_scene == null or not current_scene.has_method("_on_play_pressed"):
			return false
		current_scene._on_play_pressed()
		opened_mode_select = true
		return false

	if not opened_legacy_shop:
		mode_select = current_scene._mode_select_instance
		if not is_instance_valid(mode_select):
			print(">>> SMOKE TEST FAIL: PLAY did not create a Mode Select overlay <<<")
			return true
		if not mode_select.legacy_button.visible:
			print(">>> SMOKE TEST FAIL: Legacy button should be visible when final_boss_beaten is true <<<")
			return true
		mode_select._on_legacy_pressed()
		opened_legacy_shop = true
		return false

	if not back_at_main_menu:
		if not (current_scene is Control and current_scene.name == "LegacyShopMenu"):
			return false # give _change_scene_instance a frame to land
		current_scene._on_back_pressed()
		back_at_main_menu = true
		return false

	if checked:
		return false
	checked = true

	if not (current_scene is Control and current_scene.has_method("_on_play_pressed")):
		print(">>> SMOKE TEST FAIL: BACK from Legacy shop did not return to Main Menu <<<")
		return true

	print("SMOKE_LEGACY_SHOP_FLOW_OK")
	return false
