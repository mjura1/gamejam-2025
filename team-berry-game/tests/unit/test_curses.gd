extends TestCase

# Prekletstva (Scripts/Curses/, GameParameters/curses.json): razred/data-loader logika.
# Glej ENEMY_CURSES_PLAN.md Phase 1.

const ALL_CURSE_IDS := ["snowfall", "frenzy", "stunning_gaze", "blizzard",
	"fey_step", "changeling", "abduction", "entangle", "wraith_cloak", "contagion", "bloodlust"]

func test_create_curse_returns_correct_variant_with_data_from_json():
	for id in ALL_CURSE_IDS:
		var curse: BaseCurse = CurseData.create_curse(id)
		assert_true(curse != null, "create_curse(%s) should not be null" % id)
		assert_eq(curse.id, id, "curse.id should match requested id")
		assert_eq(curse.display_name(), CurseData.get_curse_name(id), "display_name should read from JSON")
		assert_eq(curse.description(), CurseData.get_curse_description(id), "description should read from JSON")
		assert_eq(curse.color(), CurseData.get_color(id), "color should read from JSON")
		assert_true(curse.status_text().begins_with("CURSED:"), "status_text should be prefixed CURSED:")

func test_create_curse_unknown_id_returns_null():
	assert_true(CurseData.create_curse("does_not_exist") == null, "unknown curse id should return null")

func test_frenzy_extra_actions_reads_json_param():
	var curse: BaseCurse = CurseData.create_curse("frenzy")
	assert_eq(curse.extra_actions(), CurseData.get_param("frenzy", "extra_actions", 1), "frenzy extra_actions should read from JSON")

func test_base_curse_extra_actions_defaults_to_zero():
	var curse: BaseCurse = CurseData.create_curse("snowfall")
	assert_eq(curse.extra_actions(), 0, "non-frenzy curses should default to 0 extra actions")

func test_get_curse_chance_applies_difficulty_multiplier():
	var base := CurseData.get_curse_chance_base()
	assert_eq(CurseData.get_curse_chance("normal"), base, "normal difficulty should be 1x base chance")
	assert_eq(CurseData.get_curse_chance("easy"), base * 0.5, "easy difficulty should be 0.5x base chance")
	assert_eq(CurseData.get_curse_chance("hard"), base * 1.5, "hard difficulty should be 1.5x base chance")

func test_get_curse_chance_applies_tier_multiplier():
	var mults: Array = CurseData._config.get("tier_curse_chance_mult", [1.0])
	assert_true(mults.size() >= 2, "tier_curse_chance_mult should define at least tiers 0 and 1")
	var base := CurseData.get_curse_chance_base()
	assert_eq(CurseData.get_curse_chance("normal", 0), base * mults[0], "tier 0 should apply tier_curse_chance_mult[0]")
	assert_eq(CurseData.get_curse_chance("normal", 1), base * mults[1], "tier 1 should apply tier_curse_chance_mult[1]")

func test_get_infinite_curse_chance_bonus_zero_at_or_below_base_tier():
	var base_tier: int = CurseData._config.get("infinite_mode", {}).get("base_tier", 2)
	assert_eq(CurseData.get_infinite_curse_chance_bonus(0), 0.0, "tier 0 should add no infinite-mode chance bonus")
	assert_eq(CurseData.get_infinite_curse_chance_bonus(base_tier), 0.0, "base_tier itself should add no infinite-mode chance bonus")

func test_get_curse_chance_infinite_bonus_grows_past_base_tier_and_clamps():
	var base_tier: int = CurseData._config.get("infinite_mode", {}).get("base_tier", 2)
	var max_chance: float = CurseData._config.get("infinite_mode", {}).get("max_curse_chance", 1.0)
	assert_true(CurseData.get_curse_chance("normal", base_tier + 1) > CurseData.get_curse_chance("normal", base_tier),
		"1 tier past base_tier should raise the curse chance above the base-tier value")
	assert_true(CurseData.get_curse_chance("normal", base_tier + 20) <= max_chance,
		"curse chance should never exceed config.infinite_mode.max_curse_chance however far tier climbs")

