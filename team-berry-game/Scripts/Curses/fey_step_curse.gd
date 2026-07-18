# res://Scripts/Curses/fey_step_curse.gd
# Prekletstvo "fey_step": nosilec NE SME zajemati (glej can_capture() in
# base_character.calculate_best_move, ki s tem odstrani zajetja iz njegovih
# veljavnih ciljev) - v zameno ima po vsakem premiku možnost dodatnega
# "blink" skoka na naključno prazno polje znotraj dosega.
extends BaseCurse

func _init():
	id = "fey_step"

func can_capture() -> bool:
	return false

func on_action_taken(owner, _bc) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(owner.grid_manager):
		return
	var chance: float = CurseData.get_param(id, "blink_chance", 0.5)
	if randf() >= chance:
		return

	var blink_range: int = CurseData.get_param(id, "blink_range", 2)
	var used_rect: Rect2i = owner.tile_map.get_used_rect() if is_instance_valid(owner.tile_map) else Rect2i()
	var candidates: Array[Vector2i] = []
	for dx in range(-blink_range, blink_range + 1):
		for dy in range(-blink_range, blink_range + 1):
			if dx == 0 and dy == 0:
				continue
			var pos: Vector2i = owner.grid_pos + Vector2i(dx, dy)
			if not owner.grid_manager.is_inside_boundary(pos, used_rect):
				continue
			if owner.grid_manager.is_occupied(pos):
				continue
			candidates.append(pos)

	if candidates.is_empty():
		return

	var target: Vector2i = candidates[randi() % candidates.size()]
	owner.grid_manager.vacate(owner.grid_pos)
	owner.grid_pos = target
	owner.grid_manager.occupy(target, owner)
	owner.slide_to(owner.grid_manager.grid_to_world(target))
