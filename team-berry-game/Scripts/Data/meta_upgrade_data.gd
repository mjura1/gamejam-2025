# res://Scripts/Data/meta_upgrade_data.gd
# Autoload. Prebere GameParameters/meta_upgrades.json (flat seznam trajnih
# nadgradenj - shema zrcali skill_trees.json, glej Scripts/Data/skill_tree_data.gd),
# GameParameters/meta_upgrade_levels.json (cena/max_level na nadgradnjo - ločeno
# od zgornje datoteke, ker se lahko balansira neodvisno od efekta/require) in
# GameParameters/meta_progression.json (konfiguracija formule za točke na bitko).
# Glej plans/META_PROGRESSION_PLAN.md §2c/§3 M1.
extends Node

const UPGRADES_PATH := "res://GameParameters/meta_upgrades.json"
const LEVELS_PATH := "res://GameParameters/meta_upgrade_levels.json"
const SCORING_PATH := "res://GameParameters/meta_progression.json"

var _upgrades: Array = []
var _levels: Dictionary = {}
var _scoring_config: Dictionary = {}

func _ready():
	_upgrades = _load_json(UPGRADES_PATH)
	_levels = _load_json(LEVELS_PATH)
	_scoring_config = _load_json(SCORING_PATH)

func _load_json(path: String):
	if not FileAccess.file_exists(path):
		push_error("MetaUpgradeData: manjka datoteka %s" % path)
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed

func get_upgrades() -> Array:
	return _upgrades

func get_upgrade_def(id: String) -> Dictionary:
	for def in _upgrades:
		if def.get("id", "") == id:
			return def
	return {}

func get_level_def(id: String) -> Dictionary:
	return _levels.get(id, {})

# -1 pomeni "infinite" (brez zgornje meje - glej meta_upgrade_levels.json).
func get_max_level(id: String) -> int:
	return int(get_level_def(id).get("max_level", 1))

func is_infinite_upgrade(id: String) -> bool:
	return get_max_level(id) < 0

# Cena za NASLEDNJI nakup, glede na trenutni level (0 = še ni kupljeno).
# Linearna rast (base_cost + cost_growth * current_level) - namerno preprosta,
# izogne se float zaokroževanju multiplikativne rasti za gamejam obseg.
func get_cost_for_level(id: String, current_level: int) -> int:
	var def := get_level_def(id)
	var base_cost: int = int(def.get("base_cost", 0))
	var cost_growth: int = int(def.get("cost_growth", 0))
	return base_cost + cost_growth * current_level

# Čista funkcija (vsi vhodi kot parametri, nič se ne bere iz PlayerManager/
# MetaProgress neposredno) - namerno, da je trivialno enotno testirana s
# sintetičnimi vhodi (glej tests/unit/test_meta_progression.gd).
func calculate_battle_points(depth: int, enemy_count: int, turns: int, flawless: bool,
		final_boss_beaten: bool) -> int:
	var points: float = float(_scoring_config.get("base_points_per_battle", 100))
	if flawless:
		points *= float(_scoring_config.get("flawless_multiplier", 1.5))
	points += float(_scoring_config.get("points_per_floor_depth", 10)) * depth
	points += float(_scoring_config.get("points_per_enemy", 15)) * enemy_count
	var turn_cap: int = int(_scoring_config.get("fast_win_turn_cap", 20))
	points += maxf(0.0, turn_cap - turns) * float(_scoring_config.get("fast_win_points_per_turn", 2))
	var scale: float = float(_scoring_config.get("post_clear_points_scale", 1.0))
	if not final_boss_beaten:
		scale = float(_scoring_config.get("pre_clear_points_scale", 0.15))
	points *= scale
	return int(points)
