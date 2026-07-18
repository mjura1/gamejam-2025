# res://Scripts/Curses/snowfall_curse.gd
# Prekletstvo "snowfall": nosilec po vsakem premiku znova pokrije 3x3
# območje okoli sebe z meglo (glej GridManager.cover_area - Phase 2).
extends BaseCurse

func _init():
	id = "snowfall"