func test_get_min_floor_uses_tier_min_floor_array():
	var tiers: Array = CurseData._config.get("tier_min_floor", [2])
	assert_true(tiers.size() >= 3, "tier_min_floor should define tiers 0, 1 and 2")
	assert_eq(CurseData.get_min_floor(0), tiers[0], "tier 0 should use tier_min_floor[0]")
	assert_eq(CurseData.get_min_floor(1), tiers[1], "tier 1 should use tier_min_floor[1]")
	assert_eq(CurseData.get_min_floor(2), tiers[2], "tier 2 should use tier_min_floor[2]")

func test_get_min_floor_decreases_further_past_base_tier_in_infinite_mode():
	var inf: Dictionary = CurseData._config.get("infinite_mode", {})
	var base_tier: int = inf.get("base_tier", 2)
	var decrement: int = inf.get("min_floor_decrement_per_tier", 0)
	assert_true(decrement > 0, "min_floor_decrement_per_tier should be configured so infinite mode gets harder")
	var floor_at_base := CurseData.get_min_floor(base_tier)
	assert_eq(CurseData.get_min_floor(base_tier + 1), floor_at_base - decrement,
		"1 tier past base_tier should lower min_floor by min_floor_decrement_per_tier")
	assert_true(CurseData.get_min_floor(base_tier + 2) < CurseData.get_min_floor(base_tier + 1),
		"min_floor should keep dropping the further past base_tier you go")

func test_get_min_floor_clamps_at_min_floor_clamp():
	var clamp_value: int = CurseData._config.get("infinite_mode", {}).get("min_floor_clamp", 0)
	assert_eq(CurseData.get_min_floor(500), clamp_value, "min_floor should never drop below min_floor_clamp, however far tier climbs")

func test_should_curse_respects_min_floor():
	var min_floor := CurseData.get_min_floor()
	assert_false(CurseData.should_curse(min_floor - 1, 0.0, "normal"), "floor below min_floor should never curse")
	assert_true(CurseData.should_curse(min_floor, 0.0, "normal"), "floor at/above min_floor with roll 0.0 should curse (chance > 0)")

func test_should_curse_respects_roll_against_chance():
	var min_floor := CurseData.get_min_floor()
	var chance := CurseData.get_curse_chance("normal")
	assert_true(CurseData.should_curse(min_floor, chance - 0.001, "normal"), "roll just under chance should curse")
	assert_false(CurseData.should_curse(min_floor, chance + 0.001, "normal"), "roll at/over chance should not curse")

func test_roll_curse_for_is_deterministic_with_seeded_rng():
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42
	assert_eq(CurseData.roll_curse_for("pawn", rng_a), CurseData.roll_curse_for("pawn", rng_b),
		"same seed should produce the same rolled curse")

func test_roll_curse_for_never_rolls_zero_weight_curse():
	# Temporarily zero out frenzy's weight (base AND weight_by_difficulty.normal,
	# which shadows "weight" for the default "normal" difficulty passed below -
	# see curses.json's weight_by_difficulty comment) and confirm it never rolls.
	var original: Dictionary = CurseData._curses["frenzy"].duplicate()
	CurseData._curses["frenzy"]["weight"] = 0
	CurseData._curses["frenzy"]["weight_by_difficulty"] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(50):
		var id := CurseData.roll_curse_for("pawn", rng)
		assert_true(id != "frenzy", "a curse with weight 0 should never be rolled")
	CurseData._curses["frenzy"] = original

