# res://Scripts/Items/time_dilation_item.gd
# Enkratna uporaba (Epic): dovoli premik/zajetje DRUGE figure to potezo (ne
# ISTE figure dvakrat, za razliko od extra_move, ki samo doda +1 v skupni
# proračun brez omejitve KATERA figura ga porabi - glej
# NEW_ITEMS_WAVE2_PLAN.md §7 research: moves_remaining nima nobene identitete
# figure). Grid_pos je nepomemben (ni ciljano) - apply() samo naredi dvoje: (1)
# add_bonus_move() (isti +1 kot extra_move, brez tega bi moves_remaining padel
# na 0 po prvi potezi in can_move() bi blokiral karkoli drugega), (2) postavi
# time_dilation_active_this_turn - base_character.try_move() to prebere in
# zavrne PONOVNO izbiro figure, ki je to potezo ŽE bila v
# battle_controller.moved_this_turn (glej tam in execute_move(), ki polni ta
# seznam).
extends BaseItem

func _init():
	id = "time_dilation"

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	battle_controller.time_dilation_active_this_turn = true
	battle_controller.add_bonus_move()
	return true
