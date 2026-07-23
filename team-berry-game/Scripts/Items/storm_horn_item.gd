# res://Scripts/Items/storm_horn_item.gd
# Enemy-move-reveal chain: Warhorn(U, this turn only) -> storm_horn (R, next
# 2 enemy turns) -> seers_horn (E) -> Oracle Glass(L, existing). Ista
# show_oracle_targets()/_compute_enemy_planned_targets() mehanika kot
# warhorn_item.gd - razlika je SAMO v tem, da start_enemy_turn() spodaj
# preskoči clear_oracle_targets() dokler battle_controller.
# storm_horn_turns_remaining > 0 (glej BattleController.gd). Ista snapshot
# ostane vidna (namerno NI osvežena vsako potezo) - "persists", ne "refreshes".
extends BaseItem

const PERSIST_ENEMY_TURNS := 2

func _init():
	id = "storm_horn"

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	battle_controller.storm_horn_turns_remaining = PERSIST_ENEMY_TURNS
	if is_instance_valid(battle_controller.move_highlighter):
		battle_controller.move_highlighter.show_oracle_targets(battle_controller._compute_enemy_planned_targets())
	return true
