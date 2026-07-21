# res://Scripts/MetaProgress.gd (Autoload/Singleton)
# Trajno sledenje "ali je igralec že videl tutorial mapo" med zagoni igre
# (glej plans/TUTORIAL_MAP_PLAN.md) - isti ConfigFile vzorec kot
# SettingsManager.gd/KeybindManager.gd. Shrani/naloži iz user://progress.cfg.
extends Node

const SAVE_PATH := "user://progress.cfg"
const SECTION := "progress"

# True po SKIPU ALI dokončanju tutorial mape - zapre auto-trigger ob naslednjem
# start_new_game(), ne glede na to, ali je igralec nagrado sploh prislužil.
var tutorial_seen: bool = false
# True SAMO po pravem dokončanju (ne skip) - odklene trajni +pawn+rook bonus
# v PlayerManager.setStarting(). Ločen od tutorial_seen namerno: skip ne sme
# podariti nagrade, a mora vseeno preprečiti ponovno prikazovanje tutoriala.
var tutorial_reward_granted: bool = false


func _ready():
	load_progress()


func mark_tutorial_skipped() -> void:
	tutorial_seen = true
	save_progress()


func mark_tutorial_completed() -> void:
	tutorial_seen = true
	tutorial_reward_granted = true
	save_progress()


func load_progress():
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	tutorial_seen = cfg.get_value(SECTION, "tutorial_seen", false)
	tutorial_reward_granted = cfg.get_value(SECTION, "tutorial_reward_granted", false)


func save_progress():
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "tutorial_seen", tutorial_seen)
	cfg.set_value(SECTION, "tutorial_reward_granted", tutorial_reward_granted)
	cfg.save(SAVE_PATH)
