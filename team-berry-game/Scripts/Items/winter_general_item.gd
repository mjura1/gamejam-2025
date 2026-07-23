# res://Scripts/Items/winter_general_item.gd
# Artefakt (Epic), 1x na bitko: zamrzne vsakega SOVRAŽNIKA znotraj 2 polj
# (kvadratni radius, glej GridManager.square_radius_tiles) OKROG igralčevega
# kralja. "kind: artifact", NE "passive" kot brainstorm pravi - isti razlog kot
# drillmaster (glej NEW_ITEMS_WAVE2_PLAN.md §1a gotcha): brez samodejnega
# sprožilnega pogoja (za razliko od queens_gambit/frozen_vanguard, ki se
# sprožita OB zajetju), zato mora biti igralčevo-sprožen, kar battle_ui
# arhitektura dovoli samo "artifact" itemom. Drag-sprožen kot drillmaster/
# frozen_rampart (glej battle_ui.use_item() poseben primer) - grid_pos
# (kamor je bil spuščen) je NEPOMEMBEN, učinek je vedno centriran na kralja,
# zato get_aim_cells() ne vrne ničesar (ni smiselnega predogleda vezanega na
# kazalec).
extends BaseItem

const FREEZE_TURNS := 2 # +1 korekcija za sovražnika, glej §1a effect_frozen_turns gotcha
const RADIUS := 2

func _init():
	id = "winter_general"

func _kings(battle_controller) -> Array[BaseCharacter]:
	var kings: Array[BaseCharacter] = []
	if not is_instance_valid(battle_controller.grid_manager):
		return kings
	for character in battle_controller.grid_manager.get_all_characters():
		if character is BaseCharacter and not character.is_enemy and not character.is_obstacle \
				and character.strName == "king":
			kings.append(character)
	return kings

func can_use(battle_controller, _grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, _grid_pos):
		return false
	return not _kings(battle_controller).is_empty()

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	var kings := _kings(battle_controller)
	if kings.is_empty():
		return false
	for king in kings:
		for pos in GridManager.square_radius_tiles(king.grid_pos, RADIUS):
			var target = grid_manager.get_character_at(pos)
			if target is BaseCharacter and target.is_enemy and not target.is_obstacle:
				target.effect_frozen_turns = maxi(target.effect_frozen_turns, FREEZE_TURNS)
				target.was_frozen_by_player = true # item "cold_case" (Phase 5b)
	return true
