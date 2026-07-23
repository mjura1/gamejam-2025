# res://Scripts/Data/item_data.gd
# Autoload. Prebere GameParameters/items.json (cene/opisi shop itemov) in
# GameParameters/piece_prices.json (prodajne cene figur), po vzoru ability_data.gd.
extends Node

const ITEMS_PATH := "res://GameParameters/items.json"
const PIECE_PRICES_PATH := "res://GameParameters/piece_prices.json"
const SHOP_CONFIG_PATH := "res://GameParameters/shop_config.json"
const TREASURE_CONFIG_PATH := "res://GameParameters/treasure_config.json"

# Index = power rank, used for "take the better of N rolls" (luck rerolls).
const RARITY_ORDER := ["common", "uncommon", "rare", "epic", "legendary"]

const RARITY_COLORS := {
	"common": Color.WHITE,
	"uncommon": Color(0.4, 0.9, 0.4),
	"rare": Color(0.45, 0.65, 1.0),
	"epic": Color(0.65, 0.4, 0.95),
	"legendary": Color(1.0, 0.65, 0.15),
}

# id -> razred (base_item.gd variante) - "1 osnovni razred, variante" vzorec,
# enak pieces sistemu.
const ITEM_SCRIPTS: Dictionary = {
	"extra_move": preload("res://Scripts/Items/extra_move_item.gd"),
	"barricade": preload("res://Scripts/Items/barricade_item.gd"),
	"flare": preload("res://Scripts/Items/flare_item.gd"),
}

var _items: Dictionary = {}
var _piece_prices: Dictionary = {}
var _shop_config: Dictionary = {}
var _treasure_config: Dictionary = {}

func _ready():
	_items = _load_json(ITEMS_PATH)
	_piece_prices = _load_json(PIECE_PRICES_PATH)
	_shop_config = _load_json(SHOP_CONFIG_PATH)
	_treasure_config = _load_json(TREASURE_CONFIG_PATH)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ItemData: manjka datoteka %s" % path)
		return {}

	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("ItemData: neveljaven JSON v %s" % path)
	return {}

func get_item_ids() -> Array:
	return _items.keys()

func get_item_name(id: String) -> String:
	return _items.get(id, {}).get("name", id)

func get_item_description(id: String) -> String:
	return _items.get(id, {}).get("description", "")

func get_buy_cost(id: String) -> int:
	return _items.get(id, {}).get("buy_cost", 1)

func get_sell_value(id: String) -> int:
	return _items.get(id, {}).get("sell_value", 1)

func get_piece_sell_value(roster_name: String) -> int:
	return _piece_prices.get(roster_name, {}).get("sell_value", 1)

func create_item(id: String) -> BaseItem:
	if not ITEM_SCRIPTS.has(id):
		return null
	return ITEM_SCRIPTS[id].new()

func get_rarity(id: String) -> String:
	return _items.get(id, {}).get("rarity", "common")

func get_kind(id: String) -> String:
	return _items.get(id, {}).get("kind", "consumable")

func get_reward(id: String) -> int:
	return _items.get(id, {}).get("reward", 1)

func get_luck_bonus(id: String) -> int:
	return _items.get(id, {}).get("luck_bonus", 0)

func get_rarity_color(id: String) -> Color:
	return RARITY_COLORS.get(get_rarity(id), Color.WHITE)

func get_ids_by_rarity(rarity: String) -> Array:
	var ids := []
	for id in _items.keys():
		if get_rarity(id) == rarity:
			ids.append(id)
	return ids

func get_ids_by_rarity_and_kinds(rarity: String, kinds: Array) -> Array:
	var ids := []
	for id in _items.keys():
		if get_rarity(id) == rarity and get_kind(id) in kinds:
			ids.append(id)
	return ids

func get_shop_slot_count() -> int:
	return _shop_config.get("slots", 4)

func get_rarity_weights() -> Dictionary:
	return _shop_config.get("rarity_weights", {"common": 1.0})

func get_treasure_rarity_weights(tier: int) -> Dictionary:
	var tables: Array = _treasure_config.get("rarity_weights_by_tier", [])
	if tables.is_empty():
		return {"common": 1.0}
	return tables[clampi(tier, 0, tables.size() - 1)]

# Utežen izbor raritete iz weights, nato uniformen item te raritete v klicalcu.
func _weighted_rarity_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total_weight := 0.0
	for w in weights.values():
		total_weight += w

	var roll := rng.randf() * total_weight
	var chosen_rarity: String = weights.keys()[0]
	var acc := 0.0
	for rarity in weights.keys():
		acc += weights[rarity]
		if roll < acc:
			chosen_rarity = rarity
			break
	return chosen_rarity

# Neodvisen met za vsak slot: najprej rariteta po utežeh, nato uniformen item
# te raritete. rng parameter zaradi testov (seedable); null -> nov RNG.
func roll_shop_stock(rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var weights: Dictionary = get_rarity_weights()
	# Odstrani rariteta, ki nimajo nobenega itema (renormaliziraj nad ostalimi).
	var usable_weights: Dictionary = {}
	for rarity in weights.keys():
		if get_ids_by_rarity_and_kinds(rarity, ["consumable", "passive"]).size() > 0:
			usable_weights[rarity] = weights[rarity]

	var stock: Array = []
	if usable_weights.is_empty():
		return stock

	for i in range(get_shop_slot_count()):
		var chosen_rarity := _weighted_rarity_pick(usable_weights, rng)
		var ids_of_rarity := get_ids_by_rarity_and_kinds(chosen_rarity, ["consumable", "passive"])
		var chosen_id: String = ids_of_rarity[rng.randi_range(0, ids_of_rarity.size() - 1)]
		stock.append(chosen_id)

	return stock

# "Luck = najboljši od 1+rerolls neodvisnih utežnih metov" - preprost advantage-roll
# vzorec, lahko testiran z seeded rng.
func roll_treasure_loot(tier: int, luck: int, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var weights := get_treasure_rarity_weights(tier)
	var usable_weights := {}
	for rarity in weights.keys():
		if get_ids_by_rarity_and_kinds(rarity, ["consumable", "passive", "artifact"]).size() > 0:
			usable_weights[rarity] = weights[rarity]
	if usable_weights.is_empty():
		return []

	var rerolls: int = clampi(luck / int(_treasure_config.get("luck_per_reroll", 2)),
		0, int(_treasure_config.get("max_rerolls", 3)))
	var bonus_items: int = clampi(luck / int(_treasure_config.get("luck_per_bonus_item", 3)),
		0, int(_treasure_config.get("max_bonus_items", 2)))
	var item_count: int = int(_treasure_config.get("base_item_count", 1)) + bonus_items

	var loot: Array = []
	for i in range(item_count):
		var rarity := _roll_best_rarity(usable_weights, rerolls, rng)
		var ids := get_ids_by_rarity_and_kinds(rarity, ["consumable", "passive", "artifact"])
		loot.append(ids[rng.randi_range(0, ids.size() - 1)])
	return loot

func _roll_best_rarity(weights: Dictionary, rerolls: int, rng: RandomNumberGenerator) -> String:
	var best := ""
	var best_rank := -1
	for i in range(1 + rerolls):
		var candidate: String = _weighted_rarity_pick(weights, rng)
		var rank: int = RARITY_ORDER.find(candidate)
		if rank > best_rank:
			best_rank = rank
			best = candidate
	return best
