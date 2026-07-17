# res://Scripts/Items/base_item.gd
# Osnovni razred za shop iteme - variante (glej extra_move_item.gd) samo
# nastavijo id in prepišejo apply(). Enak vzorec kot pri figurah (1 osnovni
# razred, variante zamenjajo id/ime/sprite/učinek preko ItemData/JSON).
class_name BaseItem
extends RefCounted

var id: String = ""

func display_name() -> String:
	return ItemData.get_item_name(id)

func icon_texture() -> Texture2D:
	return load("res://Assets/Sprites/item_%s.png" % id)

# battle_controller: BattleController; grid_pos: celica, kamor je bil item spuščen.
# Vrne true, če je item na tem mestu sploh uporaben. Osnovno: kadarkoli je na
# vrsti igralec.
func can_use(battle_controller, _grid_pos: Vector2i) -> bool:
	return battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN

# Izvede učinek. Vrne true ob uspehu (klicatelj nato porabi 1x iz inventarja).
func apply(_battle_controller, _grid_pos: Vector2i) -> bool:
	return false
