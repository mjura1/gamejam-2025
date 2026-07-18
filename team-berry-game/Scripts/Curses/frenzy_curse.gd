# res://Scripts/Curses/frenzy_curse.gd
# Prekletstvo "frenzy": nosilec deluje dvakrat v vsaki sovražnikovi potezi
# (glej BattleController.start_enemy_turn()).
extends BaseCurse

func _init():
	id = "frenzy"

func extra_actions() -> int:
	return CurseData.get_param(id, "extra_actions", 1)
