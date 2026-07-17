# res://Scripts/settings_menu.gd
# Ponovno uporaben overlay: Main Menu in Pause Menu ga oba instancirata kot
# otroka sebe, ko igralec pritisne "SETTINGS", in ga odstranita/skrijeta ob
# back_pressed - "nazaj" torej deluje samodejno (nikoli nismo zares zapustili
# scene, ki nas je odprla).
extends Control

signal back_pressed

@onready var rows_container: VBoxContainer = %RowsContainer
@onready var restore_button: Button = %RestoreButton
@onready var back_button: Button = %BackButton
@onready var reduced_motion_check: CheckBox = %ReducedMotionCheck

const MODIFIER_KEYCODES := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]

# Akcija, ki trenutno čaka na naslednji pritisk tipke ("" = nič ne čaka).
var _capturing_action: String = ""
var _row_buttons: Dictionary = {}


func _ready():
	restore_button.pressed.connect(_on_restore_pressed)
	back_button.pressed.connect(_on_back_pressed)
	reduced_motion_check.button_pressed = SettingsManager.reduced_motion
	reduced_motion_check.toggled.connect(_on_reduced_motion_toggled)
	_build_rows()


func _on_reduced_motion_toggled(enabled: bool):
	SettingsManager.set_reduced_motion(enabled)


func _build_rows():
	for child in rows_container.get_children():
		child.queue_free()
	_row_buttons.clear()

	for action in KeybindManager.REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)

		var label := Label.new()
		label.text = _action_label(action)
		label.custom_minimum_size = Vector2(240, 0)
		row.add_child(label)

		var bind_button := Button.new()
		bind_button.custom_minimum_size = Vector2(160, 0)
		bind_button.pressed.connect(_on_rebind_button_pressed.bind(action, bind_button))
		row.add_child(bind_button)

		rows_container.add_child(row)
		_row_buttons[action] = bind_button
		_refresh_row(action)


# Prijazna imena za akcije brez podčrtajev - "piece_slot_N" postane "Piece Slot N".
func _action_label(action: String) -> String:
	match action:
		"end_turn":
			return "End Turn"
		"select_last_moved":
			return "Select Last Moved"
		"ability_1":
			return "Ability 1"
		"ability_2":
			return "Ability 2"
		_:
			if action.begins_with("piece_slot_"):
				return "Piece Slot %s" % action.trim_prefix("piece_slot_")
			return action


func _on_rebind_button_pressed(action: String, _button: Button):
	if _capturing_action != "":
		# Igralec je kliknil drugo vrstico sredi čakanja na prejšnjo - prekliči
		# prejšnjo čisto, brez spremembe.
		_refresh_row(_capturing_action)
	_capturing_action = action
	_row_buttons[action].text = "PRESS A KEY..."


func _refresh_row(action: String):
	if _row_buttons.has(action):
		_row_buttons[action].text = KeybindManager.keycode_to_label(KeybindManager.get_current_keycode(action))


func _unhandled_input(event):
	if _capturing_action == "":
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	var action := _capturing_action

	if event.physical_keycode == KEY_ESCAPE:
		# Prekliči brez spremembe - Escape ostane rezerviran za pavzo.
		_capturing_action = ""
		_refresh_row(action)
		get_viewport().set_input_as_handled()
		return

	if event.physical_keycode in MODIFIER_KEYCODES:
		return

	KeybindManager.rebind_action(action, event.physical_keycode)
	_capturing_action = ""
	_refresh_row(action)
	get_viewport().set_input_as_handled()


func _on_restore_pressed():
	KeybindManager.restore_defaults()
	for action in _row_buttons.keys():
		_refresh_row(action)


func _on_back_pressed():
	back_pressed.emit()
