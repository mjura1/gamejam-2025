extends TestCase

func test_roll_shop_stock_is_deterministic_with_seeded_rng():
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42
	assert_eq(ItemData.roll_shop_stock(rng_a), ItemData.roll_shop_stock(rng_b),
		"same seed should produce the same rolled stock")

func test_roll_shop_stock_respects_slot_count():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(ItemData.roll_shop_stock(rng).size(), ItemData.get_shop_slot_count(),
		"roll_shop_stock should return exactly slot_count entries")

func test_roll_shop_stock_all_common_when_weights_only_common():
	var original := ItemData.get_rarity_weights()
	ItemData._shop_config["rarity_weights"] = {"common": 1}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stock := ItemData.roll_shop_stock(rng)
	for id in stock:
		assert_eq(ItemData.get_rarity(id), "common", "with only common weighted, every roll should be common")
	ItemData._shop_config["rarity_weights"] = original

func test_roll_shop_stock_skips_empty_rarity_without_crash():
	var original := ItemData.get_rarity_weights()
	ItemData._shop_config["rarity_weights"] = {"common": 1, "legendary": 99}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var stock := ItemData.roll_shop_stock(rng)
	assert_eq(stock.size(), ItemData.get_shop_slot_count(), "an empty named rarity should not crash the roll")
	for id in stock:
		assert_true(ItemData.get_item_ids().has(id), "every rolled id should exist in items.json")
	ItemData._shop_config["rarity_weights"] = original

func test_roll_shop_stock_every_id_exists_in_items():
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var stock := ItemData.roll_shop_stock(rng)
	for id in stock:
		assert_true(ItemData.get_item_ids().has(id), "every rolled id should exist in items.json")
