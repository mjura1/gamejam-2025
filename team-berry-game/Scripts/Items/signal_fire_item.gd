# res://Scripts/Items/signal_fire_item.gd
# Enkratna uporaba: razkrije trenutno polje VSAKE figure na plošči (obeh
# strani, brez ovir) - kot flare/night_watch, permanenten reveal_area() na
# vsa ta polja (isti "reveal_area je EDINA prava fog-clear pot" vzorec kot
# povsod drugod - glej NEW_ITEMS_WAVE2_PLAN.md §1). "fading out after ~5s" iz
# brainstorm opisa velja SAMO za vizualni pulz-poudarek (glej
# MoveHighlighter.show_signal_pulse) - razkrita polja ostanejo razkrita
# trajno, enako kot vsak drug reveal item v tej igri (v tem projektu ne
# obstaja "začasno vidno skozi meglo brez dejanskega razkritja" koncept).
# Ni ciljano na grid_pos (učinek je na celi plošči, spustljivo kamorkoli) -
# get_aim_cells nima dostopa do battle_controller (glej BaseItem signature),
# zato ne more predogledati dejanskih figurnih polj med vlečenjem; ostane
# privzeto prazen (brez aim predogleda), sprejemljiva vrzel za item brez
# pravega "cilja".
extends BaseItem

func _init():
	id = "signal_fire"

func _piece_positions(battle_controller) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for character in battle_controller.grid_manager.get_all_characters():
		if character is BaseCharacter and not character.is_obstacle:
			positions.append(character.grid_pos)
	return positions

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	var positions := _piece_positions(battle_controller)
	battle_controller.grid_manager.reveal_area(positions)
	if is_instance_valid(battle_controller.move_highlighter):
		battle_controller.move_highlighter.show_signal_pulse(positions)
	return true

func get_aim_cells(_grid_pos: Vector2i) -> Array[Vector2i]:
	return []
