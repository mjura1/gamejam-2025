extends Node

@onready var grid_manager = $GridManager

const obstacle = "res://Scenes/CharacterPiecesNodes/Neutral/House.tscn"
var to_spawn_enemy: Array
var to_spawn_ally: Array 

# Friendly pieces dictionary
const friendly_pieces := {
	"pawn": "res://Scenes/CharacterPiecesNodes/Ally/pawn.tscn",
	"rook": "res://Scenes/CharacterPiecesNodes/Ally/rook.tscn",
	"bishop": "res://Scenes/CharacterPiecesNodes/Ally/bishop.tscn",
	"knight": "res://Scenes/CharacterPiecesNodes/Ally/knight.tscn",
	"king": "res://Scenes/CharacterPiecesNodes/Ally/king.tscn",
	"queen": "res://Scenes/CharacterPiecesNodes/Ally/queen.tscn"
}

# Enemy pieces dictionary
const enemy_pieces := {
	"pawn": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_pawn.tscn",
	"rook": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_rook.tscn",
	"bishop": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_bishop.tscn",
	"knight": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_knight.tscn",
	"king": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_king.tscn",
	"queen": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_queen.tscn"
	}
	


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# edina koda ki ni vibe codana:
	
	PlayerManager.add_to_active_party("rook")
	PlayerManager.add_to_active_party("pawn")
	
	PlayerManager.add_to_enemy_party("rook")
	PlayerManager.add_to_enemy_party("pawn")
	
	to_spawn_ally = PlayerManager.active_party.duplicate(true)
	to_spawn_enemy = PlayerManager.enemy_party.duplicate(true)
	
	while not to_spawn_ally.is_empty():
		for i in range(0, 12):
			if to_spawn_ally.is_empty():
				break
			var spawn = randi_range(0, 6)
			if spawn == 0 or grid_manager.is_occupied(grid_manager.grid_to_world(Vector2i(i, 0))) or to_spawn_ally.is_empty():
				continue
				
			var piece = to_spawn_ally.pop_at(randi_range(0, PlayerManager.active_party.size() - 1))
			grid_manager.spawn_character(friendly_pieces[piece], grid_manager.grid_to_world(Vector2(i,0)))
			
	for i in range(0, 12):
		for j in range(0, 11):
			var spawn = randi_range(0, 10)
			if spawn == 1:
				var piece = randi_range(0, 5)
				grid_manager.spawn_character(obstacle, grid_manager.grid_to_world(Vector2(i, j)))
	
	while not to_spawn_enemy.is_empty():	
		for i in range(0, 12):
			if to_spawn_enemy.is_empty():
				break
			var spawn = randi_range(0, 6)
			if spawn == 0 or grid_manager.is_occupied(grid_manager.grid_to_world(Vector2i(i, 11))) or to_spawn_enemy.is_empty():
				continue
				
			var piece = to_spawn_enemy.pop_at(randi_range(0, to_spawn_enemy.size() - 1))
			grid_manager.spawn_character(enemy_pieces[piece], grid_manager.grid_to_world(Vector2(i,11)))
				
	

	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
