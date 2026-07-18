# res://Scripts/CharacterPieces/Ally/wolf.gd
# Item "bloodhounds": prijazen volk, priklican vsako bitko, ki deluje sam
# (glej BattleController._move_autonomous_allies) takoj po igralčevi potezi.
# Nima sposobnosti in ni del trajnega rosterja (glej PlayerManager.
# add_temporary_ally/remove_converted_ally - routes through the
# is_converted_ally death path, glej BattleController spawn mesto).
extends BaseCharacter

func _ready():
	move_range = 2
	strName = "wolf"
	is_autonomous = true
	super._ready()

func get_move_directions() -> Array[Vector2i]:
	return [
		Vector2i( 1,  0),
		Vector2i(-1,  0),
		Vector2i( 0,  1),
		Vector2i( 0, -1),
		Vector2i( 1,  1),
		Vector2i( 1, -1),
		Vector2i(-1,  1),
		Vector2i(-1, -1),
	]

# Ne podeduje BaseCharacter.calculate_best_move() (ta se zgodi SAMO za
# is_enemy). Volk je zaveznik, a se premika kot enostaven AI: 1) zajemi
# sovražnika, če je na dosegu; 2) sicer se premakni proti najbližjemu
# živemu sovražniku; 3) če ni sovražnikov ali ni veljavnih tarč, obstani.
func calculate_best_move() -> Dictionary:
	var valid_targets := calculate_valid_targets()
	if valid_targets.is_empty():
		return {}

	for pos in valid_targets:
		var target_char = grid_manager.get_character_at(pos)
		if target_char and target_char.is_enemy and not target_char.is_obstacle:
			return {"move_type": "CAPTURE", "target_pos": pos}

	var nearest_enemy: BaseCharacter = null
	var nearest_dist := INF
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character) or not (character is BaseCharacter):
			continue
		if not character.is_enemy or character.is_obstacle:
			continue
		var dist = grid_pos.distance_to(character.grid_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_enemy = character

	if nearest_enemy == null:
		return {}

	var best_move: Vector2i = valid_targets[0]
	var best_score := INF
	for pos in valid_targets:
		var score = pos.distance_to(nearest_enemy.grid_pos)
		if score < best_score:
			best_score = score
			best_move = pos

	return {"move_type": "MOVE", "target_pos": best_move}
