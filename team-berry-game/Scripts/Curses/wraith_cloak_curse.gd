# res://Scripts/Curses/wraith_cloak_curse.gd
# Prekletstvo "wraith_cloak": nosilec je ob dodelitvi prekletstva TAKOJ
# pokrit s svojo (počasi razpadajočo) prekletstveno meglo na LASTNEM polju
# (glej on_applied - kliče se iz base_character.apply_curse, torej PREDEN se
# nosilec sploh prvič premakne). Namerno NEMA on_action_taken preglasitve -
# ko se prvič premakne, ostane stara megla na STARI (zdaj prazni) poziciji in
# preprosto sama razpade (tick_curse_fog_decay) - "ambush", ki enkrat izrabljen
# ne skriva več.
extends BaseCurse

func _init():
	id = "wraith_cloak"

func on_applied(owner) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(owner.grid_manager):
		return
	var ticks_per_stage: int = CurseData.get_param(id, "decay_ticks_per_stage", 2)
	owner.grid_manager.cover_area_curse([owner.grid_pos], ticks_per_stage, CurseData.get_color(id))
