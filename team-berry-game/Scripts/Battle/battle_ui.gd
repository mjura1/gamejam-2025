# res://Scripts/Battle/battle_ui.gd
# Desni UI panel v bitki: roster, aktivne figure, itemi in podrobnosti
# izbrane figure. Živi na CanvasLayerju, da ga Camera2D ne transformira
# (enak pristop kot pause menu - glej GameFlow._ready()).
extends CanvasLayer

@onready var player_manager = get_node("/root/PlayerManager")
@onready var grid_manager = get_node("../GridManager")
@onready var map_behaviour = get_node("../Map")

@onready var roster_row: HFlowContainer = %RosterRow
@onready var active_row: HFlowContainer = %ActiveRow
@onready var upgrade_count_label: Label = %UpgradeCount
@onready var revive_count_label: Label = %ReviveCount
@onready var portrait: TextureRect = %Portrait
@onready var status_value: Label = %StatusValue
@onready var ability1_name: Label = %Ability1Name
@onready var ability1_uses: Label = %Ability1Uses
@onready var ability1_desc: Label = %Ability1Desc
@onready var ability2_locked: Label = %Ability2Locked

const STATUS_ALIVE_COLOR := Color(0.5, 1.0, 0.5)
const STATUS_DEAD_COLOR := Color(1.0, 0.4, 0.4)


func _ready():
	player_manager.party_changed.connect(_on_party_changed)
	map_behaviour.selection_changed.connect(_on_selection_changed)

	_update_item_counts()
	_clear_detail_panel()

	# Figure se spawnajo šele v battle.gd._ready() (starš se inicializira ZA
	# otroki), zato prvo gradnjo vrstic odložimo za en frame.
	_rebuild_rows.call_deferred()


# ===============================================
# VRSTICI Z IKONAMI (roster + aktivne)
# ===============================================

func _rebuild_rows():
	for child in roster_row.get_children():
		child.queue_free()
	for child in active_row.get_children():
		child.queue_free()

	# Žive zavezniške figure na plošči, razvrščene po tipu rosterja.
	var alive_by_type: Dictionary = {}
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter):
			continue
		if character.is_enemy or character.is_obstacle:
			continue
		var roster_name: String = "friendly_" + character.strName
		if not alive_by_type.has(roster_name):
			alive_by_type[roster_name] = []
		alive_by_type[roster_name].append(character)

	# RDEČA VRSTICA: celoten roster. Vsakemu vnosu poskusimo dodeliti živo
	# figuro istega tipa - vnosi brez nje so prikazani kot mrtvi (sivi).
	# Dodelitve si zapomnimo, da roza vrstico zgradimo iz istih podatkov
	# (ne iz otrok roster_row - tam so ob rebuildu še stari, queue_free
	# čakajoči otroci).
	var assignments: Array = []
	for roster_name in player_manager.friendly_party:
		var assigned: BaseCharacter = null
		if alive_by_type.has(roster_name) and not alive_by_type[roster_name].is_empty():
			assigned = alive_by_type[roster_name].pop_front()
		assignments.append([roster_name, assigned])

		var icon := PieceIcon.new()
		icon.setup(roster_name, assigned)
		icon.icon_clicked.connect(_on_icon_clicked)
		roster_row.add_child(icon)

	# ROZA VRSTICA: aktivne figure (žive na plošči). Trenutno enaka vsebina
	# kot roster minus mrtvi - ločena vrstica pride prav ob kasnejšem
	# "place pieces before battle" featureju.
	for assignment in assignments:
		if is_instance_valid(assignment[1]):
			var icon := PieceIcon.new()
			icon.setup(assignment[0], assignment[1])
			icon.icon_clicked.connect(_on_icon_clicked)
			active_row.add_child(icon)

	_highlight_selected(map_behaviour.selected_character)


func _on_icon_clicked(icon: PieceIcon):
	if is_instance_valid(icon.character):
		# Živa figura: izberi jo na plošči (enaka pot kot klik na figuro).
		map_behaviour.select_character_via_ui(icon.character)
	else:
		# Mrtva figura: ni izbire na plošči, samo prikaz v detail panelu.
		_show_dead_piece(icon.piece_name)
		_highlight_icon_only(icon)


# ===============================================
# DETAIL PANEL (izbrana figura)
# ===============================================

func _on_selection_changed(character):
	if is_instance_valid(character) and character is BaseCharacter:
		_show_character(character)
	else:
		_clear_detail_panel()
	_highlight_selected(character)


func _show_character(character: BaseCharacter):
	portrait.texture = load("res://Assets/Sprites/friendly_%s.png" % character.strName)
	status_value.text = "ALIVE"
	status_value.add_theme_color_override("font_color", STATUS_ALIVE_COLOR)
	_show_ability_placeholders()


func _show_dead_piece(piece_name: String):
	portrait.texture = load("res://Assets/Sprites/%s.png" % piece_name)
	status_value.text = "DEAD"
	status_value.add_theme_color_override("font_color", STATUS_DEAD_COLOR)
	_show_ability_placeholders()


func _clear_detail_panel():
	portrait.texture = null
	status_value.text = "-"
	status_value.remove_theme_color_override("font_color")
	ability1_name.text = "-"
	ability1_uses.text = ""
	ability1_desc.text = ""
	ability2_locked.text = ""


func _show_ability_placeholders():
	# Ability sistem še ne obstaja - prikažemo predvideno obliko panela.
	ability1_name.text = "???"
	ability1_uses.text = "0"
	ability1_desc.text = "Abilities coming soon."
	ability2_locked.text = "Use 1 upgrade item at a rest to unlock the second ability."


# ===============================================
# POUDARJANJE IKON
# ===============================================

func _highlight_selected(character):
	for row in [roster_row, active_row]:
		for icon in row.get_children():
			if icon is PieceIcon:
				icon.set_highlighted(
					is_instance_valid(character) and icon.character == character
				)


# Poudari samo kliknjeno (mrtvo) ikono - na plošči ni ničesar za izbrat.
func _highlight_icon_only(target: PieceIcon):
	for row in [roster_row, active_row]:
		for icon in row.get_children():
			if icon is PieceIcon:
				icon.set_highlighted(icon == target)


# ===============================================
# ITEMI IN OSVEŽEVANJE
# ===============================================

func _update_item_counts():
	upgrade_count_label.text = "x%d" % player_manager.upgrade_items
	revive_count_label.text = "x%d" % player_manager.revive_items


func _on_party_changed():
	# Figura je umrla (ali se je ekipa spremenila) - osvežimo vrstici.
	# call_deferred: die() sproži signal PREDEN queue_free() figuro
	# dejansko odstrani iz grid_managerja snapshot-a.
	_rebuild_rows.call_deferred()
	_update_item_counts()
