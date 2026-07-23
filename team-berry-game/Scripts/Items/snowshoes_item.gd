# res://Scripts/Items/snowshoes_item.gd
# Enkratna uporaba: cilj (grid_pos) je nepomemben, kot pri extra_move_item.gd.
# Samo naravna zastavico na BattleController za TO potezo - dejansko razkritje
# poti se zgodi v base_character.execute_move(), ki to zastavico prebere ob
# vsakem premiku zaveznika (glej tam).
extends BaseItem

func _init():
	id = "snowshoes"

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	battle_controller.snowshoes_active_this_turn = true
	return true
