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
	"snowshoes": preload("res://Scripts/Items/snowshoes_item.gd"),
	"warhorn": preload("res://Scripts/Items/warhorn_item.gd"),
	"bastion": preload("res://Scripts/Items/bastion_item.gd"),
	"wildfire_flare": preload("res://Scripts/Items/wildfire_flare_item.gd"),
	"aurora_flare": preload("res://Scripts/Items/aurora_flare_item.gd"),
	# Artefakt, ne consumable - glej frozen_rampart_item.gd/battle_ui.use_item()
	# poseben primer (ne porabi se iz inventarja).
	"frozen_rampart": preload("res://Scripts/Items/frozen_rampart_item.gd"),
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

# false only for passives/artifacts whose effect doesn't benefit from owning
# more than 1 copy (a boolean has_passive() check, or a flat, non-scaling
# get_reward()) - see GameParameters/items.json "stackable" field. Consumables
# omit the field and default to true (always fine to hold many).
func get_stackable(id: String) -> bool:
	return _items.get(id, {}).get("stackable", true)

func get_rarity_color(id: String) -> Color:
	return RARITY_COLORS.get(get_rarity(id), Color.WHITE)

func get_ids_by_rarity(rarity: String) -> Array:
	var ids := []
	for id in _items.keys():
		if get_rarity(id) == rarity:
			ids.append(id)
	return ids

func get_ids_by_rarity_and_kinds(rarity: String, kinds: Array, excluded_ids: Array = []) -> Array:
	var ids := []
	for id in _items.keys():
		if get_rarity(id) == rarity and get_kind(id) in kinds and not (id in excluded_ids):
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

# Shared "per-tier array, then infinite_mode grows it further above base_tier,
# clamped at a max" formula - same convention as CurseData.get_min_curse_count
# (see GameParameters/curses.json config.infinite_mode). Used for both
# items_per_tier/artifacts_per_tier below so treasure chests keep scaling past
# the classic 3-tier map instead of flatlining once a run goes infinite.
func _tier_scaled_count(tier: int, per_tier_key: String, default_base: int, increment_key: String, max_key: String) -> int:
	var per_tier: Array = _treasure_config.get(per_tier_key, [default_base])
	var base: int = default_base
	if not per_tier.is_empty():
		base = int(per_tier[clampi(tier, 0, per_tier.size() - 1)])

	var inf: Dictionary = _treasure_config.get("infinite_mode", {})
	var base_tier: int = int(inf.get("base_tier", maxi(0, per_tier.size() - 1)))
	var per_tier_increment: int = int(inf.get(increment_key, 0))
	var count := base + maxi(0, tier - base_tier) * per_tier_increment

	var max_count: int = int(inf.get(max_key, -1))
	if max_count >= 0:
		count = mini(count, max_count)
	return count

# Guaranteed regular-kind (consumable/passive) items per chest, before the
# luck-based bonus in roll_treasure_loot.
func get_treasure_item_count(tier: int) -> int:
	return _tier_scaled_count(tier, "items_per_tier", 1, "items_per_tier_increment", "max_items")

# Guaranteed artifact-kind items per chest.
func get_treasure_artifact_count(tier: int) -> int:
	return _tier_scaled_count(tier, "artifacts_per_tier", 0, "artifacts_per_tier_increment", "max_artifacts")

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

# Izbere en item id za rarity/kinds, izloči excluded_ids (že podeljeni
# non-stackable itemi, glej get_stackable). Če ta rariteta po izločitvi nima
# nič na voljo (npr. edini epic/legendary artefakt je že v lasti), pade nazaj
# na prvo raritete iz RARITY_ORDER, ki po izločitvi še ima kaj - common
# vsebuje vedno stackable consumable-e, zato ta fallback nikoli ne vrne "".
func _pick_available_id(rarity: String, kinds: Array, excluded_ids: Array, rng: RandomNumberGenerator) -> String:
	var ids := get_ids_by_rarity_and_kinds(rarity, kinds, excluded_ids)
	if ids.is_empty():
		for fallback_rarity in RARITY_ORDER:
			ids = get_ids_by_rarity_and_kinds(fallback_rarity, kinds, excluded_ids)
			if not ids.is_empty():
				break
	if ids.is_empty():
		return ""
	return ids[rng.randi_range(0, ids.size() - 1)]

