# res://Scripts/Items/aurora_flare_item.gd
# Enkratna uporaba: razkrije VSA polja plošče (oba sistema megle - glej
# GridManager.reveal_area). Namerno reveal_area namesto
# clear_all_fog()/clear_all_curse_fog() (te se uporabljajo samo za
# inicializacijo nove bitke in bi mid-battle počistile tudi
# ravens_eye_cleared) - poleg tega igralcu z artefaktom "ravens_eye" to
# NAMERNO trajno zaščiti CELO ploščo pred prekletstveno meglo za preostanek
# bitke (reveal_area sama doda vsako razkrito polje v ravens_eye_cleared).
extends BaseItem

func _init():
	id = "aurora_flare"

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	var used_rect: Rect2i = battle_controller.tile_map.get_used_rect()
	var all_tiles: Array[Vector2i] = []
	for x in range(used_rect.position.x, used_rect.end.x):
		for y in range(used_rect.position.y, used_rect.end.y):
			all_tiles.append(Vector2i(x, y))
	grid_manager.reveal_area(all_tiles)
	return true
