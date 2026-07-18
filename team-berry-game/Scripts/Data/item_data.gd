# res://Scripts/Data/item_data.gd
# Autoload. Prebere Data/items.json (cene/opisi shop itemov) in
# Data/piece_prices.json (prodajne cene figur), po vzoru ability_data.gd.
extends Node

const ITEMS_PATH := "res://Data/items.json"
const PIECE_PRICES_PATH := "res://Data/piece_prices.json"
const SHOP_CONFIG_PATH := "res://Data/shop_config.json"

# id -> razred (base_item.gd variante) - "1 osnovni razred, variante" vzorec,
# enak pieces sistemu.
const ITEM_SCRIPTS: Dictionary = {
	"extra_move": preload("res://Scripts/Items/extra_move_item.gd"),
}

var _items: Dictionary = {}
var _piece_prices: Dictionary = {}
var _shop_config: Dictionary = {}

func _ready():
	_items = _load_json(ITEMS_PATH)
	_piece_prices = _load_json(PIECE_PRICES_PATH)
	_shop_config = _load_json(SHOP_CONFIG_PATH)

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

func get_ids_by_rarity(rarity: String) -> Array:
	var ids := []
	for id in _items.keys():
		if get_rarity(id) == rarity:
			ids.append(id)
	return ids

func get_shop_slot_count() -> int:
	return _shop_config.get("slots", 4)

func get_rarity_weights() -> Dictionary:
	return _shop_config.get("rarity_weights", {"common": 1.0})

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
		if get_ids_by_rarity(rarity).size() > 0:
			usable_weights[rarity] = weights[rarity]

	var stock: Array = []
	if usable_weights.is_empty():
		return stock

	var total_weight := 0.0
	for w in usable_weights.values():
		total_weight += w

	for i in range(get_shop_slot_count()):
		var roll := rng.randf() * total_weight
		var chosen_rarity: String = usable_weights.keys()[0]
		var acc := 0.0
		for rarity in usable_weights.keys():
			acc += usable_weights[rarity]
			if roll < acc:
				chosen_rarity = rarity
				break
		var ids_of_rarity := get_ids_by_rarity(chosen_rarity)
		var chosen_id: String = ids_of_rarity[rng.randi_range(0, ids_of_rarity.size() - 1)]
		stock.append(chosen_id)

	return stock
