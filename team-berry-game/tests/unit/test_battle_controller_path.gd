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
