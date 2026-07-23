# res://Scripts/Items/winters_bargain_item.gd
# Artefakt (Epic), 1x na bitko: žrtvuje naključen NEPORABLJEN consumable iz
# inventarja (kind == "consumable", count > 0 - "unused" bere se kot "trenutno
# v lasti", ne kot ločen per-battle-charge koncept, ki v tem sistemu ne
# obstaja, glej §1a gotcha o PlayerManager.owned_items nimanju
# nabojev/cooldownov) in v zameno počisti VSE statusne učinke cele zavezniške
# ekipe (effect_frozen_turns/stunned_turns/rooted_turns/snow_frozen) ter
# postavi PlayerManager.pending_move_bonus_next_battle - +1 premik na PRVO
# potezo NASLEDNJE bitke (glej BattleController.start_player_turn(), edini
# bralec te zastavice). Deviacija od brainstorma ("once per floor"): "floor"
# v tej kodi je lahko katerakoli soba (bitka/trgovina/počivališče/zaklad,
# glej Scripts/Map/map_point.gd RoomType) - ni per-battle koncepta ločenega
# od "per floor", zato je "once per battle" edina smiselna, testljiva
# interpretacija (isti razred odločitve kot drugi Phase 5 "kind" popravki).
# kind: "artifact", NE "passive" - isti razlog kot drillmaster/winter_general
# (§1a gotcha, player-initiated brez samodejnega sprožilnega pogoja).
extends BaseItem

func _init():
	id = "winters_bargain"

func _sacrifice_candidates(battle_controller) -> Array:
	var player_manager = battle_controller.player_manager
	var ids: Array = []
	for owned_id in player_manager.owned_items.keys():
		if owned_id == id:
			continue
		if ItemData.get_kind(owned_id) == "consumable" and player_manager.owned_items[owned_id] > 0:
			ids.append(owned_id)
	return ids

func can_use(battle_controller, _grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, _grid_pos):
		return false
	return not _sacrifice_candidates(battle_controller).is_empty()

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	var player_manager = battle_controller.player_manager
	var candidates := _sacrifice_candidates(battle_controller)
	if candidates.is_empty():
		return false
	player_manager.remove_item(candidates[randi() % candidates.size()])

	if is_instance_valid(battle_controller.grid_manager):
		for character in battle_controller.grid_manager.get_all_characters():
			if character is BaseCharacter and not character.is_enemy and not character.is_obstacle:
				character.effect_frozen_turns = 0
				character.stunned_turns = 0
				character.rooted_turns = 0
				character.snow_frozen = false
				character.snow_trapped_turns = 0

	player_manager.pending_move_bonus_next_battle = true
	return true
