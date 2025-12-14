extends Node

@onready var grid_manager = $GridManager

const obstacle = "res://Scenes/CharacterPiecesNodes/Neutral/House.tscn"

const friendly_pieces: Array = [
	"res://Scenes/CharacterPiecesNodes/Ally/pawn.tscn",
	"res://Scenes/CharacterPiecesNodes/Ally/rook.tscn",
	"res://Scenes/CharacterPiecesNodes/Ally/bishop.tscn",
	"res://Scenes/CharacterPiecesNodes/Ally/knight.tscn",
	"res://Scenes/CharacterPiecesNodes/Ally/king.tscn",
	"res://Scenes/CharacterPiecesNodes/Ally/queen.tscn"
	]
	
const enemy_pieces: Array = [
	"res://Scenes/CharacterPiecesNodes/Enemy/enemy_pawn.tscn",
	"res://Scenes/CharacterPiecesNodes/Enemy/enemy_rook.tscn",
	"res://Scenes/CharacterPiecesNodes/Enemy/enemy_bishop.tscn",
	"res://Scenes/CharacterPiecesNodes/Enemy/enemy_knight.tscn",
	"res://Scenes/CharacterPiecesNodes/Enemy/enemy_king.tscn",
	"res://Scenes/CharacterPiecesNodes/Enemy/enemy_queen.tscn"
	]
	


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

	# edina koda ki ni vibe codana:
	for i in range(1, 12):
		var spawn = randi_range(0, 1)
		if spawn == 1:
			var piece = randi_range(0, 5)
			grid_manager.spawn_character(friendly_pieces[piece], grid_manager.grid_to_world(Vector2(i,0)))
			
	for i in range(2, 12):
		for j in range(1, 11):
			var spawn = randi_range(0, 10)
			if spawn == 1:
				var piece = randi_range(0, 5)
				grid_manager.spawn_character(obstacle, grid_manager.grid_to_world(Vector2(i, j)))
				
	for i in range(1, 12):
		var spawn = randi_range(0, 1)
		if spawn == 1:
			var piece = randi_range(0, 5)
			grid_manager.spawn_character(enemy_pieces[piece], grid_manager.grid_to_world(Vector2(i, 11)))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
