extends SceneTree

# Post-battle summary overlay (VICTORY/DEFEAT) end-to-end smoke test. Boots
# three separate battles in sequence and drives the summary's signals
# directly (same "drive handlers directly" style as smoke_mode_select.gd):
#   Phase 0 - victory, non-boss floor: "+" badge lands on the seeded new
#             piece, rewards math is right, CONTINUE re-triggers
#             GF.return_to_map() (same map instance reused).
#   Phase 1 - victory, boss floor: CONTINUE re-triggers GF.advance_map_tier()
#             instead (tier increments, a new map instance is generated).
#   Phase 2 - defeat: Final Floor/Final Room reflect current_map_tier/
#             current_map_floor captured BEFORE reset_floor_number() ran,
#             BACK lands on the main menu with its mode-select overlay open.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_post_battle_summary.gd --quit-after 40

const PHASE_VICTORY_NORMAL := 0
const PHASE_VICTORY_BOSS := 1
const PHASE_DEFEAT := 2
const PHASE_DONE := 3

var phase := PHASE_VICTORY_NORMAL
var step := 0
var battle_instance: Node = null
var old_map_instance: Node = null
var new_main_menu: Node = null
var failed := false

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		failed = true

func _initialize():
	print(">>> SMOKE TEST: post-battle summary overlay (VICTORY/DEFEAT) <<<")
	_start_phase()

func _start_phase():
	step = 0
	battle_instance = BattleBoot.boot(self)

func _get_summary_instance() -> Node:
	var summary_layer = root.get_node_or_null("PostBattleSummaryLayer")
	if summary_layer == null or summary_layer.get_child_count() == 0:
		return null
	return summary_layer.get_child(0)

func _process(_delta: float) -> bool:
	if failed:
		print(">>> SMOKE TEST FAILED - see FAIL lines above <<<")
		return true

	match phase:
		PHASE_VICTORY_NORMAL, PHASE_VICTORY_BOSS:
			return _process_victory_phase()
		PHASE_DEFEAT:
			return _process_defeat_phase()
		PHASE_DONE:
			return false
	return false

