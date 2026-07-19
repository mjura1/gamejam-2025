# res://Scripts/Data/skill_tree_data.gd
# Autoload. Prebere Data/skill_trees.json (drevo nadgradenj po tipu figure),
# da lahko balansiramo drevesa brez spreminjanja GDScript kode.
# Glej SKILL_TREE_PLAN.md za shemo vozlišč in seznam effect tipov.
extends Node

const DATA_PATH := "res://Data/skill_trees.json"

var _trees_by_type: Dictionary = {}

func _ready():
	_load()

func _load():
	if not FileAccess.file_exists(DATA_PATH):
		push_error("SkillTreeData: manjka datoteka %s" % DATA_PATH)
		return

	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_trees_by_type = parsed
	else:
		push_error("SkillTreeData: neveljaven JSON v %s" % DATA_PATH)

# Vsa vozlišča drevesa za dani tip figure ("pawn" ipd.), v prikazovalnem
# vrstnem redu. POZOR: ime NI get_tree() - to bi povozilo Node.get_tree().
func get_tree_nodes(piece_type: String) -> Array:
	return _trees_by_type.get(piece_type, [])

# Def enega vozlišča ali {}, če ne obstaja. POZOR: ime NI get_node() - to bi
# povozilo Node.get_node().
func get_node_def(piece_type: String, node_id: String) -> Dictionary:
	for node_def in get_tree_nodes(piece_type):
		if node_def.get("id", "") == node_id:
			return node_def
	return {}
