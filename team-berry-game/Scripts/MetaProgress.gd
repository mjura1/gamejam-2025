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

# True po prvi zmagi nad pravim final bossom (tier-2 King) - odklene Legacy
# gumb na mode-select. Mode-agnostic (glej GameFlow._on_victory_continue_pressed):
# v Classic to je zmaga, ki konča run; v Infinite je to prva tier-2+ boss zmaga.
var final_boss_beaten: bool = false
# Trajna valuta ("Legacy Points"), nabira se čez VSE rune, tudi pred prvim
# final_boss_beaten (samo počasneje - glej MetaUpgradeData.calculate_battle_points).
var legacy_points: int = 0
# id (iz GameParameters/meta_upgrades.json) -> true. Ločeno od piece_upgrades/
# owned_items v PlayerManager - to je TRAJNO stanje, ne resetira se v setStarting().
var unlocked_upgrades: Dictionary = {}


func _ready():
	load_progress()


func mark_tutorial_skipped() -> void:
	tutorial_seen = true
	save_progress()


func mark_tutorial_completed() -> void:
	tutorial_seen = true
	tutorial_reward_granted = true
	save_progress()


func mark_final_boss_beaten() -> void:
	if final_boss_beaten:
		return
	final_boss_beaten = true
	save_progress()


func add_legacy_points(amount: int) -> void:
	if amount <= 0:
		return
	legacy_points += amount
	save_progress()


func has_upgrade(id: String) -> bool:
	return unlocked_upgrades.has(id)


# Zrcali PlayerManager.can_buy_node/try_buy_node proti SkillTreeData (glej
# plans/META_PROGRESSION_PLAN.md §2c) natanko - tu porabimo legacy_points
# namesto upgrade_items, pišemo v unlocked_upgrades namesto piece_upgrades.
func can_buy_upgrade(id: String) -> bool:
	if id == "" or has_upgrade(id):
		return false
	var def: Dictionary = MetaUpgradeData.get_upgrade_def(id)
	if def.is_empty():
		return false
	for req in def.get("requires", []):
		if not has_upgrade(req):
			return false
	for excl in def.get("excludes", []):
		if has_upgrade(excl):
			return false
	return legacy_points >= int(def.get("cost", 0))


func try_buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	var def: Dictionary = MetaUpgradeData.get_upgrade_def(id)
	legacy_points -= int(def.get("cost", 0))
	unlocked_upgrades[id] = true
	save_progress()
	return true


func load_progress():
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	tutorial_seen = cfg.get_value(SECTION, "tutorial_seen", false)
	tutorial_reward_granted = cfg.get_value(SECTION, "tutorial_reward_granted", false)
	final_boss_beaten = cfg.get_value(SECTION, "final_boss_beaten", false)
	legacy_points = cfg.get_value(SECTION, "legacy_points", 0)
	unlocked_upgrades = cfg.get_value(SECTION, "unlocked_upgrades", {})


func save_progress():
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "tutorial_seen", tutorial_seen)
	cfg.set_value(SECTION, "tutorial_reward_granted", tutorial_reward_granted)
	cfg.set_value(SECTION, "final_boss_beaten", final_boss_beaten)
	cfg.set_value(SECTION, "legacy_points", legacy_points)
	cfg.set_value(SECTION, "unlocked_upgrades", unlocked_upgrades)
	cfg.save(SAVE_PATH)
