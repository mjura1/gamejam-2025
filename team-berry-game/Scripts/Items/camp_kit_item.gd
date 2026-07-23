# res://Scripts/Items/camp_kit_item.gd
# Enkratna uporaba: quick_step za CELO zavezniško ekipo naenkrat - počisti
# snow_frozen/snow_trapped_turns/effect_frozen_turns na vsaki živi zavezniški
# figuri (isti "obe zamrznitveni mehaniki" razlog kot quick_step_item.gd -
# resnično zamrznjena figura je lahko zamrznjena od katerekoli).
extends BaseItem

func _init():
	id = "camp_kit"

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character) or not (character is BaseCharacter):
			continue
		if character.is_enemy or character.is_obstacle:
			continue
		character.snow_frozen = false
		character.snow_trapped_turns = 0
		character.effect_frozen_turns = 0
	return true
