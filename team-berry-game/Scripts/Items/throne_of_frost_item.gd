# res://Scripts/Items/throne_of_frost_item.gd
# Artefakt (Legendary), 1x na bitko, drag-in-poraba brez porabe iz inventarja
# (isti "1x na bitko" vzorec kot winter_general/drillmaster, glej
# battle_ui.use_item() poseben primer) - grid_pos je nepomemben, učinek je
# vedno na igralčevem kralju. King.move_range je bil vrnjen nazaj na pravi
# šahovski 1 (glej king.gd opombo - prej 12, strogo boljše od kraljičinega 8,
# kar je to bitko naredilo neuporabno) - zdaj ta artefakt dejansko nekaj
# podeli: king.move_range postane kraljičin 8 SAMO za TO potezo (glej
# BattleController.throne_of_frost_active_king - povrnjeno na začetku
# naslednje igralčeve poteze, isti "traja do naslednjega start_player_turn()"
# vzorec kot Knight.Evade/spectral_queen).
extends BaseItem

const QUEEN_MOVE_RANGE := 8

func _init():
	id = "throne_of_frost"

func _king(battle_controller) -> BaseCharacter:
	if not is_instance_valid(battle_controller.grid_manager):
		return null
	for character in battle_controller.grid_manager.get_all_characters():
		if character is BaseCharacter and not character.is_enemy and not character.is_obstacle \
				and character.strName == "king":
			return character
	return null

func can_use(battle_controller, _grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, _grid_pos):
		return false
	return _king(battle_controller) != null

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	var king := _king(battle_controller)
	if king == null:
		return false
	king.move_range = QUEEN_MOVE_RANGE
	battle_controller.throne_of_frost_active_king = king
	return true
