# res://Scenes/Tutorial/tutorial_movement.gd
# Root script tutorial stopnje "Moving & Capturing". Ista naloga kot
# test_sandbox.gd (ročno postavljene figure -> registracija + start bitke),
# plus dvoje, česar sandbox ne potrebuje:
#  - PlayerManager actives morajo zrcaliti ročno postavljeno ploščo: sem
#    pridemo iz menija, brez runa, torej resetActives() ni bil klican in
#    check_battle_end() bi ob praznem active_enemies/active_party takoj
#    sprožil victory/defeat vejo, ki nima mape za vrnitev.
#  - "tutorial_keepalive" vnos poskrbi, da enemyGone() nikoli ne postane
#    true, tudi ko igralec zajame oba kmeta - stopnja se zapusti IZKLJUČNO
#    prek BACK gumba (GF.return_to_tutorial_hub), ne prek battle flowa.
extends Node

@onready var grid_manager = $GridManager
@onready var battle_controller = $BattleController

func _ready() -> void:
	var party: Array[String] = ["friendly_king", "friendly_queen"]
	var enemies: Array[String] = ["enemy_pawn", "enemy_pawn", "tutorial_keepalive"]
	PlayerManager.active_party = party
	PlayerManager.active_enemies = enemies
	PlayerManager.dead_party.clear()

	if is_instance_valid(grid_manager):
		grid_manager.register_all_characters_in_scene()

	if is_instance_valid(battle_controller):
		battle_controller.initialize_battle()

func _on_back_pressed() -> void:
	UiAudio.play_click()
	GF.return_to_tutorial_hub()
