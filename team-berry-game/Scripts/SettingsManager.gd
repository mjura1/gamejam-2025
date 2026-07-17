# res://Scripts/SettingsManager.gd (Autoload/Singleton)
# Splošne igralne nastavitve (ločeno od KeybindManager, ki upravlja samo
# preslikave tipk) - trenutno samo "reduced motion" za izklop drsečih
# animacij figur (dostopnost). Shrani/naloži iz user://settings.cfg.
extends Node

signal reduced_motion_changed(enabled: bool)

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

var reduced_motion: bool = false


func _ready():
	load_settings()


func set_reduced_motion(enabled: bool):
	reduced_motion = enabled
	save_settings()
	reduced_motion_changed.emit(reduced_motion)


func load_settings():
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	reduced_motion = cfg.get_value(SECTION, "reduced_motion", false)


func save_settings():
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "reduced_motion", reduced_motion)
	cfg.save(SAVE_PATH)
