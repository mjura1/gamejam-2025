# res://Scripts/Data/item_data.gd
# Autoload. Prebere Data/items.json (cene/opisi shop itemov) in
# Data/piece_prices.json (prodajne cene figur), po vzoru ability_data.gd.
extends Node

const ITEMS_PATH := "res://Data/items.json"
const PIECE_PRICES_PATH := "res://Data/piece_prices.json"

# id -> razred (base_item.gd variante) - "1 osnovni razred, variante" vzorec,
# enak pieces sistemu.
const ITEM_SCRIPTS: Dictionary = {
	"extra_move": preload("res://Scripts/Items/extra_move_item.gd"),
}

var _items: Dictionary = {}
var _piece_prices: Dictionary = {}

func _ready():
	_items = _load_json(ITEMS_PATH)
	_piece_prices = _load_json(PIECE_PRICES_PATH)

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
