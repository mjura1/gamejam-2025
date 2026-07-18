# res://Scripts/Data/tutorial_data.gd
# Autoload. Prebere Data/tutorials.json (naslov/opis tutorial stopenj), po
# vzoru item_data.gd. Scene stopenj so registrirane tukaj (id -> PackedScene),
# ker JSON ne more nositi preload-a; per-stage vedenje (npr. AI on/off) je
# lastnost same scene (glej BattleController.ai_enabled).
extends Node

const TUTORIALS_PATH := "res://Data/tutorials.json"

const STAGE_SCENES: Dictionary = {
	"movement": preload("res://Scenes/Tutorial/tutorial_movement.tscn"),
}

var _stages: Array = []

func _ready():
	_stages = _load_json(TUTORIALS_PATH).get("stages", [])

func get_stages() -> Array:
	return _stages

func get_stage_scene(id: String) -> PackedScene:
	return STAGE_SCENES.get(id)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("TutorialData: manjka datoteka %s" % path)
		return {}

	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("TutorialData: neveljaven JSON v %s" % path)
	return {}
