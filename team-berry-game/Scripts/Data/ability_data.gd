# res://Scripts/Data/ability_data.gd
# Autoload. Prebere Data/abilities.json (base_uses/max_uses po ability id-ju),
# da lahko balansiramo sposobnosti brez spreminjanja GDScript kode.
extends Node

const DATA_PATH := "res://Data/abilities.json"

var _uses_by_id: Dictionary = {}

func _ready():
	_load()

func _load():
	if not FileAccess.file_exists(DATA_PATH):
		push_error("AbilityData: manjka datoteka %s" % DATA_PATH)
		return

	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_uses_by_id = parsed
	else:
		push_error("AbilityData: neveljaven JSON v %s" % DATA_PATH)

func get_base_uses(id: String) -> int:
	return _uses_by_id.get(id, {}).get("base_uses", 0)

func get_mid_uses(id: String) -> int:
	return _uses_by_id.get(id, {}).get("mid_uses", 0)

func get_max_uses(id: String) -> int:
	return _uses_by_id.get(id, {}).get("max_uses", 0)

# Strošek (upgrade itemi) za dvig sposobnosti iz nivoja 1 na 2.
func get_level_up_cost(id: String) -> int:
	return _uses_by_id.get(id, {}).get("level_up_cost", 0)

# Strošek (upgrade itemi) za odklep 2. sposobnostnega slota. Samo sposobnosti,
# ki dejansko živijo v slotu 2 (glej posamezne figure), imajo to nastavljeno.
func get_unlock_cost(id: String) -> int:
	return _uses_by_id.get(id, {}).get("unlock_cost", 0)
