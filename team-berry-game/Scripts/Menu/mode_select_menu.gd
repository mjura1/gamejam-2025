# res://Scripts/Menu/mode_select_menu.gd
# Overlay, instanciran kot otrok MainMenu (enak vzorec kot settings_menu.gd).
# CLASSIC/INFINITE zaženeta igro prek GF.start_new_game(); TUTORIAL odpre hub;
# BACK samo emitira signal, MainMenu poskrbi za odstranitev.
extends Control

signal back_pressed

@onready var difficulty_option: OptionButton = %DifficultyOption
@onready var ai_difficulty_option: OptionButton = %AiDifficultyOption
@onready var legacy_button: Button = %LegacyButton

const DIFFICULTY_IDS := ["easy", "normal", "hard"]
const DIFFICULTY_TOOLTIP := "EASY - enemies get curses half as often (0.5x) and never play it safe.\nNORMAL - standard curse rate, enemies sometimes retreat to safety (50%).\nHARD - enemies get curses 50% more often (1.5x) and always retreat to safety."

# Vrstni red mora ustrezati OptionButton item indeksom v mode_select_menu.tscn
# (0=NORMAL, 1=HARD, 2=EXTREME, 3=IMPOSSIBLE) - ločena os od DIFFICULTY_IDS
# zgoraj, glej SettingsManager.ai_difficulty.
const AI_DIFFICULTY_IDS := ["normal", "hard", "extreme", "impossible"]

func _ready():
	difficulty_option.selected = DIFFICULTY_IDS.find(SettingsManager.difficulty)
	difficulty_option.item_selected.connect(_on_difficulty_selected)
	difficulty_option.tooltip_text = DIFFICULTY_TOOLTIP
	ai_difficulty_option.selected = AI_DIFFICULTY_IDS.find(SettingsManager.ai_difficulty)
	ai_difficulty_option.item_selected.connect(_on_ai_difficulty_selected)
	legacy_button.visible = MetaProgress.final_boss_beaten

func _on_difficulty_selected(index: int):
	UiAudio.play_click()
	if index < 0 or index >= DIFFICULTY_IDS.size():
		return
	SettingsManager.set_difficulty(DIFFICULTY_IDS[index])

func _on_ai_difficulty_selected(index: int):
	UiAudio.play_click()
	if index < 0 or index >= AI_DIFFICULTY_IDS.size():
		return
	SettingsManager.set_ai_difficulty(AI_DIFFICULTY_IDS[index])

func _on_classic_pressed():
	UiAudio.play_click()
	PlayerManager.setStarting("classic")
	GF.start_new_game()

func _on_infinite_pressed():
	UiAudio.play_click()
	PlayerManager.setStarting("infinite")
	GF.start_new_game()

func _on_tutorial_pressed():
	UiAudio.play_click()
	GF.start_tutorial_hub()

func _on_legacy_pressed():
	UiAudio.play_click()
	GF.start_legacy_shop()

func _on_back_pressed():
	UiAudio.play_click()
	back_pressed.emit()