func test_roll_curse_for_piece_excluded_from_every_curse_returns_empty():
	var originals: Dictionary = {}
	for id in CurseData.get_curse_ids():
		originals[id] = CurseData._curses[id].get("excluded_pieces", []).duplicate()
		CurseData._curses[id]["excluded_pieces"] = ["totally_excluded_piece"]
	assert_eq(CurseData.roll_curse_for("totally_excluded_piece"), "", "a piece excluded from every curse should get none")
	for id in CurseData.get_curse_ids():
		CurseData._curses[id]["excluded_pieces"] = originals[id]

func test_get_min_curse_count_below_min_floor_is_zero():
	var min_floor := CurseData.get_min_floor()
	assert_eq(CurseData.get_min_curse_count(min_floor - 1), 0, "floor below min_floor should guarantee 0 curses")

func test_get_min_curse_count_boss_floor_uses_fixed_boss_count():
	var min_floor := CurseData.get_min_floor()
	assert_eq(CurseData.get_min_curse_count(min_floor - 1, 0, true, false), CurseData.get_boss_curse_count(),
		"boss floor should guarantee config.boss_curse_count regardless of room depth, even below min_floor")

func test_get_min_curse_count_mini_boss_floor_uses_fixed_mini_boss_count():
	var min_floor := CurseData.get_min_floor()
	assert_eq(CurseData.get_min_curse_count(min_floor - 1, 0, false, true), CurseData.get_mini_boss_curse_count(),
		"mini-boss floor should guarantee config.mini_boss_curse_count regardless of room depth, even below min_floor")

func test_get_min_curse_count_boss_takes_precedence_over_mini_boss():
	var min_floor := CurseData.get_min_floor()
	assert_eq(CurseData.get_min_curse_count(min_floor, 0, true, true), CurseData.get_boss_curse_count(),
		"if both flags are somehow true, boss_curse_count should win")

func test_get_min_curse_count_scales_by_one_per_floor_from_min_floor():
	var min_floor := CurseData.get_min_floor()
	assert_eq(CurseData.get_min_curse_count(min_floor), 1, "min_floor should guarantee 1 curse")
	assert_eq(CurseData.get_min_curse_count(min_floor + 1), 2, "min_floor + 1 should guarantee 2 curses")
	assert_eq(CurseData.get_min_curse_count(min_floor + 2), 3, "min_floor + 2 should guarantee 3 curses")

func test_get_infinite_tier_curse_bonus_zero_at_or_below_base_tier():
	assert_eq(CurseData.get_infinite_tier_curse_bonus(0), 0, "tier 0 should add no infinite-mode bonus")
	assert_eq(CurseData.get_infinite_tier_curse_bonus(2), 0, "base_tier itself should add no infinite-mode bonus")

func test_get_infinite_tier_curse_bonus_scales_past_base_tier():
	assert_eq(CurseData.get_infinite_tier_curse_bonus(3), 1, "1 tier past base_tier should add 1 bonus curse")
	assert_eq(CurseData.get_infinite_tier_curse_bonus(5), 3, "3 tiers past base_tier should add 3 bonus curses")

func test_get_min_curse_count_increases_with_tier_past_base_tier():
	# room depth relative to base_tier's OWN min_floor - avoids baking in the
	# exact tier_min_floor/decrement numbers, since both the shrinking
	# min_floor AND the tier count bonus push this up together now.
	var base_tier: int = CurseData._config.get("infinite_mode", {}).get("base_tier", 2)
	var current_floor := CurseData.get_min_floor(base_tier) + 2
	var count_at_base_tier := CurseData.get_min_curse_count(current_floor, base_tier)
	var count_one_tier_later := CurseData.get_min_curse_count(current_floor, base_tier + 1)
	assert_true(count_one_tier_later > count_at_base_tier,
		"1 tier past base_tier should guarantee strictly more curses (lower min_floor + tier count bonus combined)")

