extends TestCase

# Testi za plans/META_PROGRESSION_PLAN.md - MetaUpgradeData.calculate_battle_points
# (čista funkcija), MetaProgress.can_buy_upgrade/try_buy_upgrade (zrcali
# PlayerManager.can_buy_node/try_buy_node - glej test_skill_tree.gd) in
# PlayerManager._apply_meta_upgrades()/setStarting() reset-then-reapply.

const PlayerManagerScript = preload("res://Scripts/Player/PlayerManager.gd")

# ----------------- MetaUpgradeData.calculate_battle_points -----------------

func test_base_case_matches_base_points_per_battle():
	var points := MetaUpgradeData.calculate_battle_points(0, 0, 999, false, true)
	assert_eq(points, 100, "depth 0, no enemies, slow win, not flawless, post-clear should equal base_points_per_battle")

func test_flawless_applies_multiplier():
	var base := MetaUpgradeData.calculate_battle_points(0, 0, 999, false, true)
	var flawless := MetaUpgradeData.calculate_battle_points(0, 0, 999, true, true)
	assert_eq(flawless, int(base * 1.5), "flawless should multiply by flawless_multiplier (1.5)")

func test_depth_and_enemy_count_add_linearly():
	var base := MetaUpgradeData.calculate_battle_points(0, 0, 999, false, true)
	var with_depth := MetaUpgradeData.calculate_battle_points(3, 0, 999, false, true)
	assert_eq(with_depth, base + 3 * 10, "depth should add points_per_floor_depth per floor")
	var with_enemies := MetaUpgradeData.calculate_battle_points(0, 4, 999, false, true)
	assert_eq(with_enemies, base + 4 * 15, "enemy_count should add points_per_enemy per enemy")

func test_fast_win_adds_speed_bonus_up_to_cap():
	var slow := MetaUpgradeData.calculate_battle_points(0, 0, 20, false, true)
	var fast := MetaUpgradeData.calculate_battle_points(0, 0, 10, false, true)
	assert_eq(slow, 100, "turns == fast_win_turn_cap should add no speed bonus")
	assert_eq(fast, 100 + 10 * 2, "fewer turns than the cap should add fast_win_points_per_turn per turn saved")

func test_pre_clear_scale_applied_when_final_boss_not_beaten():
	var pre := MetaUpgradeData.calculate_battle_points(0, 0, 999, false, false)
	var post := MetaUpgradeData.calculate_battle_points(0, 0, 999, false, true)
	assert_eq(pre, int(100 * 0.15), "pre-clear scale should apply when final_boss_beaten is false")
	assert_eq(post, 100, "post-clear scale (1.0) should apply when final_boss_beaten is true")

# ----------------- MetaProgress.can_buy_upgrade/try_buy_upgrade -----------------
# NOTE: MetaProgress is the real autoload singleton (simple Dictionary/int
# state, no scene-tree dependency - same reasoning as calling SkillTreeData
# directly in test_skill_tree.gd). Each test resets the fields it touches so
# tests don't leak state into each other via the shared autoload instance.
# Upgrades are leveled/repeatable (glej MetaUpgradeData.get_cost_for_level/
# get_max_level in GameParameters/meta_upgrade_levels.json) - -1 max_level
# pomeni "infinite" (nikoli maxed).

func _reset_meta_progress():
	MetaProgress.legacy_points = 0
	MetaProgress.upgrade_levels = {}
	MetaProgress.final_boss_beaten = false

func test_cannot_buy_upgrade_without_enough_points():
	_reset_meta_progress()
	MetaProgress.legacy_points = 100
	assert_false(MetaProgress.try_buy_upgrade("starting_pawn"), "starting_pawn level 1 costs 300, should fail with 100 points")
	assert_eq(MetaProgress.legacy_points, 100, "a failed buy should not spend points")

func test_cannot_buy_upgrade_without_requirements():
	_reset_meta_progress()
	MetaProgress.legacy_points = 10000
	assert_false(MetaProgress.try_buy_upgrade("starting_rook"), "starting_rook requires starting_pawn first")

func test_buy_upgrade_spends_cost_and_marks_unlocked():
	_reset_meta_progress()
	MetaProgress.legacy_points = 300
	assert_true(MetaProgress.try_buy_upgrade("starting_pawn"), "buy should succeed with exactly enough points")
	assert_eq(MetaProgress.legacy_points, 0, "buy should spend exactly the upgrade cost")
	assert_true(MetaProgress.has_upgrade("starting_pawn"), "bought upgrade should be marked unlocked")
	assert_eq(MetaProgress.get_upgrade_level("starting_pawn"), 1, "first buy should set level to 1")

