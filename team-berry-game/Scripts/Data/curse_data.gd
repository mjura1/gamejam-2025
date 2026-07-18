# res://Scripts/Data/curse_data.gd
# Autoload. Prebere Data/curses.json (ogrodje prekletstev sovražnikov), po
# vzoru item_data.gd ("1 avtoload prebere JSON + registry razredov" vzorec).
# Nosi TUDI Data/ai_config.json (splošni "enemy behavior" podatki - vrednosti
# figur za value-aware capture in danger-avoidance verjetnosti po težavnosti,
# glej base_character.calculate_best_move) - namerno v istem avtoloadu namesto
# ločenega, da ne množimo majhnih JSON-loaderjev za tesno povezane AI podatke.
extends Node

const CURSES_PATH := "res://Data/curses.json"
const AI_CONFIG_PATH := "res://Data/ai_config.json"

# id -> razred (base_curse.gd variante) - "1 osnovni razred, variante" vzorec,
# enak pieces/items sistemu.
const CURSE_SCRIPTS: Dictionary = {
	"snowfall": preload("res://Scripts/Curses/snowfall_curse.gd"),
	"frenzy": preload("res://Scripts/Curses/frenzy_curse.gd"),
	"stunning_gaze": preload("res://Scripts/Curses/stunning_gaze_curse.gd"),
	"blizzard": preload("res://Scripts/Curses/blizzard_curse.gd"),
}

var _config: Dictionary = {}
var _curses: Dictionary = {}
var _ai_config: Dictionary = {}

func _ready():
	var parsed := _load_json(CURSES_PATH)
	_config = parsed.get("config", {})
	_curses = parsed.get("curses", {})
	_ai_config = _load_json(AI_CONFIG_PATH)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("CurseData: manjka datoteka %s" % path)
		return {}

	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("CurseData: neveljaven JSON v %s" % path)
	return {}

func get_curse_ids() -> Array:
	return _curses.keys()

func get_curse_name(id: String) -> String:
	return _curses.get(id, {}).get("name", id)

func get_curse_description(id: String) -> String:
	return _curses.get(id, {}).get("description", "")

func get_param(id: String, key: String, default):
	return _curses.get(id, {}).get(key, default)

func get_color(id: String) -> Color:
	var rgb: Array = _curses.get(id, {}).get("color", [])
	if rgb.size() >= 3:
		return Color(rgb[0], rgb[1], rgb[2])
	return Color.MAGENTA

func get_weight(id: String) -> float:
	return _curses.get(id, {}).get("weight", 0.0)

func get_excluded_pieces(id: String) -> Array:
	return _curses.get(id, {}).get("excluded_pieces", [])

func get_min_floor() -> int:
	return _config.get("min_floor", 2)

func get_curse_chance_base() -> float:
	return _config.get("curse_chance", 0.25)

# curse_chance (osnovna) * uteži za izbrano težavnost (Data/curses.json
# config.difficulty_chance_mult, privzeto normal=1.0).
func get_curse_chance(difficulty: String = "normal") -> float:
	var mults: Dictionary = _config.get("difficulty_chance_mult", {})
	var mult: float = mults.get(difficulty, 1.0)
	return get_curse_chance_base() * mult

# Čista funkcija (testljiva brez RNG/autoload stanja odvisnosti na klicnem
# mestu) - ali naj sovražnik na tem nadstropju sploh dobi met za prekletstvo.
# roll: vnaprej izvlečen randf() [0,1).
func should_curse(current_floor: int, roll: float, difficulty: String = "normal") -> bool:
	if current_floor < get_min_floor():
		return false
	return roll < get_curse_chance(difficulty)

# Zajamčeno minimalno število prekletih sovražnikov na bitko, od get_min_floor()
# naprej (min_floor => 1, min_floor+1 => 2, ... - linearno +1 na nadstropje).
# Pod min_floor je 0 (garancije sploh ni, glej should_curse za enak prag).
func get_min_curse_count(current_floor: int) -> int:
	if current_floor < get_min_floor():
		return 0
	return current_floor - get_min_floor() + 1

func create_curse(id: String) -> BaseCurse:
	if not CURSE_SCRIPTS.has(id):
		return null
	return CURSE_SCRIPTS[id].new()

# Uteženi met med prekletstvi, ki so za ta tip figure sploh dovoljena
# (weight > 0, strName ni v excluded_pieces). "" = nobeno ni na voljo.
# rng parameter zaradi testov (seedable) - ista konvencija kot
# ItemData.roll_shop_stock.
func roll_curse_for(piece_name: String, rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var eligible: Array = []
	var total_weight := 0.0
	for id in get_curse_ids():
		if piece_name in get_excluded_pieces(id):
			continue
		var w := get_weight(id)
		if w <= 0.0:
			continue
		eligible.append(id)
		total_weight += w

	if eligible.is_empty():
		return ""

	var roll := rng.randf() * total_weight
	var acc := 0.0
	for id in eligible:
		acc += get_weight(id)
		if roll < acc:
			return id

	return eligible[eligible.size() - 1]

# ----------------- AI_CONFIG (Data/ai_config.json) -----------------

# Relativna vrednost figure (strName) za value-aware capture (glej
# base_character.calculate_best_move - korak 6, med več hkrati zajemljivimi
# tarčami izbere najvrednejšo). Privzeto 1, če piece_values nima vnosa.
func get_piece_value(piece_name: String) -> int:
	return _ai_config.get("piece_values", {}).get(piece_name, 1)

# Splošen getter za ai_config.json vrednosti po težavnosti (trenutno samo
# "danger_avoid_prob" - verjetnost, da sovražnik pri "chase" koraku raje
# izbere polje izven zavezniškega dosega, glej calculate_best_move korak 7).
func get_ai_param(difficulty: String, key: String, default: float = 0.0) -> float:
	return _ai_config.get(key, {}).get(difficulty, default)