func test_get_min_curse_count_clamps_to_max_curse_count():
	var min_floor := CurseData.get_min_floor()
	var max_count: int = CurseData._config.get("infinite_mode", {}).get("max_curse_count", -1)
	assert_true(max_count >= 0, "infinite_mode.max_curse_count should be configured")
	assert_eq(CurseData.get_min_curse_count(min_floor + 50, 50), max_count,
		"guaranteed curse count should never exceed config.infinite_mode.max_curse_count")

func test_roll_curse_for_piece_excluded_from_one_curse_only_gets_others():
	var original: Array = CurseData._curses["frenzy"].get("excluded_pieces", []).duplicate()
	CurseData._curses["frenzy"]["excluded_pieces"] = ["queen"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in range(50):
		var id := CurseData.roll_curse_for("queen", rng)
		assert_true(id != "frenzy", "a piece excluded from frenzy should never roll frenzy")
	CurseData._curses["frenzy"]["excluded_pieces"] = original

# ----------------- NEW CURSES (Fey Step/Changeling/Abduction/Entangle/
# Wraith Cloak/Contagion/Bloodlust): base_curse.gd hook defaults + JSON param
# wiring. Live-grid effects (blink/swap/root/self-fog/spread/bonus action)
# are exercised through the real BattleController in
# tests/smoke/smoke_curses.gd - these cover the pure, grid-independent logic.

func test_base_curse_can_capture_defaults_to_true():
	for id in ["snowfall", "frenzy", "stunning_gaze", "blizzard", "changeling", "abduction", "entangle", "wraith_cloak", "contagion", "bloodlust"]:
		var curse: BaseCurse = CurseData.create_curse(id)
		assert_true(curse.can_capture(), "%s should be able to capture (only fey_step can't)" % id)

func test_fey_step_cannot_capture():
	var curse: BaseCurse = CurseData.create_curse("fey_step")
	assert_false(curse.can_capture(), "fey_step should not be able to capture")

func test_base_curse_grants_bonus_action_on_capture_defaults_to_false():
	for id in ["snowfall", "frenzy", "stunning_gaze", "blizzard", "fey_step", "changeling", "abduction", "entangle", "wraith_cloak", "contagion"]:
		var curse: BaseCurse = CurseData.create_curse(id)
		assert_false(curse.grants_bonus_action_on_capture(), "%s should not grant a bloodlust-style bonus action" % id)

func test_bloodlust_grants_bonus_action_on_capture():
	var curse: BaseCurse = CurseData.create_curse("bloodlust")
	assert_true(curse.grants_bonus_action_on_capture(), "bloodlust should grant a bonus action on capture")

func test_fey_step_blink_params_read_from_json():
	var chance: float = CurseData.get_param("fey_step", "blink_chance", -1.0)
	assert_true(chance > 0.0 and chance <= 1.0, "fey_step blink_chance should be a probability in (0, 1]")
	assert_true(CurseData.get_param("fey_step", "blink_range", -1) > 0, "fey_step should define a positive blink_range")

func test_entangle_duration_and_cooldown_read_from_json():
	assert_true(CurseData.get_param("entangle", "duration", -1) > 0, "entangle should define a positive duration")
	assert_true(CurseData.get_param("entangle", "cooldown", -1) > 0, "entangle should define a positive cooldown")

func test_contagion_spread_chance_reads_from_json():
	var chance: float = CurseData.get_param("contagion", "spread_chance", -1.0)
	assert_true(chance > 0.0 and chance < 1.0, "contagion spread_chance should be a probability in (0, 1)")

func test_bloodlust_max_bonus_actions_reads_from_json():
	assert_true(CurseData.get_param("bloodlust", "max_bonus_actions", -1) > 0, "bloodlust should define a positive max_bonus_actions")

func test_bloodlust_has_very_low_weight():
	# Miha: bloodlust "can wipe your board" - keep it rare relative to the
	# original 3 curses (snowfall=40/frenzy=30/stunning_gaze=30).
	assert_true(CurseData.get_weight("bloodlust") < CurseData.get_weight("snowfall"),
		"bloodlust should be rarer than the baseline curses")
