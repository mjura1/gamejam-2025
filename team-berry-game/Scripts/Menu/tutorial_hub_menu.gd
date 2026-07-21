# res://Scripts/Menu/tutorial_hub_menu.gd
# Hub s seznamom tutorial stopenj. Prava scena, ne overlay (glej
# GF.start_tutorial_hub) - stopnja je battle-like scena, po njej se hub
# zgradi na novo. Vrstice se zgradijo ob zagonu iz TutorialData
# (GameParameters/tutorials.json); PLAY zažene stopnjo prek GF.start_tutorial_stage.
extends Control

@onready var rows_container: VBoxContainer = %RowsContainer

func _ready():
	for stage in TutorialData.get_stages():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		var title := Label.new()
		title.text = stage["title"]
		title.custom_minimum_size = Vector2(200, 0)
		var desc := Label.new()
		desc.text = stage["description"]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(400, 0)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var play_button := Button.new()
		play_button.text = "PLAY"
		play_button.pressed.connect(_on_stage_pressed.bind(stage["id"]))
		row.add_child(title)
		row.add_child(desc)
		row.add_child(play_button)
		rows_container.add_child(row)

	# NOVO: Replay vstop za tutorial MAPO (glej plans/TUTORIAL_MAP_PLAN.md M6) -
	# ni TutorialData stopnja (ni v tutorials.json, gre skozi Map->Battle kot
	# pravi mini-run), zato je vrstica hardcoded tu namesto zgrajena iz zanke.
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 20)
	var map_title := Label.new()
	map_title.text = "The Chessboard"
	map_title.custom_minimum_size = Vector2(200, 0)
	var map_desc := Label.new()
	map_desc.text = "Replay the guided first map - recruiting, fighting, items, and the shop."
	map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_desc.custom_minimum_size = Vector2(400, 0)
	map_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var map_play_button := Button.new()
	map_play_button.text = "PLAY"
	map_play_button.pressed.connect(_on_replay_tutorial_map_pressed)
	map_row.add_child(map_title)
	map_row.add_child(map_desc)
	map_row.add_child(map_play_button)
	rows_container.add_child(map_row)

func _on_stage_pressed(stage_id: String):
	UiAudio.play_click()
	GF.start_tutorial_stage(TutorialData.get_stage_scene(stage_id))

func _on_replay_tutorial_map_pressed():
	UiAudio.play_click()
	GF.replay_tutorial_map()

func _on_back_pressed():
	UiAudio.play_click()
	GF.return_to_main_menu()
