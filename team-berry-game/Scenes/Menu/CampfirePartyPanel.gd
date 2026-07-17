# res://Scenes/Menu/CampfirePartyPanel.gd
# Party management na počivališču: zgoraj vsi lastniški koščki (aktivni +
# rezerva) v scrollable gridu, spodaj aktivna ekipa kot 10 fiksnih rež
# (5x2 - max_party_size). Klik na koščka v zgornjem gridu ga doda v aktivno
# ekipo (če je prostor); klik na koščka v spodnjem gridu ga vrne v rezervo.
extends CanvasLayer

@onready var player_manager = get_node("/root/PlayerManager")

@onready var roster_grid: GridContainer = %RosterGrid
@onready var active_grid: GridContainer = %ActiveGrid
@onready var back_button: Button = %BackButton


func _ready():
	player_manager.party_changed.connect(_refresh)
	back_button.pressed.connect(close_menu)
	_refresh()


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		close_menu()


func _refresh():
	_rebuild_roster_grid()
	_rebuild_active_grid()


# ===============================================
# ZGORAJ: VSI KOŠČKI (aktivni - polna barva, rezerva - potemnjeni "benched")
# ===============================================

func _rebuild_roster_grid():
	for child in roster_grid.get_children():
		child.queue_free()

	for i in player_manager.friendly_party.size():
		var icon := PieceIcon.new()
		icon.setup(player_manager.friendly_party[i], null)
		icon.icon_clicked.connect(func(_icon): player_manager.move_active_to_reserve(i))
		roster_grid.add_child(icon)

	for i in player_manager.reserve_party.size():
		var icon := PieceIcon.new()
		icon.setup(player_manager.reserve_party[i], null)
		icon.set_benched(true)
		icon.icon_clicked.connect(func(_icon): player_manager.move_reserve_to_active(i))
		roster_grid.add_child(icon)


# ===============================================
# SPODAJ: AKTIVNA EKIPA - 10 FIKSNIH REŽ
# ===============================================

func _rebuild_active_grid():
	for child in active_grid.get_children():
		child.queue_free()

	for i in player_manager.max_party_size:
		if i < player_manager.friendly_party.size():
			var icon := PieceIcon.new()
			icon.setup(player_manager.friendly_party[i], null)
			icon.icon_clicked.connect(func(_icon): player_manager.move_active_to_reserve(i))
			active_grid.add_child(icon)
		else:
			var empty_slot := Control.new()
			empty_slot.custom_minimum_size = Vector2(40, 40)
			active_grid.add_child(empty_slot)


# ===============================================
# ZAPIRANJE
# ===============================================

func close_menu():
	queue_free()
