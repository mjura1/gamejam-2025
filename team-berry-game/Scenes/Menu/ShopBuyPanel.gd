# res://Scenes/Menu/ShopBuyPanel.gd
# Trgovina - nakup: ena vrstica na item iz ItemData.get_item_ids() (trenutno
# samo extra_move - zaloga trgovine je "vse, kar obstaja", glej ITEM_SHOP_PLAN
# Phase 3). Gumb BUY je onemogočen, če igralec nima dovolj upgrade_items.
extends CanvasLayer

@onready var player_manager = get_node("/root/PlayerManager")

@onready var items_label: Label = %ItemsLabel
@onready var item_list: VBoxContainer = %ItemList
@onready var back_button: Button = %BackButton


func _ready():
	player_manager.items_changed.connect(_refresh)
	back_button.pressed.connect(close_menu)
	_refresh()


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		close_menu()


func _refresh():
	items_label.text = "UPGRADE ITEMS: x%d" % player_manager.upgrade_items

	for child in item_list.get_children():
		child.queue_free()
	for id in ItemData.get_item_ids():
		item_list.add_child(_build_item_row(id))


func _build_item_row(id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var icon := TextureRect.new()
	icon.texture = load("res://Assets/Sprites/item_%s.png" % id)
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = ItemData.get_item_name(id)
	info.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = ItemData.get_item_description(id)
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_label)
	row.add_child(info)

	var cost: int = ItemData.get_buy_cost(id)
	var button := Button.new()
	button.text = "BUY (%d)" % cost
	button.disabled = player_manager.upgrade_items < cost
	button.pressed.connect(func(): player_manager.try_buy_item(id))
	row.add_child(button)

	return row


func close_menu():
	queue_free()
