extends Control

# POPRAVEK: Izbrisana je bila neuporabna konstanta GF = preload(...).
# Godot Autoload Singletonu dostopamo neposredno preko imena, ki ste mu ga dali 
# v Project Settings (predpostavimo, da je to globalno ime 'GF').

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Preverjanje za debug: Prepričamo se, da je GF dostopen ob zagonu
	if not is_instance_valid(GF):
		push_error("NAPAKA: GF (GameFlow) Singleton ni pravilno nastavljen ali ni dostopen.")
	pass 

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_start_pressed():
	print("Start pressed. Sprožam zagon igre...")
	
	# KLJUČNO: Kličemo funkcijo na ŽIVI INSTANCI Singletona,
	# ki prevzame nadzor in naloži Mapo.
	GF.start_new_game()

func _on_settings_pressed():
	print("Settings pressed")
	# get_tree().change_scene_to_file(path gre sem)

func _on_exit_pressed():
	print("Exit pressed")
	get_tree().quit()
