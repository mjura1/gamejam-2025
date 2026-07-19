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

# IMPOSSIBLE-tier AI positioning bonus (SettingsManager.ai_difficulty, gated behind
# the curse_synergy tier flag - see Scripts/AI/enemy_ai_strategy.gd and
# plans/AI_DIFFICULTY_PLAN.md §2.6): how much does ending THIS turn's move at
# candidate_pos help this curse's post-move on_action_taken effect. Called once per
# root candidate with the POST-move snapshot (owner already relocated to
# candidate_pos, any capture at candidate_pos already resolved) - Vector2i ->
# {is_enemy, is_obstacle, value, move_directions, move_range}, same shape
# enemy_ai_strategy.gd's search uses internally. 0 = no opinion (default - most
# curses don't need this; only override where POSITIONING genuinely changes the
# curse's outcome, e.g. "targets nearest visible" hooks where moving changes who's
# nearest).
func ai_positioning_bonus(_owner, _candidate_pos: Vector2i, _snapshot: Dictionary) -> float:
	return 0.0
