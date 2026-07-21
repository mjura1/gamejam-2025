extends Control
class_name PostBattleSummary

signal continue_pressed
signal back_pressed

func _ready():
	%ContinueButton.pressed.connect(func(): UiAudio.play_click(); continue_pressed.emit())
	%BackButton.pressed.connect(func(): UiAudio.play_click(); back_pressed.emit())

func setup_victory(friendly_party: Array, enemy_party: Array, new_friendly_piece: String,
		new_enemy_piece: String, upgrade_items_gained: int) -> void:
	%TitleLabel.text = "VICTORY"
	%VictoryContent.visible = true
	%DefeatContent.visible = false
	_populate_party_row(%MineRow, friendly_party, new_friendly_piece)
	_populate_party_row(%EnemyRow, enemy_party, new_enemy_piece)
	_populate_rewards(upgrade_items_gained)

func setup_defeat(final_tier: int, final_floor: int) -> void:
	%TitleLabel.text = "DEFEAT"
	%VictoryContent.visible = false
	%DefeatContent.visible = true
	%FinalFloorLabel.text = "Final Floor: %d" % (final_tier + 1)
	%FinalRoomLabel.text = "Final Room: %d" % final_floor

func _populate_party_row(row: Container, roster: Array, new_piece_name: String) -> void:
	for child in row.get_children():
		child.queue_free()
	# The new/highlighted icon (if any) is always added LAST, regardless of
	# where it falls in the roster array - keeps it on the same side of the
	# row for both MINE and ENEMY (their roster arrays don't share ordering
	# conventions for where a freshly-appended piece lands).
	var claimed := false
	var new_icon: PieceIcon = null
	for roster_name in roster:
		var icon := PieceIcon.new()
		icon.setup(roster_name, null)
		if not claimed and new_piece_name != "" and roster_name == new_piece_name:
			icon.set_highlighted(true)
			icon.set_slot_label("+")
			claimed = true
			new_icon = icon
		else:
			icon.set_benched(true)
			row.add_child(icon)
	if new_icon != null:
		row.add_child(new_icon)

func _populate_rewards(upgrade_items_gained: int) -> void:
	for child in %RewardsList.get_children():
		child.queue_free()
	if upgrade_items_gained > 0:
		%RewardsList.add_child(_build_reward_row("UPGRADE ITEMS", upgrade_items_gained))

func _build_reward_row(label_text: String, amount: int) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var amount_label := Label.new()
	amount_label.text = "x%d" % amount
	amount_label.add_theme_font_size_override("font_size", 16)
	row.add_child(amount_label)
	return row