func _process_victory_phase() -> bool:
	var player_manager = root.get_node("PlayerManager")
	var is_boss := phase == PHASE_VICTORY_BOSS

	if step == 0:
		var battle_controller = battle_instance.get_node_or_null("BattleController")
		if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
			return false # still waiting for placement to complete

		player_manager.current_map_tier = 0
		player_manager.is_boss_floor = is_boss
		player_manager.new_friendly_piece = "friendly_pawn"
		player_manager.new_enemy_piece = "enemy_pawn"

		var grid_manager = battle_instance.get_node("GridManager")
		for c in grid_manager.get_all_characters():
			if c is BaseCharacter and c.is_enemy and not c.is_obstacle:
				c.die()

		old_map_instance = root.get_node("GF").current_map_instance
		battle_controller.check_battle_end()
		step = 1
		return false

	if step == 1:
		var summary_instance = _get_summary_instance()
		if summary_instance == null:
			return false # summary overlay not up yet

		var label := "boss" if is_boss else "non-boss"

		var mine_row = summary_instance.get_node("%MineRow")
		var mine_highlighted := 0
		for icon in mine_row.get_children():
			if icon.is_highlighted:
				mine_highlighted += 1
				_check("[%s] highlighted MINE icon has the seeded piece name" % label,
					icon.piece_name == "friendly_pawn")
				_check("[%s] highlighted MINE icon shows the + badge" % label,
					icon.slot_label.text == "+")
		_check("[%s] exactly one MINE icon is highlighted (claimed guard)" % label, mine_highlighted == 1)

		var enemy_row = summary_instance.get_node("%EnemyRow")
		var enemy_highlighted := 0
		for icon in enemy_row.get_children():
			if icon.is_highlighted:
				enemy_highlighted += 1
				_check("[%s] highlighted ENEMY icon has the seeded piece name" % label,
					icon.piece_name == "enemy_pawn")
		_check("[%s] exactly one ENEMY icon is highlighted (claimed guard)" % label, enemy_highlighted == 1)

		var expected_gained: int = player_manager.UPGRADE_ITEMS_PER_BOSS_WIN if is_boss else player_manager.UPGRADE_ITEMS_PER_WIN
		var rewards_list = summary_instance.get_node("%RewardsList")
		var found_row := false
		for row in rewards_list.get_children():
			var row_children = row.get_children()
			if row_children.size() >= 2 and row_children[0].text == "UPGRADE ITEMS":
				found_row = true
				_check("[%s] rewards row shows the correct upgrade_items_gained delta" % label,
					row_children[row_children.size() - 1].text == "x%d" % expected_gained)
		_check("[%s] rewards list included an UPGRADE ITEMS row" % label, found_row)

		print(">>> SMOKE TEST: [%s] emitting continue_pressed <<<" % label)
		summary_instance.continue_pressed.emit()
		step = 2
		return false

	if step == 2:
		var gf = root.get_node("GF")
		if is_boss:
			# advance_map_tier(): tier increments and a NEW map instance
			# replaces the old one (only once it's finished initializing).
			if player_manager.current_map_tier != 1:
				return false
			if not is_instance_valid(gf.current_map_instance) or not gf.current_map_instance.is_initialized:
				return false
			_check("[boss] CONTINUE re-triggered advance_map_tier() (tier incremented)",
				player_manager.current_map_tier == 1)
			_check("[boss] CONTINUE generated a new map instance (not the old one reused)",
				gf.current_map_instance != old_map_instance)
			_check("[boss] new map instance is the current scene", current_scene == gf.current_map_instance)
		else:
			if current_scene != old_map_instance:
				return false
			_check("[non-boss] CONTINUE re-triggered return_to_map() (same map instance reused)",
				current_scene == old_map_instance)
			_check("[non-boss] tier unchanged by a non-boss win", player_manager.current_map_tier == 0)

		phase += 1
		_start_phase()
		return false

	return false

func _process_defeat_phase() -> bool:
	var player_manager = root.get_node("PlayerManager")

	if step == 0:
		var battle_controller = battle_instance.get_node_or_null("BattleController")
		if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
			return false # still waiting for placement to complete

		player_manager.current_map_tier = 2
		player_manager.current_map_floor = 5

		var grid_manager = battle_instance.get_node("GridManager")
		for c in grid_manager.get_all_characters():
			if c is BaseCharacter and not c.is_enemy and not c.is_obstacle:
				c.die()

		battle_controller.check_battle_end()
		step = 1
		return false

	if step == 1:
		var summary_instance = _get_summary_instance()
		if summary_instance == null:
			return false # summary overlay not up yet

		_check("[defeat] Final Floor shows the tier captured before reset (1-indexed)",
			summary_instance.get_node("%FinalFloorLabel").text == "Final Floor: 3")
		_check("[defeat] Final Room shows the room depth captured before reset",
			summary_instance.get_node("%FinalRoomLabel").text == "Final Room: 5")

		print(">>> SMOKE TEST: [defeat] emitting back_pressed <<<")
		summary_instance.back_pressed.emit()
		step = 2
		return false

	if step == 2:
		if current_scene == battle_instance or current_scene == null:
			return false
		if not current_scene.has_method("open_mode_select"):
			return false # not the main menu yet
		new_main_menu = current_scene
		step = 3
		return false

	if step == 3:
		# open_mode_select() is called via call_deferred - give it a frame.
		if not is_instance_valid(new_main_menu._mode_select_instance):
			return false
		_check("[defeat] BACK landed on the main menu with mode-select open",
			is_instance_valid(new_main_menu._mode_select_instance))
		phase = PHASE_DONE
		if not failed:
			print("SMOKE_POST_BATTLE_SUMMARY_OK")
		return false

	return false
