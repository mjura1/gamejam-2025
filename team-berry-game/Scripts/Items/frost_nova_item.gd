# res://Scripts/Items/frost_nova_item.gd
# Enkratna uporaba: zamrzne vsakega SOVRAŽNIKA na enem od 8 sosednjih polj
# (ne diagonale-samo, glej map_behaviour._has_adjacent_enemy za isto
# definicijo "adjacent" v tej igri) okoli grid_pos - grid_pos sam NI zamrznjen
# (samo "sosednji", brainstorm besedilo). grid_pos ne rabi biti zaseden -
# "chosen piece" se bere kot "chosen tile", enostavnejše in skladno z drugimi
# consumable itemi brez ciljne-figure zahteve.
#
# FREEZE_TURNS=2, NE 1: glej frozen_lure_item.gd-jevo opombo o
# effect_frozen_turns tick-timing hrošču (NEW_ITEMS_WAVE2_PLAN.md §1a) - ista
# +1 korekcija velja za VSAK item, ki zamrzne SOVRAŽNIKA.
extends BaseItem

const FREEZE_TURNS := 2

func _init():
	id = "frost_nova"

func _ring_tiles(grid_pos: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			tiles.append(grid_pos + Vector2i(dx, dy))
	return tiles

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	for pos in _ring_tiles(grid_pos):
		var target = grid_manager.get_character_at(pos)
		if target is BaseCharacter and target.is_enemy and not target.is_obstacle:
			target.effect_frozen_turns = maxi(target.effect_frozen_turns, FREEZE_TURNS + PlayerManager.cold_resistance_bonus())
			target.was_frozen_by_player = true # item "cold_case" (Phase 5b)
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return _ring_tiles(grid_pos)
