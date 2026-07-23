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
	var expected: int = ItemData.get_treasure_item_count(0) + ItemData.get_treasure_artifact_count(0)
	assert_eq(loot.size(), expected,
		"0 luck should yield exactly items_per_tier + artifacts_per_tier entries for this tier")

func test_roll_treasure_loot_item_count_caps_at_max_bonus_items():
	var luck_per_bonus: int = ItemData._treasure_config.get("luck_per_bonus_item", 3)
	var max_bonus: int = ItemData._treasure_config.get("max_bonus_items", 2)
	var max_bonus_artifacts: int = ItemData._treasure_config.get("max_bonus_artifacts", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var loot := ItemData.roll_treasure_loot(0, luck_per_bonus * max_bonus * 10, rng)
	var expected: int = ItemData.get_treasure_item_count(0) + max_bonus \
		+ ItemData.get_treasure_artifact_count(0) + max_bonus_artifacts
	assert_eq(loot.size(), expected,
		"very high luck should cap bonus regular items/artifacts at their max_bonus_* knobs, on top of the guaranteed counts")

func test_roll_treasure_loot_artifact_count_caps_at_max_bonus_artifacts():
	var luck_per_bonus_artifact: int = ItemData._treasure_config.get("luck_per_bonus_artifact", 6)
	var max_bonus_artifacts: int = ItemData._treasure_config.get("max_bonus_artifacts", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var loot := ItemData.roll_treasure_loot(0, luck_per_bonus_artifact * max_bonus_artifacts * 10, rng)
	var artifact_loot_count := 0
	for id in loot:
		if ItemData.get_kind(id) == "artifact":
			artifact_loot_count += 1
	var expected_artifacts: int = ItemData.get_treasure_artifact_count(0) + max_bonus_artifacts
	assert_eq(artifact_loot_count, expected_artifacts,
		"very high luck should cap bonus artifacts at max_bonus_artifacts, on top of artifacts_per_tier")

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

# ----------------- Guaranteed items AND artifacts, per-tier scaling -----------------

func test_roll_treasure_loot_always_includes_an_artifact_when_tier_guarantees_one():
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	assert_true(ItemData.get_treasure_artifact_count(1) > 0,
		"test assumes tier 1 guarantees at least 1 artifact per treasure_config.json")
	var loot := ItemData.roll_treasure_loot(1, 0, rng)
	var has_artifact := false
	for id in loot:
		if ItemData.get_kind(id) == "artifact":
			has_artifact = true
	assert_true(has_artifact, "a tier that guarantees artifacts should always include at least one in the loot")

func test_roll_treasure_loot_always_includes_a_regular_item():
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var loot := ItemData.roll_treasure_loot(1, 0, rng)
	var has_regular_item := false
	for id in loot:
		if ItemData.get_kind(id) in ["consumable", "passive"]:
			has_regular_item = true
	assert_true(has_regular_item, "a chest should always include at least one regular (non-artifact) item")

func test_get_treasure_item_count_matches_items_per_tier_within_classic_range():
	var per_tier: Array = ItemData._treasure_config.get("items_per_tier", [1])
	for tier in range(per_tier.size()):
		assert_eq(ItemData.get_treasure_item_count(tier), int(per_tier[tier]),
			"tiers within the classic table should use items_per_tier directly (tier %d)" % tier)

func test_get_treasure_artifact_count_matches_artifacts_per_tier_within_classic_range():
	var per_tier: Array = ItemData._treasure_config.get("artifacts_per_tier", [0])
	for tier in range(per_tier.size()):
		assert_eq(ItemData.get_treasure_artifact_count(tier), int(per_tier[tier]),
			"tiers within the classic table should use artifacts_per_tier directly (tier %d)" % tier)

func test_get_treasure_item_count_grows_past_base_tier_in_infinite_mode():
	var inf: Dictionary = ItemData._treasure_config.get("infinite_mode", {})
	var base_tier: int = inf.get("base_tier", 2)
	var base_count: int = ItemData.get_treasure_item_count(base_tier)
	var next_count: int = ItemData.get_treasure_item_count(base_tier + 1)
	assert_true(next_count >= base_count,
		"item count should never shrink for a tier past base_tier (infinite mode growth)")

func test_get_treasure_item_count_caps_at_max_items_far_into_infinite_mode():
	var inf: Dictionary = ItemData._treasure_config.get("infinite_mode", {})
	var max_items: int = inf.get("max_items", -1)
	if max_items < 0:
		return # no clamp configured, nothing to assert
	var base_tier: int = inf.get("base_tier", 2)
	assert_eq(ItemData.get_treasure_item_count(base_tier + 50), max_items,
		"item count should clamp at max_items arbitrarily deep into infinite mode")

func test_get_treasure_artifact_count_caps_at_max_artifacts_far_into_infinite_mode():
	var inf: Dictionary = ItemData._treasure_config.get("infinite_mode", {})
	var max_artifacts: int = inf.get("max_artifacts", -1)
	if max_artifacts < 0:
		return # no clamp configured, nothing to assert
	var base_tier: int = inf.get("base_tier", 2)
	assert_eq(ItemData.get_treasure_artifact_count(base_tier + 50), max_artifacts,
		"artifact count should clamp at max_artifacts arbitrarily deep into infinite mode")

# ----------------- Non-stackable exclusion -----------------

func test_roll_treasure_loot_excludes_already_owned_non_stackable_ids():
	var non_stackable_id := ""
	for id in ItemData.get_item_ids():
		if not ItemData.get_stackable(id):
			non_stackable_id = id
			break
	assert_true(non_stackable_id != "", "test assumes at least 1 non-stackable item exists in items.json")

	for seed in range(1, 21):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var loot := ItemData.roll_treasure_loot(2, 20, rng, [non_stackable_id])
		assert_false(loot.has(non_stackable_id),
			"an already-owned non-stackable item should never be rolled again (seed %d)" % seed)

func test_roll_shop_stock_excludes_already_owned_non_stackable_ids():
	var non_stackable_id := ""
	for id in ItemData.get_item_ids():
		if ItemData.get_kind(id) in ["consumable", "passive"] and not ItemData.get_stackable(id):
			non_stackable_id = id
			break
	assert_true(non_stackable_id != "", "test assumes at least 1 non-stackable shop item exists in items.json")

	for seed in range(1, 21):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var stock := ItemData.roll_shop_stock(rng, [non_stackable_id])
		assert_false(stock.has(non_stackable_id),
			"an already-owned non-stackable item should never appear in shop stock again (seed %d)" % seed)

func test_get_stackable_defaults_true_for_consumables():
	assert_true(ItemData.get_stackable("extra_move"), "consumables should default to stackable")

func test_get_stackable_false_for_boolean_passives():
	assert_false(ItemData.get_stackable("spyglass"), "a boolean-effect passive with no stacking benefit should be non-stackable")

func test_get_stackable_true_for_lucky_charm():
	assert_true(ItemData.get_stackable("lucky_charm"), "lucky_charm's luck_bonus scales with owned count, so it must stay stackable")
