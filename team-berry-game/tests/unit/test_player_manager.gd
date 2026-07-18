extends TestCase

const PlayerManagerScript = preload("res://Scripts/Player/PlayerManager.gd")

func test_active_gone_true_when_empty():
	var pm = PlayerManagerScript.new()
	var empty: Array[String] = []
	pm.active_party = empty
	assert_true(pm.activeGone(), "activeGone() should be true when active_party is empty")

func test_active_gone_false_when_not_empty():
	var pm = PlayerManagerScript.new()
	var party: Array[String] = ["friendly_pawn"]
	pm.active_party = party
	assert_false(pm.activeGone(), "activeGone() should be false when active_party has entries")

func test_enemy_gone_true_when_empty():
	var pm = PlayerManagerScript.new()
	var empty: Array[String] = []
	pm.active_enemies = empty
	assert_true(pm.enemyGone(), "enemyGone() should be true when active_enemies is empty")

func test_enemy_gone_false_when_not_empty():
	var pm = PlayerManagerScript.new()
	var enemies: Array[String] = ["enemy_pawn"]
	pm.active_enemies = enemies
	assert_false(pm.enemyGone(), "enemyGone() should be false when active_enemies has entries")

func test_reset_actives_copies_persistent_rosters():
	var pm = PlayerManagerScript.new()
	var friendly: Array[String] = ["friendly_pawn", "friendly_rook"]
	var enemy: Array[String] = ["enemy_pawn"]
	pm.friendly_party = friendly
	pm.enemy_party = enemy
	pm.resetActives()
	assert_eq(pm.active_party, ["friendly_pawn", "friendly_rook"], "resetActives() should copy friendly_party into active_party")
	assert_eq(pm.active_enemies, ["enemy_pawn"], "resetActives() should copy enemy_party into active_enemies")

func test_set_current_floor_raises_to_new_value():
	var pm = PlayerManagerScript.new()
	pm.current_map_floor = 0
	pm.set_current_floor(3)
	assert_eq(pm.current_map_floor, 3, "set_current_floor should raise current_map_floor to the passed-in value")

func test_set_current_floor_never_lowers():
	var pm = PlayerManagerScript.new()
	pm.current_map_floor = 5
	pm.set_current_floor(2)
	assert_eq(pm.current_map_floor, 5, "set_current_floor should not lower current_map_floor when given a smaller value")

func test_set_current_floor_equal_value_is_noop():
	var pm = PlayerManagerScript.new()
	pm.current_map_floor = 4
	pm.set_current_floor(4)
	assert_eq(pm.current_map_floor, 4, "set_current_floor should leave current_map_floor unchanged when given the same value")

func test_add_to_enemy_party_grows_as_player_goes_deeper():
	var pm = PlayerManagerScript.new()
	pm.setStarting()
	var expected: Array[String] = pm.default_enemies.duplicate()
	expected.append("enemy_knight")
	expected.append("enemy_rook")
	pm.add_to_enemy_party("enemy_knight")
	pm.add_to_enemy_party("enemy_rook")
	assert_eq(pm.enemy_party, expected, "add_to_enemy_party should accumulate across floors within the same map (on top of the run's starting roster), not reset per battle")

func test_add_to_friendly_party_fills_active_roster_first():
	var pm = PlayerManagerScript.new()
	pm.max_party_size = 2
	pm.add_to_friendly_party("friendly_pawn")
	pm.add_to_friendly_party("friendly_rook")
	assert_eq(pm.friendly_party, ["friendly_pawn", "friendly_rook"], "add_to_friendly_party should fill the active roster up to max_party_size")
	assert_eq(pm.reserve_party, [], "reserve_party should stay empty while the active roster has room")

func test_add_to_friendly_party_overflows_into_reserve_instead_of_dropping():
	var pm = PlayerManagerScript.new()
	pm.max_party_size = 2
	pm.add_to_friendly_party("friendly_pawn")
	pm.add_to_friendly_party("friendly_rook")
	pm.add_to_friendly_party("friendly_bishop")
	assert_eq(pm.friendly_party, ["friendly_pawn", "friendly_rook"], "a full active roster should not grow past max_party_size")
	assert_eq(pm.reserve_party, ["friendly_bishop"], "a piece collected once the active roster is full should be kept in reserve_party, not lost")

# ----------------- upgrade itemi in nadgradnje po tipu figure -----------------

func test_get_piece_upgrades_defaults_to_level_1_locked_slot2():
	var pm = PlayerManagerScript.new()
	var up = pm.get_piece_upgrades("pawn")
	assert_false(up["slot2_unlocked"], "a fresh piece type should start with ability slot 2 locked")
	assert_eq(up["levels"][1], 1, "a fresh piece type should start with ability 1 at level 1")
	assert_eq(up["levels"][2], 1, "a fresh piece type should start with ability 2 at level 1")

