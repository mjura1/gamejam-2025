extends Node

@onready var grid_manager = $GridManager

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	grid_manager.spawn_character("res://Scenes/CharacterPiecesNodes/Neutral/House.tscn", Vector2(24,24))
	grid_manager.spawn_character("res://Scenes/CharacterPiecesNodes/Ally/pawn.tscn", Vector2(40,40))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
