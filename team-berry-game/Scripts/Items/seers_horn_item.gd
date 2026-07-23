# res://Scripts/Items/seers_horn_item.gd
# Enemy-move-reveal chain: warhorn(U, all enemies, this turn) -> storm_horn(R,
# all enemies, next 2 turns) -> seers_horn (E, ONE chosen enemy) -> Oracle
# Glass(L, existing, all enemies every turn). Cilj (grid_pos) mora biti
# sovražnik, ki je igralca ŽE opazil (has_spotted_player) - calculate_best_move()
# je sicer varen za bralni klic (ne premakne, ne porabi proračuna), a
# dormantnega sovražnika (has_spotted_player == false) bi PRVI klic
# "prebudil" (glej base_character.calculate_best_move "Wake-up turn" veja) -
# torej bi uporaba itema na dormantnem sovražniku ta sam po sebi predčasno
# razkrila igralca njemu. can_use() to prepreči.
extends BaseItem

func _init():
	id = "seers_horn"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	return target is BaseCharacter and target.is_enemy and not target.is_obstacle \
		and target.has_spotted_player

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	var action: Dictionary = target.calculate_best_move()
	if action.is_empty():
		return false
	if is_instance_valid(battle_controller.move_highlighter):
		var tiles: Array[Vector2i] = [action["target_pos"]]
		battle_controller.move_highlighter.show_oracle_targets(tiles)
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
