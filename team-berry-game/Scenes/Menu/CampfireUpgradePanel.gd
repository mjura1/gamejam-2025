# res://Scenes/Menu/CampfireUpgradePanel.gd
# Nadgradnje na počivališču: za vsak TIP figure v lasti (aktivna + rezerva)
# prikaže njeno skill-tree drevo (GameParameters/skill_trees.json) v 4 stolpcih -
# sposobnost 1/2/3 + perki - z gumbom za nakup vsakega vozlišča.
# Nadgradnje veljajo za VSE figure istega tipa in so trajne za ta run
# (PlayerManager.piece_upgrades) - tu je edino mesto porabe upgrade itemov.
extends CanvasLayer

@onready var player_manager = get_node("/root/PlayerManager")

@onready var items_label: Label = %ItemsLabel
@onready var type_list: VBoxContainer = %TypeList
@onready var back_button: Button = %BackButton

# Cache za _refresh(): dokler se _owned_types() ne spremeni (nov tip figure),
# posodobimo obstoječe gumbe na mestu namesto da vso drevo podremo in znova
# zgradimo - polni rebuild ob vsakem nakupu (queue_free + realloc ~70 Controlov
# + re-theme) je opazno zatikal UI.
var _built_types: Array[String] = []
var _buttons: Dictionary = {}  # "piece_type:node_id" -> Button

# Vrstni red prikaza; prikažejo se samo tipi, ki jih igralec dejansko ima.
const TYPE_ORDER := ["pawn", "knight", "rook", "bishop", "queen", "king"]

# Za branje get_ability_defs() brez žive figure na plošči: instanca scene se
# NE doda v drevo (_ready/@onready se ne izvedeta), preberemo samo defs.
const PIECE_SCENES := {
	"pawn": preload("res://Scenes/CharacterPiecesNodes/Ally/pawn.tscn"),
	"knight": preload("res://Scenes/CharacterPiecesNodes/Ally/knight.tscn"),
	"rook": preload("res://Scenes/CharacterPiecesNodes/Ally/rook.tscn"),
	"bishop": preload("res://Scenes/CharacterPiecesNodes/Ally/bishop.tscn"),
	"queen": preload("res://Scenes/CharacterPiecesNodes/Ally/queen.tscn"),
	"king": preload("res://Scenes/CharacterPiecesNodes/Ally/king.tscn"),
}


func _ready():
	player_manager.items_changed.connect(_refresh)
	back_button.pressed.connect(close_menu)
	_refresh()


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		close_menu()


# Tipi figur, ki jih igralec ima (aktivna ekipa + rezerva), v TYPE_ORDER
# vrstnem redu, brez podvajanj.
func _owned_types() -> Array[String]:
	var owned: Array[String] = []
	for roster_name in player_manager.friendly_party + player_manager.reserve_party:
		var piece_type: String = roster_name.trim_prefix("friendly_")
		if not owned.has(piece_type):
			owned.append(piece_type)

	var ordered: Array[String] = []
	for piece_type in TYPE_ORDER:
		if owned.has(piece_type):
			ordered.append(piece_type)
	return ordered


func _get_ability_defs(piece_type: String) -> Array:
	var tmp = PIECE_SCENES[piece_type].instantiate()
	var defs: Array = tmp.get_ability_defs()
	tmp.free()
	return defs


func _refresh():
	items_label.text = "UPGRADE ITEMS: x%d" % player_manager.upgrade_items

	var current_types := _owned_types()
	if current_types != _built_types:
		for child in type_list.get_children():
			child.queue_free()
		_buttons.clear()
		for piece_type in current_types:
			type_list.add_child(_build_type_row(piece_type))
		_built_types = current_types
	else:
		for key in _buttons:
			var parts := (key as String).split(":")
			_apply_button_state(_buttons[key], parts[0], parts[1])


func _build_type_row(piece_type: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var icon := TextureRect.new()
	icon.texture = load("res://Assets/Sprites/friendly_%s.png" % piece_type)
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var defs := _get_ability_defs(piece_type)
	row.add_child(_build_column(piece_type, "ABILITY 1 — %s" % defs[0].get("name", "-"), ["a1_lv2", "a1_lv3"], defs))
	row.add_child(_build_column(piece_type, "ABILITY 2 — %s" % defs[1].get("name", "-"), ["a2_unlock", "a2_lv2", "a2_lv3"], defs))
	row.add_child(_build_column(piece_type, "ABILITY 3 — %s" % defs[2].get("name", "-"), ["a3_unlock", "a3_lv2", "a3_lv3"], defs))
	row.add_child(_build_column(piece_type, "PERKS", ["p1", "spec_a", "spec_b"], defs))

	return row


# En stolpec (ena "ABILITY N" ali "PERKS" skupina): naslov + gumb na vozlišče,
# v vrstnem redu iz node_ids.
func _build_column(piece_type: String, header: String, node_ids: Array, defs: Array) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header_label := Label.new()
	header_label.text = header
	header_label.add_theme_font_size_override("font_size", 16)
	col.add_child(header_label)

	for node_id in node_ids:
		col.add_child(_build_node_button(piece_type, node_id, defs))

	return col


func _build_node_button(piece_type: String, node_id: String, defs: Array) -> Button:
	var node_def: Dictionary = SkillTreeData.get_node_def(piece_type, node_id)
	var button := Button.new()
	button.tooltip_text = _node_tooltip(node_def, defs)
	button.pressed.connect(func(): player_manager.try_buy_node(piece_type, node_id))
	_apply_button_state(button, piece_type, node_id)
	_buttons["%s:%s" % [piece_type, node_id]] = button
	return button


# Nastavi text/disabled glede na trenutno stanje - klicano ob gradnji gumba IN
# ob vsakem _refresh() ko se _owned_types() ni spremenil (gl. _refresh()).
# pressed handler ostane isti Callable ves čas, se poveže samo enkrat ob gradnji.
func _apply_button_state(button: Button, piece_type: String, node_id: String) -> void:
	var node_def: Dictionary = SkillTreeData.get_node_def(piece_type, node_id)
	var node_name: String = node_def.get("name", "-")
	var cost: int = int(node_def.get("cost", 0))

	if player_manager.has_tree_node(piece_type, node_id):
		button.text = "✔ %s" % node_name
		button.disabled = true
	elif _is_excluded(piece_type, node_def):
		button.text = "%s (path closed)" % node_name
		button.disabled = true
	elif not _requirements_met(piece_type, node_def):
		button.text = "🔒 %s" % node_name
		button.disabled = true
	elif player_manager.upgrade_items < cost:
		button.text = "%s (%d)" % [node_name, cost]
		button.disabled = true
	else:
		button.text = "%s (%d)" % [node_name, cost]
		button.disabled = false


func _requirements_met(piece_type: String, node_def: Dictionary) -> bool:
	for req in node_def.get("requires", []):
		if not player_manager.has_tree_node(piece_type, req):
			return false
	return true


func _is_excluded(piece_type: String, node_def: Dictionary) -> bool:
	for excl in node_def.get("excludes", []):
		if player_manager.has_tree_node(piece_type, excl):
			return true
	return false


# node_def.desc v skill_trees.json je že poln opis učinka (glej npr. pawn
# a2_lv2 vs. pawn.gd ABILITY_DEFS[1].mid.desc - isti stavek), zato se tu ne
# dodaja še opis iz ABILITY_DEFS - to bi podvojilo isto besedilo v tooltipu.
func _node_tooltip(node_def: Dictionary, _defs: Array) -> String:
	return node_def.get("desc", "")


func close_menu():
	queue_free()
