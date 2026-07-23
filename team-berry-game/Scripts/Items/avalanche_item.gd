# res://Scripts/Items/avalanche_item.gd
# Enkratna uporaba (Epic): potisne VSAKEGA sovražnika na plošči 3 polja nazaj.
# "Nazaj" = FIKSNA smer (0,-1), proč od igralca (proti vrhu plošče, od koder
# megla/sovražniki izvirajo - glej GridManager.initialize_all_fog opombo) -
# za razliko od avalanche_horn (radialno OD IZBRANE TOČKE), tu ni izbrane
# točke (učinek je na CELI plošči), zato edina smiselna "nazaj" smer je
# enotna. Sovražnik, ki ga potisk ustavi PREJ kot za polnih 3 polja (blokiran
# z zidom/oviro/drugo figuro), se namesto tega zamrzne - brainstorm "pushed
# into a wall/obstacle are frozen". FREEZE_TURNS=2 (ne 1) - glej
# frozen_lure_item.gd-jevo opombo o effect_frozen_turns tick-timing hrošču.
extends BaseItem

const PUSH_DISTANCE := 3
const FREEZE_TURNS := 2
const PUSH_DIRECTION := Vector2i(0, -1)

func _init():
	id = "avalanche"

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	var enemies: Array[BaseCharacter] = []
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and c.is_enemy and not c.is_obstacle:
			enemies.append(c)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var origin: Vector2i = enemy.grid_pos
		var landed: Vector2i = grid_manager.push_character(enemy, PUSH_DIRECTION, PUSH_DISTANCE)
		var moved: int = absi(landed.y - origin.y)
		if moved < PUSH_DISTANCE:
			enemy.effect_frozen_turns = maxi(enemy.effect_frozen_turns, FREEZE_TURNS)
			enemy.was_frozen_by_player = true # item "cold_case" (Phase 5b)
	return true
