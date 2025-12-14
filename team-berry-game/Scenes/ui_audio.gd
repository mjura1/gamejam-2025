extends Node

@onready var click_player: AudioStreamPlayer = $ClickStreamer

func _ready() -> void:
	print("ui_audio ready")

func play_click() -> void:
	if not click_player.playing:
		click_player.play()
