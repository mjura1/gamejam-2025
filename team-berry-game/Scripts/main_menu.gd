extends Control

const SETTINGS_MENU_SCENE = preload("res://Scenes/Menu/settings_menu.tscn")

var _settings_instance: Control = null

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
	if is_instance_valid(_settings_instance):
		return
	_settings_instance = SETTINGS_MENU_SCENE.instantiate()
	_settings_instance.back_pressed.connect(_on_settings_back)
	add_child(_settings_instance)
	$VBoxContainer.hide()
	$Title.hide()


func _on_settings_back():
	if is_instance_valid(_settings_instance):
		_settings_instance.queue_free()
	_settings_instance = null
	$VBoxContainer.show()
	$Title.show()

func _on_exit_pressed():
	print("Exit pressed")
	get_tree().quit()
