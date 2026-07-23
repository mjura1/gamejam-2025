extends TestCase

func test_roll_treasure_loot_is_deterministic_with_seeded_rng():
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42
	assert_eq(ItemData.roll_treasure_loot(0, 0, rng_a), ItemData.roll_treasure_loot(0, 0, rng_b),
		"same seed should produce the same rolled loot")

func test_roll_treasure_loot_base_count_with_no_luck():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var loot := ItemData.roll_treasure_loot(0, 0, rng)
	assert_eq(loot.size(), ItemData._treasure_config.get("base_item_count", 1),
		"0 luck should yield exactly base_item_count items")

func test_roll_treasure_loot_item_count_caps_at_max_bonus_items():
	var luck_per_bonus: int = ItemData._treasure_config.get("luck_per_bonus_item", 3)
	var max_bonus: int = ItemData._treasure_config.get("max_bonus_items", 2)
	var base_count: int = ItemData._treasure_config.get("base_item_count", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var loot := ItemData.roll_treasure_loot(0, luck_per_bonus * max_bonus * 10, rng)
	assert_eq(loot.size(), base_count + max_bonus,
		"very high luck should cap bonus items at max_bonus_items")

func test_roll_treasure_loot_rarity_never_regresses_with_more_luck():
	var luck_per_bonus: int = ItemData._treasure_config.get("luck_per_bonus_item", 3)
	var max_bonus: int = ItemData._treasure_config.get("max_bonus_items", 2)
	for seed in range(1, 11):
		var rng_low := RandomNumberGenerator.new()
		rng_low.seed = seed
		var low_rank: int = ItemData.RARITY_ORDER.find(
			ItemData.get_rarity(ItemData.roll_treasure_loot(0, 0, rng_low)[0]))

		var rng_high := RandomNumberGenerator.new()
		rng_high.seed = seed
		var high_rank: int = ItemData.RARITY_ORDER.find(
			ItemData.get_rarity(ItemData.roll_treasure_loot(0, luck_per_bonus * max_bonus * 10, rng_high)[0]))

		assert_true(high_rank >= low_rank,
			"higher luck should never roll a worse rarity than lower luck (seed %d)" % seed)

func test_get_treasure_rarity_weights_clamps_tier_to_last_table():
	var tables: Array = ItemData._treasure_config.get("rarity_weights_by_tier", [])
	assert_eq(ItemData.get_treasure_rarity_weights(99), ItemData.get_treasure_rarity_weights(tables.size() - 1),
		"tiers beyond the table should clamp to the last (best) entry, same as MapGenerator._configure_tier")

func test_roll_treasure_loot_skips_empty_rarity_without_crash():
	var original: Array = ItemData._treasure_config.get("rarity_weights_by_tier", [])
	ItemData._treasure_config["rarity_weights_by_tier"] = [{"common": 1, "mythic": 99}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var loot := ItemData.roll_treasure_loot(0, 0, rng)
	assert_false(loot.is_empty(), "an empty named rarity should not crash the roll")
	for id in loot:
		assert_true(ItemData.get_item_ids().has(id), "every rolled id should exist in items.json")
	ItemData._treasure_config["rarity_weights_by_tier"] = original

func test_roll_treasure_loot_every_id_exists_in_items():
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var loot := ItemData.roll_treasure_loot(2, 10, rng)
	for id in loot:
		assert_true(ItemData.get_item_ids().has(id), "every rolled id should exist in items.json")

func test_shop_stock_never_contains_artifact_kind():
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var stock := ItemData.roll_shop_stock(rng)
	for id in stock:
		assert_true(ItemData.get_kind(id) != "artifact", "shop stock should never contain an artifact-kind item")
