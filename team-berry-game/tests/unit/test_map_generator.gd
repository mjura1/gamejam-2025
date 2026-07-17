extends TestCase

const MapGeneratorScript = preload("res://Scripts/Map/MapGenerator.gd")

func test_tier_0_is_tutorial_depth_with_pawn_and_knight_only():
	var gen = MapGeneratorScript.new()
	gen._configure_tier(0)
	assert_eq(gen.FLOORS, 5, "Tier 0 should be a 5-floor tutorial map")
	assert_eq(gen.boss_type, Room.RoomType.enemy_knight, "Tier 0's boss floor should be a knight")
	assert_true(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_pawn), "Tier 0 should allow pawns")
	assert_true(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_knight), "Tier 0 should allow knights")
	assert_false(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_rook), "Tier 0 should not allow rooks")
	assert_false(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_bishop), "Tier 0 should not allow bishops")
	assert_false(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_queen), "Tier 0 should not allow queens")
	assert_false(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_king), "Tier 0 should not allow kings")

func test_tier_1_adds_rook_and_bishop():
	var gen = MapGeneratorScript.new()
	gen._configure_tier(1)
	assert_eq(gen.FLOORS, 7, "Tier 1 should be a 7-floor map")
	assert_eq(gen.boss_type, Room.RoomType.enemy_rook, "Tier 1's boss floor should be a rook")
	assert_true(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_rook), "Tier 1 should allow rooks")
	assert_true(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_bishop), "Tier 1 should allow bishops")
	assert_false(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_queen), "Tier 1 should not allow queens yet")
	assert_false(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_king), "Tier 1 should not allow kings yet")

func test_tier_2_adds_queen_mini_boss_and_king_final_boss():
	var gen = MapGeneratorScript.new()
	gen._configure_tier(2)
	assert_eq(gen.FLOORS, 9, "Tier 2 should be a 9-floor map")
	assert_eq(gen.boss_type, Room.RoomType.enemy_king, "Tier 2's final boss should be the king")
	assert_eq(gen.mini_boss_floor, 6, "Tier 2's mini-boss should land on floor FLOORS - 3 (6)")
	assert_eq(gen.mini_boss_type, Room.RoomType.enemy_queen, "Tier 2's mini-boss should be the queen")
	assert_eq(gen.recruit_floor, 3, "Tier 2's friendly-king recruit floor moved to 3 to make room for the shop at 4")
	assert_eq(gen.shop_floor, 4, "Tier 2 should have a shop floor at 4 (the map's middle floor)")
	assert_true(gen.ROOM_WEIGHTS.has(Room.RoomType.enemy_queen), "Tier 2 should allow queens in the random pool")

func test_all_tiers_keep_friendly_rooms_available():
	for tier in range(3):
		var gen = MapGeneratorScript.new()
		gen._configure_tier(tier)
		assert_true(gen.ROOM_WEIGHTS.has(Room.RoomType.friendly_pawn), "Tier %d should still allow friendly recruit rooms" % tier)

func test_total_weight_matches_sum_of_room_weights():
	var gen = MapGeneratorScript.new()
	gen._configure_tier(1)
	var expected_sum = 0
	for weight in gen.ROOM_WEIGHTS.values():
		expected_sum += weight
	assert_eq(gen.total_weight, expected_sum, "total_weight should equal the sum of the configured ROOM_WEIGHTS")

func test_tier_1_has_shop_floor_at_map_middle():
	var gen = MapGeneratorScript.new()
	gen._configure_tier(1)
	assert_eq(gen.shop_floor, 3, "Tier 1 should have a shop floor at 3 (the map's middle floor)")

func test_tier_0_has_no_shop_floor():
	var gen = MapGeneratorScript.new()
	gen._configure_tier(0)
	assert_eq(gen.shop_floor, -1, "Tier 0 should not have a shop floor")

func test_shop_floor_is_all_shop_rooms_on_every_generated_tier_1_and_2_map():
	for tier in [1, 2]:
		var gen = MapGeneratorScript.new()
		gen.generate_map(tier)
		var found_shop := false
		for room in gen.map_data[gen.shop_floor]:
			if room == null:
				continue
			found_shop = true
			assert_eq(room.type, Room.RoomType.shop, "Tier %d: every non-null room on the shop floor should be type shop" % tier)
		assert_true(found_shop, "Tier %d should have at least one shop room on the shop floor" % tier)

func test_every_tier_forces_campfire_on_second_to_last_floor():
	# _connect_to_boss() funnels every surviving path through FLOORS - 2 before
	# the boss floor, so that's the one floor where a rest stop is guaranteed
	# regardless of which path the player took.
	for tier in range(3):
		var gen = MapGeneratorScript.new()
		gen.generate_map(tier)
		var campfire_floor = gen.FLOORS - 2
		var found_campfire := false
		for room in gen.map_data[campfire_floor]:
			if room == null:
				continue
			found_campfire = true
			assert_eq(room.type, Room.RoomType.campfire, "Tier %d: every room on floor FLOORS - 2 should be a campfire" % tier)
		assert_true(found_campfire, "Tier %d should have at least one room on floor FLOORS - 2" % tier)
