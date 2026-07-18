extends TestCase

const BattleControllerScript = preload("res://Scripts/TileMap/BattleController.gd")

func test_adjacent_move_has_empty_path():
	var bc = BattleControllerScript.new()
	var path = bc._compute_path_tiles(Vector2i(0, 0), Vector2i(1, 0))
	assert_eq(path, [], "a 1-tile move has no tiles strictly between origin and destination")

func test_horizontal_slide_path():
	var bc = BattleControllerScript.new()
	var path = bc._compute_path_tiles(Vector2i(0, 0), Vector2i(3, 0))
	assert_eq(path, [Vector2i(1, 0), Vector2i(2, 0)], "horizontal 3-tile slide should pass through 2 intermediate tiles")

func test_diagonal_slide_path():
	var bc = BattleControllerScript.new()
	var path = bc._compute_path_tiles(Vector2i(0, 0), Vector2i(-3, -3))
	assert_eq(path, [Vector2i(-1, -1), Vector2i(-2, -2)], "diagonal 3-tile slide should pass through 2 intermediate tiles")

func test_knight_jump_long_x_bend():
	var bc = BattleControllerScript.new()
	# delta (2, 1): |dx| > |dy|, so the stylized bend goes the long (x) axis first.
	var path = bc._compute_path_tiles(Vector2i(0, 0), Vector2i(2, 1))
	assert_eq(path, [Vector2i(2, 0)], "knight jump with |dx|>|dy| should bend along x first")

func test_knight_jump_long_y_bend():
	var bc = BattleControllerScript.new()
	# delta (1, 2): |dy| > |dx|, so the stylized bend goes the long (y) axis first.
	var path = bc._compute_path_tiles(Vector2i(0, 0), Vector2i(1, 2))
	assert_eq(path, [Vector2i(0, 2)], "knight jump with |dy|>|dx| should bend along y first")

# ----------------- Item "bounty" -----------------

const PlayerManagerScript = preload("res://Scripts/Player/PlayerManager.gd")
const BaseCharacterScript = preload("res://Scripts/CharacterPieces/base_character.gd")

func test_on_enemy_died_rewards_only_when_bounty_target_dies_first():
	var bc = BattleControllerScript.new()
	bc.player_manager = PlayerManagerScript.new()
	var target := BaseCharacterScript.new()
	bc.bounty_target = target

	var before: int = bc.player_manager.upgrade_items
	bc.on_enemy_died(target)
	assert_eq(bc.player_manager.upgrade_items, before + 1,
		"the bounty target dying first should grant the reward (1x reward field, default 1)")

func test_on_enemy_died_no_reward_when_target_not_first_to_die():
	var bc = BattleControllerScript.new()
	bc.player_manager = PlayerManagerScript.new()
	var target := BaseCharacterScript.new()
	var other := BaseCharacterScript.new()
	bc.bounty_target = target

	var before: int = bc.player_manager.upgrade_items
	bc.on_enemy_died(other) # some other enemy dies first - bounty missed
	assert_eq(bc.player_manager.upgrade_items, before,
		"no reward should be granted when the first enemy to die isn't the bounty target")

func test_on_enemy_died_only_resolves_once_per_battle():
	var bc = BattleControllerScript.new()
	bc.player_manager = PlayerManagerScript.new()
	var target := BaseCharacterScript.new()
	bc.bounty_target = target

	bc.on_enemy_died(BaseCharacterScript.new()) # first death (miss) resolves the bounty
	var before: int = bc.player_manager.upgrade_items
	bc.on_enemy_died(target) # target dies second - too late, already resolved
	assert_eq(bc.player_manager.upgrade_items, before,
		"only the FIRST enemy death in a battle should be able to resolve the bounty")

# ----------------- Item "courier_package" -----------------

func test_courier_reward_paid_when_courier_survives():
	var bc = BattleControllerScript.new()
	bc.player_manager = PlayerManagerScript.new()
	bc.courier = BaseCharacterScript.new() # never freed - still is_instance_valid()

	var before: int = bc.player_manager.upgrade_items
	bc._maybe_pay_courier_reward()
	assert_eq(bc.player_manager.upgrade_items, before + 1,
		"a surviving courier should pay the reward (1x reward field, default 1)")

func test_courier_reward_not_paid_when_courier_died():
	var bc = BattleControllerScript.new()
	bc.player_manager = PlayerManagerScript.new()
	var courier := BaseCharacterScript.new()
	bc.courier = courier
	courier.free() # simulates die()'s queue_free() having already taken effect

	var before: int = bc.player_manager.upgrade_items
	bc._maybe_pay_courier_reward()
	assert_eq(bc.player_manager.upgrade_items, before,
		"a captured (freed) courier should not pay any reward")

func test_courier_reward_not_paid_when_no_courier_was_marked():
	var bc = BattleControllerScript.new()
	bc.player_manager = PlayerManagerScript.new()
	bc.courier = null

	var before: int = bc.player_manager.upgrade_items
	bc._maybe_pay_courier_reward()
	assert_eq(bc.player_manager.upgrade_items, before,
		"no reward should be paid when courier_package wasn't owned (courier never marked)")
