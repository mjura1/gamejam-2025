extends BaseCharacter

func _ready():
	# Vitez se premika le za en korak v smeri "L"
	move_range = 1
	strName = "knight"
	super._ready()

# KLJUČNA SPREMEMBA: Sedaj implementira get_move_directions()
func get_move_directions() -> Array[Vector2i]:
	return KNIGHT_OFFSETS
# calculate_valid_targets() se podeduje

# ----------------- SPOSOBNOSTI -----------------

const ABILITY_DEFS = [
	{
		"id": "evade", "name": "Evade", "needs_target": false,
		"base": {"desc": "This knight cannot be captured until your next turn."},
		"mid": {"desc": "This knight cannot be captured until your next turn."},
		"upgraded": {"desc": "This knight cannot be captured until your next turn."},
	},
	{
		"id": "reposition", "name": "Reposition", "needs_target": true,
		"base": {"desc": "Make an extra move with this knight without ending your turn."},
		"mid": {"desc": "Make an extra move with this knight without ending your turn."},
		"upgraded": {"desc": "Make an extra move with this knight without ending your turn."},
	},
	{
		"id": "ambush", "name": "Ambush", "needs_target": true,
		"base": {"radius": 3, "desc": "Jump to any snow-free empty tile within 3 tiles."},
		"mid": {"radius": 4, "desc": "Jump to any snow-free empty tile within 4 tiles."},
		"upgraded": {"radius": 5, "desc": "Jump to any snow-free empty tile within 5 tiles."},
	},
]

func get_ability_defs() -> Array:
	return ABILITY_DEFS

func get_ability_targets(slot: int) -> Array[Vector2i]:
	if slot == 2:
		return calculate_valid_targets()
	if slot == 3:
		return _ambush_targets(_tier_data(3).get("radius", 3))
	return []

# "Snow" tu je prekletstvena megla (curse_fog_nodes - Snowfall/Blizzard/
# Contagion), NE osnovna megla vojnega tumana (fog_nodes) - glej
# SKILL_TREE_PLAN.md §4.2.
func _ambush_targets(radius: int) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	for pos in GridManager.square_radius_tiles(grid_pos, radius):
		if pos == grid_pos:
			continue
		if not grid_manager.is_inside_boundary(pos, tile_map.get_used_rect()):
			continue
		if grid_manager.is_occupied(pos):
			continue
		if grid_manager.curse_fog_nodes.has(pos):
			continue
		targets.append(pos)
	return targets

func _execute_ability(id: String, target) -> bool:
	match id:
		"evade":
			is_capture_immune = true
			return true
		"reposition":
			return _do_reposition(target)
		"ambush":
			return _do_ambush(target)
	return false

# Vitez skoči (brez poti) na prazno, sneg-prosto polje - cilj je že
# filtriran skozi get_ability_targets(3), tu samo minimalna zaščita pred
# skokom na zasedeno polje (glej Bishop._do_longshot/Knight._do_reposition
# za enak "zaupaj UI-ju" vzorec).
func _do_ambush(target: Vector2i) -> bool:
	if grid_manager.is_occupied(target):
		return false
	execute_move(target)
	return true

# Enak premik/zajetje kot try_move(), le da gre skozi ability sistem (porabi
# 1 uporabo Reposition za to bitko, ne navadnega premika).
func _do_reposition(target) -> bool:
	var target_char = grid_manager.get_character_at(target)
	if target_char and target_char.is_enemy != is_enemy:
		capture(target_char)
	else:
		execute_move(target)
	return true
