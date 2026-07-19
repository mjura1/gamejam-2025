# res://Scripts/Data/curse_data.gd
# Autoload. Prebere GameParameters/curses.json (ogrodje prekletstev sovražnikov), po
# vzoru item_data.gd ("1 avtoload prebere JSON + registry razredov" vzorec).
# Nosi TUDI GameParameters/ai_config.json (figur vrednosti za value-aware capture,
# glej base_character.calculate_best_move in Scripts/AI/enemy_ai_strategy.gd) -
# namerno v istem avtoloadu namesto ločenega, da ne množimo majhnih JSON-loaderjev
# za tesno povezane AI podatke. Difficulty-gated AI PARAMETRI (danger_avoid_prob
# ipd.) so se preselili v Scripts/Data/ai_strategy_data.gd + GameParameters/
# ai_difficulty.json (SettingsManager.ai_difficulty - ločena os od curse-difficulty,
# glej plans/AI_DIFFICULTY_PLAN.md).
extends Node

const CURSES_PATH := "res://GameParameters/curses.json"
const AI_CONFIG_PATH := "res://GameParameters/ai_config.json"

# id -> razred (base_curse.gd variante) - "1 osnovni razred, variante" vzorec,
# enak pieces/items sistemu.
const CURSE_SCRIPTS: Dictionary = {
	"snowfall": preload("res://Scripts/Curses/snowfall_curse.gd"),
	"frenzy": preload("res://Scripts/Curses/frenzy_curse.gd"),
	"stunning_gaze": preload("res://Scripts/Curses/stunning_gaze_curse.gd"),
	"blizzard": preload("res://Scripts/Curses/blizzard_curse.gd"),
	"fey_step": preload("res://Scripts/Curses/fey_step_curse.gd"),
	"changeling": preload("res://Scripts/Curses/changeling_curse.gd"),
	"abduction": preload("res://Scripts/Curses/abduction_curse.gd"),
	"entangle": preload("res://Scripts/Curses/entangle_curse.gd"),
	"wraith_cloak": preload("res://Scripts/Curses/wraith_cloak_curse.gd"),
	"contagion": preload("res://Scripts/Curses/contagion_curse.gd"),
	"bloodlust": preload("res://Scripts/Curses/bloodlust_curse.gd"),
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

# difficulty-aware: falls back to the base "weight"/"excluded_pieces" unless the
# curse defines a "weight_by_difficulty"/"excluded_pieces_by_difficulty" override
# for this exact difficulty (see GameParameters/curses.json root-level comments).
func get_weight(id: String, difficulty: String = "normal") -> float:
	var curse: Dictionary = _curses.get(id, {})
	var overrides: Dictionary = curse.get("weight_by_difficulty", {})
	return overrides.get(difficulty, curse.get("weight", 0.0))

func get_excluded_pieces(id: String, difficulty: String = "normal") -> Array:
	var curse: Dictionary = _curses.get(id, {})
	var overrides: Dictionary = curse.get("excluded_pieces_by_difficulty", {})
	return overrides.get(difficulty, curse.get("excluded_pieces", []))

# min_floor je zdaj PO MAPNEM NIVOJU (GameParameters/curses.json config.tier_min_floor -
# array, indeksiran kot tier_curse_chance_mult/MapGenerator.TIER_CONFIGS: 0/1/2 = Tier 0/1/2).
# Nižja vrednost = prekletstva se pojavijo prej (pri manjši globini sobe). Za tier NAD
# zadnjim indeksom (infinite način) config.infinite_mode.min_floor_decrement_per_tier
# učinkovit prag še naprej znižuje, navzdol omejeno z min_floor_clamp - tako se v
# neskončnem napredovanju prekletstva pojavijo tudi vedno prej, ne samo vedno več.
# current_map_tier privzeto 0, da klici brez njega (obstoječi klicatelji/testi)
# ostanejo nespremenjeni.
func get_min_floor(current_map_tier: int = 0) -> int:
	var tiers: Array = _config.get("tier_min_floor", [2])
	var base_floor: int = 2
	if not tiers.is_empty():
		base_floor = tiers[clampi(current_map_tier, 0, tiers.size() - 1)]

	var inf: Dictionary = _config.get("infinite_mode", {})
	var base_tier: int = inf.get("base_tier", 2)
	var decrement: int = inf.get("min_floor_decrement_per_tier", 0)
	var floor_clamp: int = inf.get("min_floor_clamp", 0)

	var effective_floor := base_floor - maxi(0, current_map_tier - base_tier) * decrement
	return maxi(floor_clamp, effective_floor)

func get_curse_chance_base() -> float:
	return _config.get("curse_chance", 0.25)

# Uteži na naključno prekletstveno možnost PO MAPNEM NIVOJU (0-2, GameParameters/curses.json
# config.tier_curse_chance_mult - array, indeksiran kot MapGenerator.TIER_CONFIGS).
# current_map_tier nad zadnjim indeksom se sponi na zadnjega (glej get_infinite_curse_chance_bonus
# za dejansko infinite-mode rast NAD tem).
func get_tier_curse_chance_mult(current_map_tier: int) -> float:
	var mults: Array = _config.get("tier_curse_chance_mult", [1.0])
	if mults.is_empty():
		return 1.0
	var idx: int = clampi(current_map_tier, 0, mults.size() - 1)
	return mults[idx]

# Enak razlog kot get_infinite_tier_curse_bonus (glej spodaj) - v infinite načinu
# current_map_tier raste brez konca, mapa pa se za tier > base_tier ne spremeni,
# zato mora VERJETNOST prekletstva prav tako naprej rasti od nekod (GameParameters/curses.json
# config.infinite_mode.curse_chance_increment_per_tier na tier nad base_tier).
func get_infinite_curse_chance_bonus(current_map_tier: int) -> float:
	var inf: Dictionary = _config.get("infinite_mode", {})
	var base_tier: int = inf.get("base_tier", 2)
	var per_tier: float = inf.get("curse_chance_increment_per_tier", 0.0)
	return maxf(0.0, float(current_map_tier - base_tier)) * per_tier

# curse_chance (osnovna) * uteži za izbrano težavnost (GameParameters/curses.json
# config.difficulty_chance_mult, privzeto normal=1.0) * uteži za mapni nivo
# (config.tier_curse_chance_mult), plus infinite-mode prirastek nad base_tier -
# skupaj omejeno z config.infinite_mode.max_curse_chance (privzeto 1.0).
func get_curse_chance(difficulty: String = "normal", current_map_tier: int = 0) -> float:
	var mults: Dictionary = _config.get("difficulty_chance_mult", {})
	var mult: float = mults.get(difficulty, 1.0)
	var chance := get_curse_chance_base() * mult * get_tier_curse_chance_mult(current_map_tier)
	chance += get_infinite_curse_chance_bonus(current_map_tier)
	var max_chance: float = _config.get("infinite_mode", {}).get("max_curse_chance", 1.0)
	return minf(chance, max_chance)

# Čista funkcija (testljiva brez RNG/autoload stanja odvisnosti na klicnem
# mestu) - ali naj sovražnik na tem nadstropju sploh dobi met za prekletstvo.
# roll: vnaprej izvlečen randf() [0,1). current_map_tier privzeto 0, da klici
# brez njega (obstoječi klicatelji/testi) ostanejo nespremenjeni.
func should_curse(current_floor: int, roll: float, difficulty: String = "normal", current_map_tier: int = 0) -> bool:
	if current_floor < get_min_floor(current_map_tier):
		return false
	return roll < get_curse_chance(difficulty, current_map_tier)

# Koliko dodatnih zajamčenih prekletstev prinese vsak nivo sobe (current_floor)
# od get_min_floor() naprej (GameParameters/curses.json config.min_curse_count_per_room,
# privzeto 1 - obnaša se enako kot prejšnja trdo kodirana "+1 na nadstropje").
func get_min_curse_count_per_room() -> int:
	return _config.get("min_curse_count_per_room", 1)

# GameParameters/curses.json config.infinite_mode: MapGenerator.TIER_CONFIGS ima samo
# vnose za tier 0-2 (glej _configure_tier - clampi na zadnji vnos), zato mapa sama
# po sebi za tier > base_tier ne postane nič težja, čeprav current_map_tier v
# infinite načinu še naprej narašča. To doda dodatna zajamčena prekletstva za
# vsak tier NAD base_tier (privzeto 2), da igra ostane težja tudi v neskončnem
# napredovanju - navzgor omejeno z max_curse_count (-1 = brez omejitve).
func get_infinite_tier_curse_bonus(current_map_tier: int) -> int:
	var inf: Dictionary = _config.get("infinite_mode", {})
	var base_tier: int = inf.get("base_tier", 2)
	var per_tier: int = inf.get("curse_count_per_tier", 0)
	return maxi(0, current_map_tier - base_tier) * per_tier

# Zajamčeno minimalno število prekletih sovražnikov na bitko, od get_min_floor()
# naprej (min_floor => 1 * min_curse_count_per_room, min_floor+1 => 2 * ..., ...),
# plus get_infinite_tier_curse_bonus() za current_map_tier (glej zgoraj) - skupaj
# omejeno z config.infinite_mode.max_curse_count, če je nastavljen (>= 0).
# Pod min_floor je 0 (garancije sploh ni, glej should_curse za enak prag).
# current_map_tier privzeto 0, is_boss_floor/is_mini_boss_floor privzeto false,
# da klici brez njih (obstoječi klicatelji/testi) ostanejo nespremenjeni.
#
# Boss/mini-boss bitke so posebne, redke bitke (1 na mapo/tier) - namesto
# izpeljanega števila po globini sobe uporabijo FIKSNO število iz
# GameParameters/curses.json config.boss_curse_count / mini_boss_curse_count
# (is_boss_floor ima prednost, če bi bila oba hkrati true).
func get_min_curse_count(current_floor: int, current_map_tier: int = 0, is_boss_floor: bool = false, is_mini_boss_floor: bool = false) -> int:
	if is_boss_floor:
		return get_boss_curse_count()
	if is_mini_boss_floor:
		return get_mini_boss_curse_count()
	var min_floor := get_min_floor(current_map_tier)
	if current_floor < min_floor:
		return 0
	var count := (current_floor - min_floor + 1) * get_min_curse_count_per_room()
	count += get_infinite_tier_curse_bonus(current_map_tier)
	var max_count: int = _config.get("infinite_mode", {}).get("max_curse_count", -1)
	if max_count >= 0:
		count = mini(count, max_count)
	return count

func get_boss_curse_count() -> int:
	return _config.get("boss_curse_count", 1)

func get_mini_boss_curse_count() -> int:
	return _config.get("mini_boss_curse_count", 1)

func create_curse(id: String) -> BaseCurse:
	if not CURSE_SCRIPTS.has(id):
		return null
	return CURSE_SCRIPTS[id].new()

# Uteženi met med prekletstvi, ki so za ta tip figure sploh dovoljena
# (weight > 0, strName ni v excluded_pieces). "" = nobeno ni na voljo.
# rng parameter zaradi testov (seedable) - ista konvencija kot
# ItemData.roll_shop_stock. difficulty izbere weight_by_difficulty/
# excluded_pieces_by_difficulty override (glej get_weight/get_excluded_pieces
# zgoraj), privzeto "normal" da klici brez njega ostanejo nespremenjeni.
func roll_curse_for(piece_name: String, rng: RandomNumberGenerator = null, difficulty: String = "normal") -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var eligible: Array = []
	var total_weight := 0.0
	for id in get_curse_ids():
		if piece_name in get_excluded_pieces(id, difficulty):
			continue
		var w := get_weight(id, difficulty)
		if w <= 0.0:
			continue
		eligible.append(id)
		total_weight += w

	if eligible.is_empty():
		return ""

	var roll := rng.randf() * total_weight
	var acc := 0.0
	for id in eligible:
		acc += get_weight(id, difficulty)
		if roll < acc:
			return id

	return eligible[eligible.size() - 1]

# ----------------- AI_CONFIG (GameParameters/ai_config.json) -----------------

# Relativna vrednost figure (strName) za value-aware capture (glej
# base_character.calculate_best_move - korak 6, med več hkrati zajemljivimi
# tarčami izbere najvrednejšo). Privzeto 1, če piece_values nima vnosa.
func get_piece_value(piece_name: String) -> int:
	return _ai_config.get("piece_values", {}).get(piece_name, 1)
