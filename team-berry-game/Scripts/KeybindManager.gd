# res://Scripts/KeybindManager.gd (Autoload/Singleton)
# Upravlja preslikave (rebinding) tipk za akcije, ki jih igralec sme
# prilagoditi v Settings zaslonu, in jih shrani/nalozi iz user://keybinds.cfg.
# Prvi autoload v [autoload] vrstnem redu (project.godot), da se shranjeni
# rebindi uveljavijo prej, kot lahko karkoli drugega prebere Input/InputMap.
extends Node

# Sproži se ob vsakem rebindu/restore_defaults - battle_ui.gd ga uporabi za
# takojšnjo osvežitev značk s tipko na roster/aktivni vrstici in figurah.
signal rebinds_changed

const SAVE_PATH := "user://keybinds.cfg"
const SECTION := "keybinds"

# Vse akcije, ki jih Settings zaslon prikaze in dovoli spremeniti - en sam vir
# resnice za save/load/restore in za gradnjo vrstic v settings_menu.gd.
const REBINDABLE_ACTIONS: Array[String] = [
	"end_turn",
	"select_last_moved",
	"ability_1",
	"ability_2",
	"piece_slot_1",
	"piece_slot_2",
	"piece_slot_3",
	"piece_slot_4",
	"piece_slot_5",
	"piece_slot_6",
	"piece_slot_7",
	"piece_slot_8",
	"piece_slot_9",
	"piece_slot_10",
]

# Fizicne tipke (physical_keycode) iz project.godot ob zagonu igre, PRED
# nalaganjem shranjenih rebindov - to je osnova za "RESTORE TO DEFAULTS".
var _defaults: Dictionary = {}


func _ready():
	for action in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			_defaults[action] = _first_physical_keycode(action)
	load_keybinds()


func _first_physical_keycode(action: String) -> int:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return 0
	return events[0].physical_keycode


func _apply(action: String, physical_keycode: int):
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	InputMap.action_add_event(action, event)


func get_current_keycode(action: String) -> int:
	return _first_physical_keycode(action)


func keycode_to_label(physical_keycode: int) -> String:
	return OS.get_keycode_string(physical_keycode)


func rebind_action(action: String, physical_keycode: int):
	_apply(action, physical_keycode)
	save_keybinds()
	rebinds_changed.emit()


func restore_defaults():
	for action in REBINDABLE_ACTIONS:
		if _defaults.has(action):
			_apply(action, _defaults[action])
	save_keybinds()
	rebinds_changed.emit()


func load_keybinds():
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		# Prvi zagon (se ni shranjene datoteke) - privzete vrednosti iz
		# project.godot so ze aktivne, ni potrebno nic narediti.
		return

	for action in REBINDABLE_ACTIONS:
		if cfg.has_section_key(SECTION, action):
			_apply(action, cfg.get_value(SECTION, action))


func save_keybinds():
	var cfg := ConfigFile.new()
	for action in REBINDABLE_ACTIONS:
		var keycode := _first_physical_keycode(action)
		if keycode != 0:
			cfg.set_value(SECTION, action, keycode)
	cfg.save(SAVE_PATH)
