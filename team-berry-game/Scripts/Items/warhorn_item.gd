# res://Scripts/Items/warhorn_item.gd
# Enkratna uporaba: cilj (grid_pos) je nepomemben. Prikaže predvideno ciljno
# polje vsakega sovražnika, ki je igralca že opazil (glej
# BattleController._compute_enemy_planned_targets - artefakt "oracle_glass"
# uporablja isto funkcijo samodejno vsako potezo, ta item pa jo sproži enkrat
# na klic).
extends BaseItem

func _init():
	id = "warhorn"

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	if is_instance_valid(battle_controller.move_highlighter):
		battle_controller.move_highlighter.show_oracle_targets(battle_controller._compute_enemy_planned_targets())
	return true
