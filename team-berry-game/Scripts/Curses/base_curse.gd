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

# Fey Step: nosilec ne sme zajemati sovražnikovih (=igralčevih) figur -
# glej base_character.calculate_best_move, ki s tem odstrani zajetja iz
# njegovih veljavnih ciljev.
func can_capture() -> bool: return true

# Bloodlust: po USPEŠNEM ZAJETJU (ne po navadnem premiku) dobi nosilec eno
# dodatno akcijo TAKOJ - glej BattleController.start_enemy_turn(), ki po
# vsaki akciji preveri to zastavico namesto statičnega extra_actions().
func grants_bonus_action_on_capture() -> bool: return false

# Kavelj: pokliče se PO vsaki uspešno izvedeni akciji tega sovražnika
# (BattleController._take_enemy_action). owner: BaseCharacter, bc: BattleController.
func on_action_taken(_owner, _bc) -> void: pass

# Kavelj: pokliče se TAKOJ, ko je prekletstvo dodeljeno nosilcu (glej
# base_character.apply_curse) - za prekletstva, ki morajo nekaj postaviti
# PREDEN se nosilec sploh prvič premakne (Wraith Cloak).
func on_applied(_owner) -> void: pass

# Besedilo za STATUS/inspekcijo v battle UI.
func status_text() -> String: return "CURSED: %s" % display_name()