func test_repeat_buy_raises_level_and_cost():
	_reset_meta_progress()
	MetaProgress.legacy_points = 100000
	var cost_at_level_0 := MetaUpgradeData.get_cost_for_level("extra_coin_1", 0)
	assert_true(MetaProgress.try_buy_upgrade("extra_coin_1"), "first buy should succeed")
	assert_eq(MetaProgress.get_upgrade_level("extra_coin_1"), 1, "level should be 1 after first buy")
	var cost_at_level_1 := MetaUpgradeData.get_cost_for_level("extra_coin_1", 1)
	assert_true(cost_at_level_1 > cost_at_level_0, "cost for the next level should be higher than the previous one")
	assert_true(MetaProgress.try_buy_upgrade("extra_coin_1"), "second buy should also succeed (not one-time)")
	assert_eq(MetaProgress.get_upgrade_level("extra_coin_1"), 2, "level should be 2 after second buy")

func test_upgrade_maxes_out_at_max_level():
	_reset_meta_progress()
	MetaProgress.legacy_points = 100000
	assert_true(MetaProgress.try_buy_upgrade("starting_pawn"), "prerequisite buy should succeed")
	assert_true(MetaProgress.try_buy_upgrade("starting_rook"), "first starting_rook buy should succeed")
	assert_true(MetaProgress.try_buy_upgrade("starting_rook"), "second starting_rook buy should reach its max_level (2)")
	assert_true(MetaProgress.is_upgrade_maxed("starting_rook"), "starting_rook should report maxed at level 2")
	var points_at_max := MetaProgress.legacy_points
	assert_false(MetaProgress.try_buy_upgrade("starting_rook"), "buying past max_level should fail")
	assert_eq(MetaProgress.legacy_points, points_at_max, "a failed buy at max_level should not spend points")
	assert_eq(MetaProgress.get_upgrade_level("starting_rook"), 2, "level should stay at max_level after the failed buy")

func test_infinite_upgrade_never_maxes():
	_reset_meta_progress()
	MetaProgress.legacy_points = 1000000
	for i in range(5):
		assert_true(MetaProgress.try_buy_upgrade("extra_coin_1"), "infinite upgrade (max_level -1) should stay purchasable")
	assert_eq(MetaProgress.get_upgrade_level("extra_coin_1"), 5, "level should equal the number of successful buys")
	assert_false(MetaProgress.is_upgrade_maxed("extra_coin_1"), "an infinite upgrade should never report maxed")

func test_requirement_unlocks_after_prerequisite_bought():
	_reset_meta_progress()
	MetaProgress.legacy_points = 10000
	assert_true(MetaProgress.try_buy_upgrade("starting_pawn"), "prerequisite buy should succeed")
	assert_true(MetaProgress.try_buy_upgrade("starting_rook"), "starting_rook should unlock once starting_pawn is owned")

func test_unknown_upgrade_id_fails():
	_reset_meta_progress()
	MetaProgress.legacy_points = 10000
	assert_false(MetaProgress.try_buy_upgrade("not_a_real_upgrade"), "buying an unknown id should fail")

# ----------------- PlayerManager._apply_meta_upgrades / setStarting reset -----------------

func test_setStarting_applies_unlocked_moves_per_turn_bonus():
	_reset_meta_progress()
	MetaProgress.upgrade_levels = {"extra_move_1": 1}
	var pm = PlayerManagerScript.new()
	pm.setStarting("classic")
	assert_eq(pm.moves_per_turn, 2, "extra_move_1 at level 1 should grant +1 moves_per_turn on the next run")
	_reset_meta_progress()

func test_setStarting_scales_bonus_with_upgrade_level():
	_reset_meta_progress()
	MetaProgress.upgrade_levels = {"extra_move_1": 3}
	var pm = PlayerManagerScript.new()
	pm.setStarting("classic")
	assert_eq(pm.moves_per_turn, 4, "extra_move_1 at level 3 should grant +3 moves_per_turn (amount * level)")
	_reset_meta_progress()

func test_setStarting_does_not_compound_bonus_across_calls():
	_reset_meta_progress()
	MetaProgress.upgrade_levels = {"extra_move_1": 1}
	var pm = PlayerManagerScript.new()
	pm.setStarting("classic")
	pm.setStarting("classic")
	assert_eq(pm.moves_per_turn, 2, "calling setStarting() twice in a row should not compound the bonus to 3")
	_reset_meta_progress()

func test_setStarting_with_no_unlocks_matches_base_values():
	_reset_meta_progress()
	var pm = PlayerManagerScript.new()
	pm.setStarting("classic")
	assert_eq(pm.moves_per_turn, PlayerManagerScript.BASE_MOVES_PER_TURN, "no unlocks should leave moves_per_turn at base")
	assert_eq(pm.abilities_per_turn, PlayerManagerScript.BASE_ABILITIES_PER_TURN, "no unlocks should leave abilities_per_turn at base")
	assert_eq(pm.base_luck, 0, "no unlocks should leave base_luck at 0")
	assert_eq(pm.get_luck(), 0, "get_luck() should reflect base_luck")
