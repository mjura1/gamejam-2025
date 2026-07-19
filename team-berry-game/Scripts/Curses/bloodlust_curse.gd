# res://Scripts/Curses/bloodlust_curse.gd
# Prekletstvo "bloodlust": po USPEŠNEM ZAJETJU (ne po navadnem premiku) dobi
# nosilec eno dodatno akcijo TAKOJ v isti sovražnikovi potezi (glej
# BattleController.start_enemy_turn - "was_capture" veja). Omejeno na
# max_bonus_actions na potezo (GameParameters/curses.json), da verižno zajemanje ne
# more pomesti celotne plošče v enem krogu - namerno zelo redko (nizka
# weight), glej curses.json.
extends BaseCurse

func _init():
	id = "bloodlust"

func grants_bonus_action_on_capture() -> bool:
	return true
