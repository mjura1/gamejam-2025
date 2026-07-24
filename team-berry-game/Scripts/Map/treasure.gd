# res://Scripts/Map/treasure.gd
# Zaklad: cela soba na sredini mape (item soba, glej TREASURE_CHEST_PLAN.md),
# nagrada se met/podeli šele ob kliku na skrinjo (ne ob vstopu v sceno). Ni
# LEAVE gumba - edina pot nazaj na mapo je prek ChestRewardPanel CONTINUE
# (skrinja mora biti odprta, glej §3 M3 plana).
extends Control
class_name TreasureController

const CHEST_REWARD_PANEL_SCENE := preload("res://Scenes/Menu/ChestRewardPanel.tscn")

@onready var chest_button: TextureButton = %ChestButton

var opened := false


func _ready():
	chest_button.pressed.connect(_on_chest_pressed)


func _on_chest_pressed():
	if opened:
		return
	opened = true
	UiAudio.play_click()
	chest_button.disabled = true

	var luck := PlayerManager.get_luck()
	# Item "fate_weaver": vsak zaklad vsebuje vsaj 1 artefakt, ne glede na
	# tier/luck (glej ItemData.roll_treasure_loot min_artifact_count).
	var min_artifacts: int = 1 if PlayerManager.has_passive("fate_weaver") else 0
	var loot := ItemData.roll_treasure_loot(PlayerManager.current_map_tier, luck,
		null, PlayerManager.get_unstackable_owned_ids(), min_artifacts)
	for id in loot:
		PlayerManager.add_item(id, 1)

	var upgrade_items_reward := ItemData.get_treasure_upgrade_items(PlayerManager.current_map_tier)
	PlayerManager.add_upgrade_items(upgrade_items_reward)

	var panel := CHEST_REWARD_PANEL_SCENE.instantiate()
	panel.name = "ChestRewardPanelNode"
	panel.loot = loot
	panel.upgrade_items_reward = upgrade_items_reward
	get_tree().root.add_child(panel)
