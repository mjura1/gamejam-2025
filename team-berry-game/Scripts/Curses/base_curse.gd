# res://Scripts/Curses/base_curse.gd
class_name BaseCurse
extends RefCounted
# Ogrodje prekletstev: 1 osnovni razred, variante povozijo kavlje - enak
# vzorec kot pieces (base_character) in itemi (base_item).

var id: String = ""

func display_name() -> String: return CurseData.get_curse_name(id)
func description() -> String: return CurseData.get_curse_description(id)
func color() -> Color: return CurseData.get_color(id)

# Koliko DODATNIH akcij ima ta sovražnik v sovražnikovi potezi (frenzy).
func extra_actions() -> int: return 0

# Kavelj: pokliče se PO vsaki uspešno izvedeni akciji tega sovražnika
# (BattleController._take_enemy_action). owner: BaseCharacter, bc: BattleController.
func on_action_taken(_owner, _bc) -> void: pass

# Besedilo za STATUS/inspekcijo v battle UI.
func status_text() -> String: return "CURSED: %s" % display_name()
