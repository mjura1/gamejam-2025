extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_start_pressed():
	print("Start pressed")
	# get_tree().change_scene_to_file(path gre sem)

func _on_settings_pressed():
	print("Settings pressed")
	# get_tree().change_scene_to_file(path gre sem)

func _on_exit_pressed():
	print("Exit pressed")
	get_tree().quit()
