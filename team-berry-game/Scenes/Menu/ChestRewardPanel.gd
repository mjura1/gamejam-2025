# res://Scenes/Menu/ChestRewardPanel.gd
# Reveal zaslon po odprtju zaklada (glej Scripts/Map/treasure.gd) - en row na
# item v loot. CONTINUE/Escape morata storiti isto (queue_free + return_to_map)
# - za razliko od ShopBuyPanel/ShopSellPanel tu ni "podležeče" trgovine, h
# kateri bi se Escape lahko samo vrnil, skrinja je že odprta.
extends CanvasLayer

@onready var item_list: VBoxContainer = %ItemList
@onready var continue_button: Button = %ContinueButton

var loot: Array = []


func _ready():
	continue_button.pressed.connect(_on_continue_pressed)
	for id in loot:
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
	name_label.add_theme_color_override("font_color", ItemData.get_rarity_color(id))
	info.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = ItemData.get_item_description(id)
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_label)
	row.add_child(info)

	return row


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		_on_continue_pressed()


func _on_continue_pressed():
	queue_free()
	GF.return_to_map()
