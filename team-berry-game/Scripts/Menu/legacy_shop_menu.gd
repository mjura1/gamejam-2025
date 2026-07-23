# res://Scripts/Menu/legacy_shop_menu.gd
# Poln scene swap (ne overlay panel - glej mode-select context v
# plans/META_PROGRESSION_PLAN.md §2e), doseg prek GF.start_legacy_shop().
# Troši MetaProgress.legacy_points proti GameParameters/meta_upgrades.json.
extends Control

@onready var points_label: Label = %PointsLabel
@onready var upgrade_list: VBoxContainer = %UpgradeList
@onready var back_button: Button = %BackButton

func _ready():
	back_button.pressed.connect(_on_back_pressed)
	_refresh()

func _refresh():
	points_label.text = "LEGACY POINTS: %d" % MetaProgress.legacy_points
	for child in upgrade_list.get_children():
		child.queue_free()
	for def in MetaUpgradeData.get_upgrades():
		upgrade_list.add_child(_build_upgrade_row(def))

# Zrcali CampfireUpgradePanel._build_node_button
# (Scenes/Menu/CampfireUpgradePanel.gd:110-135) skoraj dobesedno, proti
# MetaProgress namesto PlayerManager/SkillTreeData. Tu strnjeno v eno
# "disabled" stanje namesto treh ločenih besedil (excluded/locked/predrag) -
# implementatorjeva odločitev, ni load-bearing.
func _build_upgrade_row(def: Dictionary) -> Control:
	var id: String = def.get("id", "")
	var upgrade_name: String = def.get("name", "-")
	var cost: int = int(def.get("cost", 0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = upgrade_name
	info.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = def.get("desc", "")
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_label)
	row.add_child(info)

	var button := Button.new()
	if MetaProgress.has_upgrade(id):
		button.text = "✔ Unlocked"
		button.disabled = true
	elif not MetaProgress.can_buy_upgrade(id):
		button.text = "%s (%d)" % [upgrade_name, cost]
		button.disabled = true
	else:
		button.text = "BUY (%d)" % cost
		button.disabled = false
		button.pressed.connect(func():
			if MetaProgress.try_buy_upgrade(id):
				_refresh()
		)
	row.add_child(button)
	return row

func _on_back_pressed():
	UiAudio.play_click()
	GF.return_to_main_menu()
