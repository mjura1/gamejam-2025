extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	hide()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pauseGame()

func resume():
	$AnimationPlayer.play_backwards("blur")
	await $AnimationPlayer.animation_finished
	hide()
	get_tree().paused = false

func pause():
	show()
	get_tree().paused = true
	$AnimationPlayer.play("blur")

func pauseGame():
	if not GF.game_initialized:
		return
	if Input.is_action_just_pressed("escape"):
		if get_tree().paused:
			resume()
		else:
			pause()


func _on_button_pressed() -> void:
	resume()

func _on_button_2_pressed() -> void:
	GF.return_to_main_menu()

func _on_button_3_pressed() -> void:
	get_tree().quit()
