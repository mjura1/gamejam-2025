extends TestCase

const PlayerManagerScript = preload("res://Scripts/Player/PlayerManager.gd")

func test_add_item_accumulates():
	var pm = PlayerManagerScript.new()
	pm.add_item("extra_move", 2)
	pm.add_item("extra_move", 1)
	assert_eq(pm.get_item_count("extra_move"), 3, "add_item should accumulate across calls")

func test_remove_item_fails_on_empty():
	var pm = PlayerManagerScript.new()
	assert_false(pm.remove_item("extra_move"), "remove_item should fail when the player owns none")

func test_remove_item_decrements_and_clears_key_at_zero():
	var pm = PlayerManagerScript.new()
	pm.add_item("extra_move", 1)
	assert_true(pm.remove_item("extra_move"), "remove_item should succeed while count > 0")
	assert_eq(pm.get_item_count("extra_move"), 0, "count should be 0 after removing the only copy")
	assert_false(pm.owned_items.has("extra_move"), "owned_items should not keep a 0-count key")

func test_try_buy_item_spends_upgrade_items_and_grants_item():
	var pm = PlayerManagerScript.new()
	pm.add_upgrade_items(2)
	assert_true(pm.try_buy_item("extra_move"), "buy should succeed with enough upgrade items")
	assert_eq(pm.upgrade_items, 1, "buy should spend exactly buy_cost (1)")
	assert_eq(pm.get_item_count("extra_move"), 1, "buy should grant 1x the item")

func test_try_buy_item_fails_when_poor():
	var pm = PlayerManagerScript.new()
	assert_false(pm.try_buy_item("extra_move"), "buy should fail with 0 upgrade items")
	assert_eq(pm.get_item_count("extra_move"), 0, "a failed buy should not grant the item")

func test_try_sell_item_refunds_and_removes():
	var pm = PlayerManagerScript.new()
	pm.add_item("extra_move", 1)
	assert_true(pm.try_sell_item("extra_move"), "sell should succeed while owned")
	assert_eq(pm.upgrade_items, 1, "sell should refund sell_value (1)")
	assert_eq(pm.get_item_count("extra_move"), 0, "sell should remove the sold copy")

func test_try_sell_item_fails_when_not_owned():
	var pm = PlayerManagerScript.new()
	assert_false(pm.try_sell_item("extra_move"), "sell should fail when the player owns none")
	assert_eq(pm.upgrade_items, 0, "a failed sell should not refund anything")

func test_try_sell_reserve_piece_refunds_and_removes():
	var pm = PlayerManagerScript.new()
	var friendly: Array[String] = ["friendly_pawn"]
	var reserve: Array[String] = ["friendly_rook"]
	pm.friendly_party = friendly
	pm.reserve_party = reserve
	assert_true(pm.try_sell_reserve_piece(0), "selling a reserve piece should succeed")
	assert_eq(pm.upgrade_items, 1, "selling a reserve piece should refund its sell value (1)")
	assert_eq(pm.reserve_party, [], "the sold piece should be removed from reserve_party")

func test_try_sell_active_piece_refunds_and_removes_when_not_last():
	var pm = PlayerManagerScript.new()
	var friendly: Array[String] = ["friendly_pawn", "friendly_rook"]
	pm.friendly_party = friendly
	assert_true(pm.try_sell_active_piece(1), "selling an active piece should succeed while others remain")
	assert_eq(pm.upgrade_items, 1, "selling an active piece should refund its sell value (1)")
	assert_eq(pm.friendly_party, ["friendly_pawn"], "the sold piece should be removed from friendly_party")

func test_try_sell_active_piece_refuses_last_piece():
	var pm = PlayerManagerScript.new()
	var friendly: Array[String] = ["friendly_pawn"]
	pm.friendly_party = friendly
	assert_false(pm.try_sell_active_piece(0), "selling the last active piece should be refused (never leave active party empty)")
	assert_eq(pm.friendly_party, ["friendly_pawn"], "a refused sell should not change friendly_party")
	assert_eq(pm.upgrade_items, 0, "a refused sell should not refund anything")

func test_set_starting_resets_owned_items():
	var pm = PlayerManagerScript.new()
	pm.add_item("extra_move", 3)
	pm.setStarting()
	assert_eq(pm.owned_items, {}, "a new run should start with no owned items")
