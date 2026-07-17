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
var is_highlighted: bool = false

const COLOR_NORMAL := Color(1, 1, 1)
const COLOR_DEAD := Color(0.35, 0.35, 0.35)
const COLOR_HIGHLIGHTED := Color(1, 1, 0.4)


func _init():
	custom_minimum_size = Vector2(40, 40)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(p_piece_name: String, p_character: BaseCharacter):
	piece_name = p_piece_name
	character = p_character
	texture = load("res://Assets/Sprites/%s.png" % piece_name)
	set_dead(not is_instance_valid(character))


func set_dead(dead: bool):
	is_dead = dead
	_update_modulate()


func set_highlighted(highlighted: bool):
	is_highlighted = highlighted
	_update_modulate()


func _update_modulate():
	if is_dead:
		modulate = COLOR_DEAD
	elif is_highlighted:
		modulate = COLOR_HIGHLIGHTED
	else:
		modulate = COLOR_NORMAL


func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		icon_clicked.emit(self)
		accept_event()
