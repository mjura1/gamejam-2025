extends Control

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Preverjanje za debug: Prepričamo se, da je GF dostopen ob zagonu
	if not is_instance_valid(GF):
		push_error("NAPAKA: GF (GameFlow) Singleton ni pravilno nastavljen ali ni dostopen.")
	for button in get_tree().get_nodes_in_group("buttons"):
		button.pressed.connect(_on_button_pressed)

func _on_button_pressed():
	UiAudio.play_click()
	print("predvajam zvok")

func _on_start_pressed():
	print("Start pressed. Sprožam zagon igre...")
	PlayerManager.setStarting()
	# KLJUČNO: Kličemo funkcijo na ŽIVI INSTANCI Singletona,
	# ki prevzame nadzor in naloži Mapo.
	GF.start_new_game()

func _on_settings_pressed():
	print("Settings pressed")
	# get_tree().change_scene_to_file(path gre sem)

func _on_exit_pressed():
	print("Exit pressed")
	get_tree().quit()
