extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func resume():
	get_tree().paused = false
	$AnimationPlayer.play("blur")	

func pause():
	get_tree().paused = true

func pauseGame():
	if Input.is_action_just_pressed("escape") and get_tree().paused == false:
		pause()
	elif Input.is_action_just_pressed("escape") and get_tree().paused == true:
		resume()



func _on_button_pressed() -> void:
	print("Resume")
	resume()

func _on_button_2_pressed() -> void:
	print("Main menu")
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")

func _on_button_3_pressed() -> void:
	print("Quit game")
	get_tree().quit()
