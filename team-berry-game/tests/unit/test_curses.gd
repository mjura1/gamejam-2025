extends TestCase

# Prekletstva (Scripts/Curses/, Data/curses.json): razred/data-loader logika.
# Glej ENEMY_CURSES_PLAN.md Phase 1.

func test_create_curse_returns_correct_variant_with_data_from_json():
	for id in ["snowfall", "frenzy", "stunning_gaze", "blizzard"]:
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
	# Temporarily zero out frenzy's weight and confirm it never rolls.
	var original: Dictionary = CurseData._curses["frenzy"].duplicate()
	CurseData._curses["frenzy"]["weight"] = 0
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

func test_get_min_curse_count_scales_by_one_per_floor_from_min_floor():
	var min_floor := CurseData.get_min_floor()
	assert_eq(CurseData.get_min_curse_count(min_floor), 1, "min_floor should guarantee 1 curse")
	assert_eq(CurseData.get_min_curse_count(min_floor + 1), 2, "min_floor + 1 should guarantee 2 curses")
	assert_eq(CurseData.get_min_curse_count(min_floor + 2), 3, "min_floor + 2 should guarantee 3 curses")

func test_roll_curse_for_piece_excluded_from_one_curse_only_gets_others():
	var original: Array = CurseData._curses["frenzy"].get("excluded_pieces", []).duplicate()
	CurseData._curses["frenzy"]["excluded_pieces"] = ["queen"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in range(50):
		var id := CurseData.roll_curse_for("queen", rng)
		assert_true(id != "frenzy", "a piece excluded from frenzy should never roll frenzy")
	CurseData._curses["frenzy"]["excluded_pieces"] = original
