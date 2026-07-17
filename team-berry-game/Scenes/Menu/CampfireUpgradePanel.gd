# res://Scenes/Menu/CampfireUpgradePanel.gd
# Nadgradnje na počivališču: za vsak TIP figure v lasti (aktivna + rezerva)
# prikaže obe sposobnosti z nivojem in gumbom za odklep slota 2 / dvig nivoja.
# Nadgradnje veljajo za VSE figure istega tipa in so trajne za ta run
# (PlayerManager.piece_upgrades) - tu je edino mesto porabe upgrade itemov.
extends CanvasLayer

@onready var player_manager = get_node("/root/PlayerManager")
@onready var ability_data = get_node("/root/AbilityData")

@onready var items_label: Label = %ItemsLabel
@onready var type_list: VBoxContainer = %TypeList
@onready var back_button: Button = %BackButton

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

	for child in type_list.get_children():
		child.queue_free()
	for piece_type in _owned_types():
		type_list.add_child(_build_type_row(piece_type))


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
	var up: Dictionary = player_manager.get_piece_upgrades(piece_type)
	for i in range(defs.size()):
		row.add_child(_build_slot_box(piece_type, i + 1, defs[i], up))

	return row


# En stolpec za eno sposobnost: ime + nivo, opis trenutnega nivoja kot
# tooltip, spodaj gumb UNLOCK/LEVEL UP/MAX.
func _build_slot_box(piece_type: String, slot: int, def: Dictionary, up: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var level: int = up["levels"][slot]
	var locked: bool = slot == 2 and not up["slot2_unlocked"]
	var id: String = def.get("id", "")

	var name_label := Label.new()
	if locked:
		name_label.text = "%s  (LOCKED)" % def.get("name", "-")
	else:
		name_label.text = "%s  Lv %d/%d" % [def.get("name", "-"), level, BaseCharacter.ABILITY_LEVEL_MAX]
	name_label.add_theme_font_size_override("font_size", 16)
	box.add_child(name_label)

	var tier_key: String = BaseCharacter.ABILITY_TIER_KEYS[level - 1]
	box.tooltip_text = def.get(tier_key, {}).get("desc", "")

	var button := Button.new()
	if locked:
		var unlock_cost: int = ability_data.get_unlock_cost(id)
		button.text = "UNLOCK (%d)" % unlock_cost
		button.disabled = player_manager.upgrade_items < unlock_cost
		button.pressed.connect(func(): player_manager.try_unlock_slot2(piece_type, unlock_cost))
	elif level >= BaseCharacter.ABILITY_LEVEL_MAX:
		button.text = "MAX"
		button.disabled = true
	else:
		var level_up_cost: int = ability_data.get_level_up_cost(id)
		button.text = "LEVEL UP (%d)" % level_up_cost
		button.disabled = player_manager.upgrade_items < level_up_cost
		button.pressed.connect(func(): player_manager.try_level_up_ability(piece_type, slot, level_up_cost))
	box.add_child(button)

	return box


func close_menu():
	queue_free()
