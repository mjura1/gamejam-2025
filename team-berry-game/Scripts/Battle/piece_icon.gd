# res://Scripts/Battle/piece_icon.gd
# Majhna klikljiva ikona figure v battle UI (vrstici roster/aktivni).
class_name PieceIcon
extends TextureRect

signal icon_clicked(icon)

# Ime figure v obliki rosterja ("friendly_pawn" ipd.) - določa tudi sprite.
var piece_name: String = ""
# Živa figura na plošči, ki ji ikona pripada (null, če je figura mrtva).
var character: BaseCharacter = null

var is_dead: bool = false
# Figura je živa, a ni bila postavljena v to bitko (na klopi).
var is_benched: bool = false
var is_highlighted: bool = false
# Figura je že postavljena na ploščo (vnos v roster vrstici zanjo).
var is_placed: bool = false

# Majhna prosojna značka v kotu ikone, ki prikaže tipko za izbiro tega mesta
# (glej battle_ui.gd._slot_label_text) - ista bližnjica kot na sami figuri.
var slot_label: Label

const COLOR_NORMAL := Color(1, 1, 1)
const COLOR_DEAD := Color(0.35, 0.35, 0.35)
const COLOR_BENCHED := Color(0.6, 0.6, 0.6)
const COLOR_HIGHLIGHTED := Color(1, 1, 0.4)
const COLOR_PLACED := Color(0.75, 0.75, 0.75)


func _init():
	custom_minimum_size = Vector2(40, 40)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_STOP

	slot_label = Label.new()
	slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_label.add_theme_font_size_override("font_size", 11)
	slot_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	slot_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	slot_label.add_theme_constant_override("shadow_offset_x", 1)
	slot_label.add_theme_constant_override("shadow_offset_y", 1)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slot_label.size = Vector2(18, 14)
	slot_label.position = Vector2(20, 25)
	slot_label.visible = false
	add_child(slot_label)


func set_slot_label(text: String):
	slot_label.text = text
	slot_label.visible = text != ""


func setup(p_piece_name: String, p_character: BaseCharacter):
	piece_name = p_piece_name
	character = p_character
	texture = load("res://Assets/Sprites/%s.png" % piece_name)
	_update_modulate()


func set_dead(dead: bool):
	is_dead = dead
	_update_modulate()


func set_benched(benched: bool):
	is_benched = benched
	_update_modulate()


func set_highlighted(highlighted: bool):
	is_highlighted = highlighted
	_update_modulate()


func set_placed(placed: bool):
	is_placed = placed
	_update_modulate()


func _update_modulate():
	if is_dead:
		modulate = COLOR_DEAD
	elif is_highlighted:
		modulate = COLOR_HIGHLIGHTED
	elif is_benched:
		modulate = COLOR_BENCHED
	elif is_placed:
		modulate = COLOR_PLACED
	else:
		modulate = COLOR_NORMAL


func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		icon_clicked.emit(self)
		accept_event()