func test_add_upgrade_items_accumulates():
	var pm = PlayerManagerScript.new()
	pm.add_upgrade_items(2)
	pm.add_upgrade_items(3)
	assert_eq(pm.upgrade_items, 5, "add_upgrade_items should accumulate across battles/rooms")

func test_try_level_up_spends_items_and_raises_level():
	var pm = PlayerManagerScript.new()
	pm.add_upgrade_items(5)
	assert_true(pm.try_level_up_ability("pawn", 1, 2), "level up should succeed with enough items")
	assert_eq(pm.upgrade_items, 3, "level up should spend exactly the passed cost")
	assert_eq(pm.get_piece_upgrades("pawn")["levels"][1], 2, "level up should raise the slot's level by 1")

func test_try_level_up_fails_without_enough_items():
	var pm = PlayerManagerScript.new()
	pm.add_upgrade_items(1)
	assert_false(pm.try_level_up_ability("pawn", 1, 2), "level up should fail when items < cost")
	assert_eq(pm.upgrade_items, 1, "a failed level up should not spend any items")
	assert_eq(pm.get_piece_upgrades("pawn")["levels"][1], 1, "a failed level up should not change the level")

func test_try_level_up_caps_at_max_level():
	var pm = PlayerManagerScript.new()
	pm.add_upgrade_items(100)
	assert_true(pm.try_level_up_ability("pawn", 1, 2), "level up 1 -> 2 should succeed")
	assert_true(pm.try_level_up_ability("pawn", 1, 2), "level up 2 -> 3 should succeed")
	assert_false(pm.try_level_up_ability("pawn", 1, 2), "level up past ABILITY_LEVEL_MAX should fail")
	assert_eq(pm.get_piece_upgrades("pawn")["levels"][1], BaseCharacter.ABILITY_LEVEL_MAX, "level should cap at ABILITY_LEVEL_MAX")
	assert_eq(pm.upgrade_items, 96, "the capped attempt should not spend items")

func test_try_level_up_slot2_requires_unlock_first():
	var pm = PlayerManagerScript.new()
	pm.add_upgrade_items(10)
	assert_false(pm.try_level_up_ability("pawn", 2, 2), "slot 2 must be unlocked before it can be leveled")
	assert_true(pm.try_unlock_slot2("pawn", 1), "unlock should succeed with enough items")
	assert_eq(pm.upgrade_items, 9, "unlock should spend the unlock cost")
	assert_true(pm.try_level_up_ability("pawn", 2, 2), "slot 2 should be levelable once unlocked")

func test_try_unlock_slot2_fails_when_poor_or_already_unlocked():
	var pm = PlayerManagerScript.new()
	assert_false(pm.try_unlock_slot2("pawn", 1), "unlock should fail with 0 items")
	pm.add_upgrade_items(2)
	assert_true(pm.try_unlock_slot2("pawn", 1), "unlock should succeed with enough items")
	assert_false(pm.try_unlock_slot2("pawn", 1), "a second unlock of the same type should fail")
	assert_eq(pm.upgrade_items, 1, "a failed unlock should not spend items")

func test_upgrades_are_per_type_not_shared():
	var pm = PlayerManagerScript.new()
	pm.add_upgrade_items(2)
	assert_true(pm.try_level_up_ability("pawn", 1, 2), "level up should succeed with enough items")
	assert_eq(pm.get_piece_upgrades("rook")["levels"][1], 1, "upgrading one type should not touch another type")

func test_set_starting_resets_upgrades_and_items():
	var pm = PlayerManagerScript.new()
	pm.add_upgrade_items(5)
	pm.try_level_up_ability("pawn", 1, 2)
	pm.setStarting()
	assert_eq(pm.upgrade_items, 0, "a new run should start with 0 upgrade items")
	assert_eq(pm.get_piece_upgrades("pawn")["levels"][1], 1, "a new run should reset all piece upgrades to level 1")

func test_has_passive_false_when_not_owned():
	var pm = PlayerManagerScript.new()
	assert_false(pm.has_passive("spyglass"), "has_passive should be false when the item isn't owned")

func test_has_passive_true_when_owned():
	var pm = PlayerManagerScript.new()
	pm.add_item("spyglass", 1)
	assert_true(pm.has_passive("spyglass"), "has_passive should be true once at least 1 copy is owned")

func test_has_passive_false_for_consumable_even_if_owned():
	var pm = PlayerManagerScript.new()
	pm.add_item("extra_move", 1)
	assert_false(pm.has_passive("extra_move"), "has_passive should be false for consumable-kind items")
