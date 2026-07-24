# res://Scenes/Menu/ShopBuyPanel.gd
# Trgovina - nakup: ena vrstica na rolan slot (glej ShopController.stock,
# SHOP_V2_PLAN Phase 2). Slot je {"id": String, "sold": bool}; ShopController
# nastavi `stock` na to sceno pred add_child. Gumb BUY je onemogočen, če
# igralec nima dovolj upgrade_items; kupljen slot postane SOLD in ostane
# onemogočen (brez re-buy) do naslednjega obiska trgovine.
extends CanvasLayer

@onready var player_manager = get_node("/root/PlayerManager")

@onready var items_label: Label = %ItemsLabel
@onready var item_list: VBoxContainer = %ItemList
@onready var back_button: Button = %BackButton

var stock: Array = []

# Nakup + slot["sold"] oboje sprožita _refresh() (items_changed signal PA
# eksplicitni klic spodaj) - brez debounca bi to podrlo/zgradilo cel seznam
# dvakrat na en klik. call_deferred zbere oba klica v enega ob koncu frame-a.
var _refresh_pending := false


func _ready():
	player_manager.items_changed.connect(_request_refresh)
	back_button.pressed.connect(close_menu)
	_refresh()


func _request_refresh():
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_do_refresh")


func _do_refresh():
	_refresh_pending = false
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
	name_label.add_theme_color_override("font_color", ItemData.get_rarity_color(id))
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
			# try_buy_item() emits items_changed (-> _request_refresh())
			# internally, BEFORE returning here - so slot.sold must be set
			# and refresh re-requested explicitly, or the SOLD state only
			# shows up on the panel's next unrelated refresh. Both requests
			# coalesce into one rebuild via the debounce above.
			if player_manager.try_buy_item(id):
				slot["sold"] = true
				_request_refresh()
		)
	row.add_child(button)

	return row


func close_menu():
	queue_free()