# Neodvisen met za vsak slot: najprej rariteta po utežeh, nato uniformen item
# te raritete. rng parameter zaradi testov (seedable); null -> nov RNG.
# excluded_ids: itemi, ki jih igralec že ima in niso stackable (glej
# PlayerManager.get_unstackable_owned_ids) - preskoči jih pri metu, da trgovina
# ne ponudi ničvrednega duplikata. Znotraj EN METa se izločeni seznam širi z
# vsakim non-stackable izidom, da tudi dva slota v isti trgovini ne moreta
# oba pristati na istem non-stackable itemu.
func roll_shop_stock(rng: RandomNumberGenerator = null, excluded_ids: Array = []) -> Array:
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

	var picked: Array = excluded_ids.duplicate()
	for i in range(get_shop_slot_count()):
		var chosen_rarity := _weighted_rarity_pick(usable_weights, rng)
		var chosen_id := _pick_available_id(chosen_rarity, ["consumable", "passive"], picked, rng)
		if chosen_id == "":
			continue
		stock.append(chosen_id)
		if not get_stackable(chosen_id):
			picked.append(chosen_id)

	return stock

# En "batch" zaklada: count neodvisnih metov iz danih kinds (regular items ALI
# artefakti, glej roll_treasure_loot), z isto "best of 1+rerolls" logiko kot
# prej. picked_ids je DELJEN med batchi znotraj istega roll_treasure_loot
# klica (in vsebuje že-lastne non-stackable id-je pred prvim klicem), zato en
# odprt zaklad ne more podeliti dveh kosov istega non-stackable itema, tudi
# če je eden iz "items" in drugi iz "artifacts" batcha.
func _roll_loot_batch(count: int, kinds: Array, weights: Dictionary, rerolls: int,
		rng: RandomNumberGenerator, picked_ids: Array) -> Array:
	var usable_weights := {}
	for rarity in weights.keys():
		if get_ids_by_rarity_and_kinds(rarity, kinds).size() > 0:
			usable_weights[rarity] = weights[rarity]
	if usable_weights.is_empty():
		return []

	var batch: Array = []
	for i in range(count):
		var rarity := _roll_best_rarity(usable_weights, rerolls, rng)
		var id := _pick_available_id(rarity, kinds, picked_ids, rng)
		if id == "":
			continue
		batch.append(id)
		if not get_stackable(id):
			picked_ids.append(id)
	return batch

# Zaklad vedno podeli LOČENO garantirano število regular itemov (consumable/
# passive) IN artefaktov (glej GameParameters/treasure_config.json
# items_per_tier/artifacts_per_tier + infinite_mode) - ne en skupen bazen kot
# prej, da igralec ne more dobiti zaklada samih artefaktov ali samih itemov.
# Luck dodaja bonus na OBA ločeno (bonus_items prek luck_per_bonus_item/
# max_bonus_items, bonus_artifacts prek luck_per_bonus_artifact/
# max_bonus_artifacts - slednji namerno dražji, saj so artefakti močnejša
# nagrada). excluded_ids: glej roll_shop_stock zgoraj (isti namen).
func roll_treasure_loot(tier: int, luck: int, rng: RandomNumberGenerator = null,
		excluded_ids: Array = []) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var weights := get_treasure_rarity_weights(tier)

	var rerolls: int = clampi(luck / int(_treasure_config.get("luck_per_reroll", 2)),
		0, int(_treasure_config.get("max_rerolls", 3)))
	var bonus_items: int = clampi(luck / int(_treasure_config.get("luck_per_bonus_item", 3)),
		0, int(_treasure_config.get("max_bonus_items", 2)))
	var bonus_artifacts: int = clampi(luck / int(_treasure_config.get("luck_per_bonus_artifact", 6)),
		0, int(_treasure_config.get("max_bonus_artifacts", 1)))
	var item_count: int = get_treasure_item_count(tier) + bonus_items
	var artifact_count: int = get_treasure_artifact_count(tier) + bonus_artifacts

	var picked: Array = excluded_ids.duplicate()
	var loot: Array = []
	loot.append_array(_roll_loot_batch(item_count, ["consumable", "passive"], weights, rerolls, rng, picked))
	loot.append_array(_roll_loot_batch(artifact_count, ["artifact"], weights, rerolls, rng, picked))
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
