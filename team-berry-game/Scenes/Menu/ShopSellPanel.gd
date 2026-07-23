# res://Scenes/Menu/ShopSellPanel.gd
# Trgovina - prodaja: owned itemi + figure iz aktivne/rezervne ekipe.
# Prodaja figure zmanjša friendly_party/reserve_party (glej PlayerManager.
# try_sell_active_piece/try_sell_reserve_piece) - zadnje aktivne figure ni
# mogoče prodati (isti guard kot move_active_to_reserve). Seznam se obnovi
# na items_changed IN party_changed (prodaja figure sproži oba).
extends CanvasLayer

@onready var player_manager = get_node("/root/PlayerManager")

@onready var items_label: Label = %ItemsLabel
@onready var item_list: VBoxContainer = %ItemList
@onready var piece_list: VBoxContainer = %PieceList
@onready var back_button: Button = %BackButton


func _ready():
	player_manager.items_changed.connect(_refresh)
	player_manager.party_changed.connect(_refresh)
	back_button.pressed.connect(close_menu)
	_refresh()


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		close_menu()


func _refresh():
	items_label.text = "UPGRADE ITEMS: x%d" % player_manager.upgrade_items
	_rebuild_item_list()
	_rebuild_piece_list()


func _rebuild_item_list():
	for child in item_list.get_children():
		child.queue_free()
	for id in player_manager.owned_items.keys():
		var count: int = player_manager.owned_items[id]
		if count <= 0:
			continue
		item_list.add_child(_build_item_row(id, count))
	if item_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "NO ITEMS"
		item_list.add_child(empty)


func _build_item_row(id: String, count: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var icon := TextureRect.new()
	icon.texture = load("res://Assets/Sprites/item_%s.png" % id)
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = "%s  x%d" % [ItemData.get_item_name(id), count]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Artefakt "hoarders_ring": prikazana cena mora ustrezati dejanskemu izplačilu
	# iz PlayerManager.try_sell_item (glej tam - podvoji vrednost itemov).
	var sell_value: int = ItemData.get_sell_value(id)
	if player_manager.has_passive("hoarders_ring"):
		sell_value *= 2
	var button := Button.new()
	button.text = "SELL (%d)" % sell_value
	button.pressed.connect(func(): player_manager.try_sell_item(id))
	row.add_child(button)

	return row


# Vsak vnos friendly_party (ACTIVE) nato reserve_party (RESERVE) dobi svojo
# vrstico - indeks `i` je zajet po vrednosti (GDScript for-loop vsako
# iteracijo veže novo spremenljivko, glej CampfirePartyPanel.gd za isti vzorec).
func _rebuild_piece_list():
	for child in piece_list.get_children():
		child.queue_free()
	for i in player_manager.friendly_party.size():
		var last_active: bool = player_manager.friendly_party.size() <= 1
		piece_list.add_child(_build_piece_row(
			player_manager.friendly_party[i], "ACTIVE",
			func(): player_manager.try_sell_active_piece(i),
			last_active
		))
	for i in player_manager.reserve_party.size():
		piece_list.add_child(_build_piece_row(
			player_manager.reserve_party[i], "RESERVE",
			func(): player_manager.try_sell_reserve_piece(i),
			false
		))


func _build_piece_row(roster_name: String, tag: String, on_sell: Callable, disabled: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var icon := TextureRect.new()
	icon.texture = load("res://Assets/Sprites/%s.png" % roster_name)
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = "%s  (%s)" % [roster_name.trim_prefix("friendly_").capitalize(), tag]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var sell_value: int = ItemData.get_piece_sell_value(roster_name)
	var button := Button.new()
	button.text = "SELL (%d)" % sell_value
	button.disabled = disabled
	button.pressed.connect(on_sell)
	row.add_child(button)

	return row


func close_menu():
	queue_free()
