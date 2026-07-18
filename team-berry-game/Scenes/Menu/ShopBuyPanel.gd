# res://Scenes/Menu/ShopBuyPanel.gd
# Trgovina - nakup: ena vrstica na rolan slot (glej ShopController.stock,
# SHOP_V2_PLAN Phase 2). Slot je {"id": String, "sold": bool}; ShopController
# nastavi `stock` na to sceno pred add_child. Gumb BUY je onemogočen, če
# igralec nima dovolj upgrade_items; kupljen slot postane SOLD in ostane
# onemogočen (brez re-buy) do naslednjega obiska trgovine.
extends CanvasLayer

const RARITY_COLORS := {
	"common": Color.WHITE,
	"uncommon": Color(0.4, 0.9, 0.4),
	"rare": Color(0.45, 0.65, 1.0),
}

@onready var player_manager = get_node("/root/PlayerManager")

@onready var items_label: Label = %ItemsLabel
@onready var item_list: VBoxContainer = %ItemList
@onready var back_button: Button = %BackButton

var stock: Array = []


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
	for slot in stock:
		item_list.add_child(_build_item_row(slot))


func _build_item_row(slot: Dictionary) -> Control:
	var id: String = slot["id"]
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
	name_label.add_theme_color_override("font_color", RARITY_COLORS.get(ItemData.get_rarity(id), Color.WHITE))
	info.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = ItemData.get_item_description(id)
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_label)
	row.add_child(info)

	var cost: int = ItemData.get_buy_cost(id)
	var button := Button.new()
	if slot.get("sold", false):
		button.text = "SOLD"
		button.disabled = true
	else:
		button.text = "BUY (%d)" % cost
		button.disabled = player_manager.upgrade_items < cost
		button.pressed.connect(func():
			# try_buy_item() emits items_changed (-> _refresh()) internally,
			# BEFORE returning here - so slot.sold must be set and the panel
			# re-refreshed explicitly, or the SOLD state only shows up on the
			# panel's next unrelated refresh.
			if player_manager.try_buy_item(id):
				slot["sold"] = true
				_refresh()
		)
	row.add_child(button)

	return row


func close_menu():
	queue_free()
