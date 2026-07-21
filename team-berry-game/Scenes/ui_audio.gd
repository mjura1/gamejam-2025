extends Node

@onready var click_player: AudioStreamPlayer = $ClickStreamer
@onready var music_player: AudioStreamPlayer = $MusicStreamer

func _ready() -> void:
	print("ui_audio ready")
	if music_player.stream is AudioStreamMP3:
		music_player.stream.loop = true
	music_player.play()

func play_click() -> void:
	if not click_player.playing:
		click_player.play()
