# res://Scripts/SettingsManager.gd (Autoload/Singleton)
# Splošne igralne nastavitve (ločeno od KeybindManager, ki upravlja samo
# preslikave tipk) - "reduced motion" za izklop drsečih animacij figur
# (dostopnost), "difficulty" (curse CHANCE only, glej CurseData.get_curse_chance)
# in "ai_difficulty" (enemy move/capture DECISION-MAKING, glej
# AiStrategyData/EnemyAIStrategy in base_character.calculate_best_move) - dve
# NAMENOMA neodvisni osi, glej plans/AI_DIFFICULTY_PLAN.md §2.1. Shrani/naloži
# iz user://settings.cfg.
extends Node

signal reduced_motion_changed(enabled: bool)

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

const VALID_DIFFICULTIES := ["easy", "normal", "hard"]
const VALID_AI_DIFFICULTIES := ["normal", "hard", "extreme", "impossible"]

var reduced_motion: bool = false
var difficulty: String = "normal"
var ai_difficulty: String = "normal"


func _ready():
	load_settings()


func set_reduced_motion(enabled: bool):
	reduced_motion = enabled
	save_settings()
	reduced_motion_changed.emit(reduced_motion)


func set_difficulty(value: String):
	if value not in VALID_DIFFICULTIES:
		return
	difficulty = value
	save_settings()


func set_ai_difficulty(value: String):
	if value not in VALID_AI_DIFFICULTIES:
		return
	ai_difficulty = value
	save_settings()


func load_settings():
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	reduced_motion = cfg.get_value(SECTION, "reduced_motion", false)
	var loaded_difficulty: String = cfg.get_value(SECTION, "difficulty", "normal")
	difficulty = loaded_difficulty if loaded_difficulty in VALID_DIFFICULTIES else "normal"
	var loaded_ai_difficulty: String = cfg.get_value(SECTION, "ai_difficulty", "normal")
	ai_difficulty = loaded_ai_difficulty if loaded_ai_difficulty in VALID_AI_DIFFICULTIES else "normal"


func save_settings():
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "reduced_motion", reduced_motion)
	cfg.set_value(SECTION, "difficulty", difficulty)
	cfg.set_value(SECTION, "ai_difficulty", ai_difficulty)
	cfg.save(SAVE_PATH)
