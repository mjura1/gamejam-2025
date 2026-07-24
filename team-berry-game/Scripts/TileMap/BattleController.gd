extends Node
class_name BattleController

# ===============================================
# REFERENCE
# ===============================================

@onready var grid_manager: GridManager = get_node("../GridManager")
@onready var player_manager = get_node("/root/PlayerManager")
@onready var move_highlighter = get_node("../MoveHighlighter")
@onready var tile_map = get_node("../Map/TileMapLayer")
# NAMENOMA get_node(), ne bare "CurseData" identifikator - BattleController.gd
# ima class_name, torej ga --script/headless zgodnji "global class scan"
# eagerly prevede PREDEN so avtoloadi registrirani (ista opomba kot
# base_character.gd's "var curse"). Uporabljeno v start_enemy_turn()
# "bloodlust" bonus-akcija veji.
@onready var curse_data = get_node("/root/CurseData")

# Tutorial stopnje: scena lahko izklopi sovražnikovo AI (override na
# instanciranem BattleController vozlišču, glej Scenes/Tutorial/*). Privzeto
# true - živa battle.tscn ostane nespremenjena.
@export var ai_enabled: bool = true

# Sproži se ob vsaki spremembi stanja bitke (za battle UI: turn label,
# START/END TURN gumb, placement overlay).
signal state_changed(new_state)

# Sproži se ob vsaki spremembi moves_remaining/abilities_remaining (za
# battle UI prikaz nad turn labelom). Ločena proračuna - glej opombo pri
# moves_remaining spodaj za razlog.
signal moves_changed(remaining: int, max_moves: int)
signal abilities_changed(remaining: int, max_abilities: int)

# Item "bounty": sproži se, ko je tarča izbrana ob začetku prve poteze
# (battle_ui poveže to na _set_board_badge, glej start_player_turn()).
signal bounty_marked(character: BaseCharacter)

# Artefakt "prospectors_pick": enako kot bounty_marked, glej spodaj.
signal prospectors_pick_marked(character: BaseCharacter)

# Artefakt "golden_quarry" (Phase 5): enako kot bounty_marked, a sproži se
# DVAKRAT na bitko (glej start_player_turn - dve neodvisni naključni tarči).
signal golden_quarry_marked(character: BaseCharacter)

# Item "courier_package": enako kot bounty_marked, a za kurirja (glej
# start_player_turn()).
signal courier_marked(character: BaseCharacter)

# Item "old_guard": enako kot courier_marked, a za ločeno stanje (glej
# old_guard_sentry zgoraj).
signal old_guard_marked(character: BaseCharacter)

# Prekletstvo "stunning_gaze": character je bil pravkar omamljen (glej
# stunning_gaze_curse.gd.on_action_taken -> notify_stun spodaj) - battle_ui.gd
# poveže to na značko/STATUS.
signal piece_stunned(character: BaseCharacter)

# Prekletstvo "entangle": character je bil pravkar ukoreninjen (glej
# entangle_curse.gd.on_action_taken -> notify_root spodaj) - battle_ui.gd
# poveže to na značko/STATUS, enako kot piece_stunned.
signal piece_rooted(character: BaseCharacter)

# Snow rework: figura je bila pravkar zamrznjena (obkrožena s snegom na vseh
# 4 straneh SNOW_FREEZE_TURNS zaporednih potez) - glej
# _update_snow_freeze_states spodaj, battle_ui.gd poveže to na značko/STATUS.
signal piece_frozen(character: BaseCharacter)

# Snow rework pragi (glej _update_snow_freeze_states) - šteto v ZAPOREDNIH
# začetkih igralčevih potez, prebitih obkroženo s snegom.
const SNOW_FREEZE_TURNS := 1
const SNOW_DEATH_TURNS := 3

# Item "salvage": glej on_enemy_died() spodaj - placeholder odstotek, čaka na
# balance pass.
const SALVAGE_DROP_CHANCE := 0.25

# ENUM za stanja bitke
enum BattleState {
	INITIALIZING,
	PLACEMENT,
	PLAYER_TURN,
	ENEMY_TURN,
	TURN_END,
	GAME_OVER
}

var current_state: int = BattleState.INITIALIZING
var turn_count: int = 0

# Premiki/zajetja in sposobnosti imajo LOČENA proračuna v tej potezi - en
# skupen proračun (glej git history) je pustil igralcu premakniti 3 različne
# figure v eni potezi, kar je bilo preveč močno. Premiki ostanejo omejeni na
# player_manager.moves_per_turn (privzeto 1, kot pred ability sistemom),
# sposobnosti pa na player_manager.abilities_per_turn (privzeto 3) - glej
# start_player_turn(), consume_move(), consume_ability().
var moves_remaining: int = 0
var abilities_remaining: int = 0

# Item "vicious_knights": omejitev na 1x na potezo (Miha pre-approved balance
# limiter) - resetira se v start_player_turn().
var vicious_knight_used: bool = false

# Item "bounty": naključen sovražnik je označen ob začetku prve poteze v
# bitki (glej start_player_turn()); če je PRVI sovražnik, ki v tej bitki
# umre, igralec dobi nagrado (glej on_enemy_died()). Resetira se v
# initialize_battle().
var bounty_target: BaseCharacter = null
var first_enemy_death_resolved: bool = false

# Koliko sovražnikov je bilo na začetku TE bitke - active_enemies je ob
# enemyGone() prazen po definiciji, enemy_party pa raste čez cel run, zato
# nobeden od njiju ne odraža "koliko sovražnikov je bilo v tej bitki" (glej
# plans/META_PROGRESSION_PLAN.md §2d). Uporabljeno za legacy points formulo.
var battle_start_enemy_count: int = 0

# Artefakt "prospectors_pick": enak vzorec kot bounty_target/first_enemy_death_resolved
# zgoraj, ločen boolean/target ker gre za neodvisen item, tudi če sta obenem
# lastnina (oba mark-anta se lahko izplačata za isto smrt).
var prospectors_pick_target: BaseCharacter = null
var prospectors_pick_resolved: bool = false

# Item "courier_package": naključen živ zaveznik je izbran ob začetku prve
# poteze v bitki (izključuje volka - glej start_player_turn()); če preživi
# bitko do zmage, igralec dobi nagrado (glej check_battle_end() victory
# branch). Resetira se v initialize_battle().
var courier: BaseCharacter = null

# Item "old_guard": enak vzorec kot courier zgoraj, a ločeno stanje - neodvisen
# item, tudi če sta oba obenem v lasti (isti razlog kot bounty_target/
# prospectors_pick_target zgoraj). Resetira se v initialize_battle().
var old_guard_sentry: BaseCharacter = null

# Item "snowshoes": velja SAMO za to potezo - resetira se v start_player_turn().
# Prebere ga base_character.execute_move() ob vsakem zavezniškem premiku.
var snowshoes_active_this_turn: bool = false

# Artefakt "frozen_rampart": enkratna postavitev ovire na bitko, ki se NE
# porabi iz inventarja (glej battle_ui.gd.use_item() poseben primer).
# Resetira se v initialize_battle().
var frozen_rampart_used_this_battle: bool = false

# Item "night_watch": vsak označen sovražnik (lahko več, en na uporabo itema)
# dodatno razkrije SVOJE trenutno polje vsako potezo (glej
# update_fog_after_turn_start, watchtower-inline vzorec) - drži razkritje za
# preostanek bitke, tudi če se figura premakne pod svežo meglo. is_instance_valid
# skrbi za morebitne zajete/mrtve tarče (ostanejo v seznamu, a se preskočijo).
var night_watch_targets: Array[BaseCharacter] = []

# Item "loyal_pawns": enkrat na bitko - glej base_character.capture().
var loyal_pawns_used_this_battle: bool = false

# Item "nightfall_ward": PRVI(H) N zavezniških zamrznitev od snega v tej
# bitki (glej _update_snow_freeze_states spodaj) je preprečenih namesto da se
# zgodijo - za razliko od "warm_cloak" (trajno imunska ENA konkretna figura),
# to je "prihrani prve N zamrznitev KOGARKOLI" na celotno bitko. Deviacija od
# prvotne plan opombe ("prevents first effect_frozen_turns application") -
# glej NEW_ITEMS_WAVE2_PLAN.md za razlog (effect_frozen_turns trenutno nikoli
# ne prizadene zaveznika, zato bi bil kavelj mrtva koda; sneg pa je živa,
# takojšnja pot z natanko istim "prva zamrznitev" pomenom). ŠTEVEC, ne bool
# (Phase 2 ga je gradil kot bool - glej git zgodovino), ker item
# "frostguard_talisman" (Phase 4) N razširi z 1 na 2 - glej
# nightfall_ward_max_saves() spodaj.
var nightfall_ward_saves_used: int = 0

func nightfall_ward_max_saves() -> int:
	if not is_instance_valid(player_manager) or not player_manager.has_passive("nightfall_ward"):
		return 0
	return 2 if player_manager.has_passive("frostguard_talisman") else 1

# Item "knight_errant": enkrat NA POTEZO (isti vzorec/razlog kot
# vicious_knight_used spodaj - preprečuje neskončno verižno zajemanje) - glej
# map_behaviour.gd, ki po vsakem viteškem zajetju preveri obe pasivi.
var knight_errant_used_this_turn: bool = false

# Item "drillmaster": enkrat NA BITKO, drag-in-poraba brez porabe iz
# inventarja (isti vzorec kot frozen_rampart_used_this_battle - glej
# battle_ui.gd.use_item() poseben primer).
var drillmaster_used_this_battle: bool = false

# Item "twin_strike": enkrat NA BITKO (za razliko od knight_errant/
# vicious_knights, ki sta enkrat NA POTEZO) - glej map_behaviour.gd, isti
# capture-success blok, ista _has_adjacent_enemy() pomožna funkcija.
var twin_strike_used_this_battle: bool = false

# Item "permafrost_flare": id-ji con (glej GridManager.zones/add_zone), ki jih
# je ta item dodal - odstranijo se na NASLEDNJEM start_player_turn() (isti
# "preživi natanko eno sovražnikovo potezo" vzorec kot decoys_active zgoraj).
var timed_zone_ids: Array[int] = []

# Item "storm_horn": kot warhorn (ista `_compute_enemy_planned_targets`
# vizualizacija), a persistira skozi NASLEDNJI 2 sovražnikovi potezi namesto
# ene - gejta clear_oracle_targets() klic v start_enemy_turn() spodaj namesto
# da bi ga vsakič sprožil brezpogojno.
var storm_horn_turns_remaining: int = 0

# Phase 4 capture-redirect/once-per-battle itemi - glej base_character.capture()
# za iron_resolve/frozen_vanguard/queens_gambit dejansko logiko.
var iron_resolve_used_this_battle: bool = false
var frozen_vanguard_used_this_battle: bool = false
var queens_gambit_used_this_battle: bool = false

# Item "royal_guard" (Phase 5): enak "1x na bitko" capture-redirect vzorec
# kot zgoraj - glej base_character.capture() za dejansko logiko (kralj ->
# katerakoli sosednja zavezniška figura, za razliko od loyal_pawns, ki
# preusmeri SAMO na pešca).
var royal_guard_used_this_battle: bool = false

# Artefakt "golden_quarry" (Phase 5): dve neodvisni naključni tarči, izbrani
# ob začetku prve poteze (isti vzorec kot bounty_target/prospectors_pick_target
# zgoraj) - nagrada, če PRVI sovražnik, ki umre v tej bitki, je ena od njiju
# (glej on_enemy_died). Ena sama "resolved" zastavica (ne dve), ker gre za en
# sam item - obe tarči se izplačata na isto (prvo) smrt, kot pri drugih
# bounty-družinskih itemih.
var golden_quarry_target_a: BaseCharacter = null
var golden_quarry_target_b: BaseCharacter = null
var golden_quarry_resolved: bool = false

# Artefakt "vanguards_oath" (Phase 5): enkrat na bitko - PRVI zaveznik, ki v
# svojem dosegu ogroža sovražnika (preverjeno ob začetku vsake igralčeve
# poteze, glej start_player_turn), je "oborožen" za brezplačno dodatno potezo
# NA NASLEDNJI potezi (restricted-target vzorec, enak Queen.Command's
# free_move_character - glej consume_move_for spodaj). armed_character:
# nastavljen TO potezo, prenese se v bonus_character na NASLEDNJI klic
# start_player_turn (torej "next turn" bonus). bonus_character: aktiven TO
# potezo, porabi ga consume_move_for spodaj.
var vanguards_oath_used_this_battle: bool = false
var vanguards_oath_armed_character: BaseCharacter = null
var vanguards_oath_bonus_character: BaseCharacter = null

# Item "momentum": enak "armed this turn -> bonus next turn" restricted-target
# vzorec kot vanguards_oath zgoraj, a sprožen iz base_character.try_move()
# (dejanski premik na poln doseg), ne iz start_player_turn() detekcijske zanke.
var momentum_used_this_battle: bool = false
var momentum_armed_character: BaseCharacter = null
var momentum_bonus_character: BaseCharacter = null

# Artefakt "winter_general" (Phase 5b): 1x na bitko, drag-in-poraba brez
# porabe iz inventarja - isti vzorec kot drillmaster_used_this_battle/
# frozen_rampart_used_this_battle (glej battle_ui.gd.use_item() poseben primer).
var winter_general_used_this_battle: bool = false

# Artefakt "winters_bargain" (Phase 5b): enak "1x na bitko, drag-in-poraba
# brez porabe iz inventarja" vzorec kot winter_general zgoraj.
var winters_bargain_used_this_battle: bool = false

# Artefakt "throne_of_frost": enak "1x na bitko, drag-in-poraba brez porabe iz
# inventarja" vzorec kot winter_general zgoraj - a učinek (king.move_range
# začasno na kraljičin 8, glej throne_of_frost_item.gd) traja "SAMO to
# potezo", zato mora nekdo povrniti - ista "traja do naslednjega
# start_player_turn()" konvencija kot Knight.Evade/spectral_queen, glej
# uporabo spodaj.
var throne_of_frost_used_this_battle: bool = false
var throne_of_frost_active_king: BaseCharacter = null

# Item "time_dilation" (Phase 5b): AKTIVEN samo TO potezo (resetira se v
# start_player_turn) - dokler je true, base_character.try_move() zavrne
# ponovno izbiro figure, ki je že v moved_this_turn spodaj (glej tam).
var time_dilation_active_this_turn: bool = false

# Vsaka zavezniška figura, ki se je premaknila/zajela TO potezo (polni jo
# base_character.execute_move(), resetira se v start_player_turn) - edini
# porabnik je time_dilation_active_this_turn zgoraj; brez njega nič ne
# preprečuje premika ISTE figure dvakrat (glej item's opombo).
var moved_this_turn: Array[BaseCharacter] = []

# Item "undying_rank" (Phase 5b): enkrat na bitko - ko ostane natanko ena
# živa zavezniška figura, dobi is_capture_immune za 2 potezi (glej
# maybe_trigger_undying_rank spodaj, klican iz base_character.die()).
# active_until_turn primerja se z absolutnim turn_count (isti vzorec kot
# spectral_queen's turn_count <= 2 zgoraj, a RELATIVNO na trigger-trenutek,
# ne na začetek bitke).
var undying_rank_triggered_this_battle: bool = false
var undying_rank_character: BaseCharacter = null
var undying_rank_active_until_turn: int = -1

# Item "decoy": vsaka postavljena vaba, ki je PREŽIVELA (ni bila zajeta), se
# odstrani na začetku NASLEDNJE igralčeve poteze (glej start_player_turn) -
# torej traja natanko skozi eno sovražnikovo potezo, ne dlje. Zajete vabe
# (die() jih odstrani iz grid_managerja/queue_free-a same) enostavno ne bodo
# več is_instance_valid, zato jih spodnja zanka preskoči.
var decoys_active: Array[BaseCharacter] = []

# ----------------- ABILITY REACTIVE STATE (Queen.Exterminate / Queen.Lure) -----------------

# {} kadar ni naborožena, sicer {"tiles": Array[Vector2i], "owner": BaseCharacter, "owner_is_enemy": bool}.
# "owner" se uporablja SAMO za razorožitev ob smrti kraljice (glej
# base_character.gd.die()) - sprožilec sam uporablja "tiles" snapshot (že
# izračunan iz center+oblika ob aktivaciji, glej queen.gd._do_exterminate),
# ne žive reference, da eksplozija ostane na mestu tudi, če se kraljica
# kasneje premakne.
var exterminate_armed: Dictionary = {}

# Sovražniki, ki jih je Queen.Lure zvabila - na naslednji premik gredo proti
# lure_source namesto po normalni AI logiki (glej base_character.gd._lured_move).
var lured_enemies: Array[BaseCharacter] = []
var lure_source: BaseCharacter = null

# Queen.Command: figura, ki ji je bila podeljena brezplačna poteza za to
# potezo (glej queen._do_command in consume_move_for spodaj) - null, kadar
# trenutno ni podeljene nobene. Restricted-target design (SKILL_TREE_PLAN.md
# §4.5 popravek): NAMERNO ne skupni proračun kot add_bonus_move(), ker mora
# biti brezplačna poteza vezana točno na izbranega zaveznika.
var free_move_character: BaseCharacter = null

# Item "undying_rank": called from base_character.die() after EVERY friendly
# death (grid_manager.vacate() for the dying piece has already run by then,
# so get_all_characters() naturally excludes it - no manual filtering needed
# beyond the usual is_enemy/is_obstacle/is_decoy checks). Fires once, the
# first time exactly ONE living ally remains.
func maybe_trigger_undying_rank() -> void:
	if undying_rank_triggered_this_battle or not is_instance_valid(player_manager) \
			or not player_manager.has_passive("undying_rank") or not is_instance_valid(grid_manager):
		return
	var survivors: Array[BaseCharacter] = []
	for character in grid_manager.get_all_characters():
		if character is BaseCharacter and not character.is_enemy and not character.is_obstacle and not character.is_decoy:
			survivors.append(character)
	if survivors.size() == 1:
		undying_rank_triggered_this_battle = true
		undying_rank_character = survivors[0]
		undying_rank_active_until_turn = turn_count + 1
		undying_rank_character.is_capture_immune = true

func _clear_expired_evade():
	if not is_instance_valid(grid_manager):
		return
	for character in grid_manager.get_all_characters():
		if character is BaseCharacter and not character.is_enemy:
			character.is_capture_immune = false

func trigger_exterminate_if_armed():
	if exterminate_armed.is_empty():
		return
	var tiles: Array = exterminate_armed.get("tiles", [])
	var owner_is_enemy: bool = exterminate_armed.get("owner_is_enemy", false)
	var blast_owner = exterminate_armed.get("owner")
	exterminate_armed = {}

	if not is_instance_valid(grid_manager):
		return

	for pos in tiles:
		var target = grid_manager.get_character_at(pos)
		if target and target is BaseCharacter and target.is_enemy != owner_is_enemy and not target.is_obstacle:
			target.die()

	# Queen.Scorched Earth (skill tree flag "blast_clears_snow"): razkrije
	# celotno eksplozijsko območje po zajetju - glej GameParameters/skill_trees.json.
	if is_instance_valid(blast_owner) and blast_owner is BaseCharacter \
			and blast_owner.has_flag("blast_clears_snow"):
		grid_manager.reveal_area(tiles)

const ENEMY_MOVE_DELAY := 0.3 # premor med posameznimi sovražnikovimi potezami
const ENEMY_MOVE_FADE_DURATION := 5.0 # kako dolgo počasi izginjajo poudarki potez

# ----------------- INITIALIZATION -----------------

func _ready():
	# Bitko inicializira battle.gd (Scenes/Map/battle.gd) PO spawnu figur,
	# zato tukaj samo preverimo reference.
	if not is_instance_valid(grid_manager):
		push_error("BattleController: GridManager ni najden. Inicializacija bitke ni mogoča.")


func initialize_battle():
	bounty_target = null
	first_enemy_death_resolved = false
	prospectors_pick_target = null
	prospectors_pick_resolved = false
	courier = null
	old_guard_sentry = null
	frozen_rampart_used_this_battle = false
	night_watch_targets.clear()
	loyal_pawns_used_this_battle = false
	decoys_active.clear()
	nightfall_ward_saves_used = 0
	drillmaster_used_this_battle = false
	twin_strike_used_this_battle = false
	timed_zone_ids.clear()
	storm_horn_turns_remaining = 0
	iron_resolve_used_this_battle = false
	frozen_vanguard_used_this_battle = false
	queens_gambit_used_this_battle = false
	royal_guard_used_this_battle = false
	golden_quarry_target_a = null
	golden_quarry_target_b = null
	golden_quarry_resolved = false
	vanguards_oath_used_this_battle = false
	vanguards_oath_armed_character = null
	vanguards_oath_bonus_character = null
	momentum_used_this_battle = false
	momentum_armed_character = null
	momentum_bonus_character = null
	winter_general_used_this_battle = false
	winters_bargain_used_this_battle = false
	throne_of_frost_used_this_battle = false
	throne_of_frost_active_king = null
	time_dilation_active_this_turn = false
	moved_this_turn.clear()
	undying_rank_triggered_this_battle = false
	undying_rank_character = null
	undying_rank_active_until_turn = -1
	battle_start_enemy_count = player_manager.active_enemies.size()

	# 1. Pridobimo trenutni napredek igralca
	var current_floor = 0
	if is_instance_valid(player_manager):
		# Uporabimo current_map_floor, ki smo ga dodali v PlayerManager.gd
		current_floor = player_manager.current_map_floor

	# 2. Pokrijemo mapo z dinamično meglo (snežno odejo) - vsaka bitka, raste
	# z nadstropjem, ponastavi se z current_map_floor na začetku vsakega tierja.
	# Ločena prekletstvena "snowfall" megla (glej grid_manager.cover_area_curse)
	# je zdaj rezervirana za kralja - glej battle.gd._apply_curses.
	if is_instance_valid(grid_manager):
		grid_manager.clear_all_curse_fog()
		var fog_floor: int = current_floor
		if GF.tutorial_map_active and current_floor == 1:
			# Tutorial node 2 (prvi pravi boj, glej plans/TUTORIAL_MAP_PLAN.md) -
			# namerno brez snega/megle za ta konkreten, prvi boj (Mihov ask) -
			# ostala tutorial nadstropja (node 3/6) in normalni runi obdržijo
			# normalno stopnjevanje megle po current_map_floor.
			fog_floor = 0
		grid_manager.initialize_all_fog(fog_floor)

	# 3. Placement faza - igralec sam postavi figure v spodnje 3 vrstice.
	# Če so zavezniki že na plošči (test_sandbox / testi s predpostavljenimi
	# figurami), placement preskočimo in gremo naravnost v prvo potezo.
	if _has_friendly_pieces():
		start_player_turn()
	else:
		_set_state(BattleState.PLACEMENT)
		print(">>> PLACEMENT FAZA: igralec postavlja figure <<<")

# Potrdi postavitev in začne bitko. Kliče battle_ui, ko igralec pritisne
# START (active_party mora biti pred klicem že nastavljen na postavljene).
func confirm_placement():
	if current_state != BattleState.PLACEMENT:
		return
	start_player_turn()

func _has_friendly_pieces() -> bool:
	if not is_instance_valid(grid_manager):
		return false
	for character in grid_manager.get_all_characters():
		if character is BaseCharacter and not character.is_enemy and not character.is_obstacle:
			return true
	return false

func _set_state(new_state: int):
	current_state = new_state
	state_changed.emit(new_state)

# ----------------- TURN LOGIC -----------------

# Ali igralec sme (še) premakniti/zajeti figuro - poleg tega, da je na
# vrsti, mora imeti tudi še vsaj 1 premik na voljo v tej potezi (ločeno od
# sposobnosti, glej moves_remaining). Konec poteze (END TURN gumb) NI vezan
# na to - glej can_end_turn().
func can_move() -> bool:
	return current_state == BattleState.PLAYER_TURN and moves_remaining > 0

# Ali igralec sme (še) aktivirati sposobnost - ločeno proračun od premikov,
# glej abilities_remaining.
func can_use_ability() -> bool:
	return current_state == BattleState.PLAYER_TURN and abilities_remaining > 0

# Ali igralec sme izbrati (kliknjeno/kliknjeno ikono) svojo figuro - samo
# vezano na to, da je na vrsti, NE na preostale premike/sposobnosti, da si
# lahko ogleda/uporabi karkoli mu je še na voljo tudi, če je npr. že porabil
# vse premike.
func can_select() -> bool:
	return current_state == BattleState.PLAYER_TURN

# Gumb END TURN sme igralec pritisniti, dokler je na vrsti, ne glede na to,
# koliko premikov/sposobnosti mu je še ostalo (tudi 0) - poteza se NIKOLI ne
# konča sama.
func can_end_turn() -> bool:
	return current_state == BattleState.PLAYER_TURN

func start_player_turn():
	turn_count += 1
	_set_state(BattleState.PLAYER_TURN)
	print(">>> ZAČETEK POTEZE IGRALCA (Turn %d)" % turn_count)

	moves_remaining = player_manager.moves_per_turn
	abilities_remaining = player_manager.abilities_per_turn
	vicious_knight_used = false
	knight_errant_used_this_turn = false
	snowshoes_active_this_turn = false

	# Artefakt "vanguards_oath": bonus armiran na PREJŠNJI potezi (glej
	# detekcijsko zanko spodaj) postane aktiven TO potezo - restricted-target
	# vzorec kot free_move_character zgoraj, glej consume_move_for spodaj.
	vanguards_oath_bonus_character = vanguards_oath_armed_character
	vanguards_oath_armed_character = null

	# Item "momentum": bonus armiran na PREJŠNJI potezi (glej base_character.
	# try_move()) postane aktiven TO potezo - glej consume_move_for spodaj.
	momentum_bonus_character = momentum_armed_character
	momentum_armed_character = null

	# Item "time_dilation": velja SAMO to potezo - obe spodaj se ponastavita
	# ob vsakem novem začetku igralčeve poteze.
	time_dilation_active_this_turn = false
	moved_this_turn.clear()

	# Artefakt "winters_bargain": +1 premik obljubljen za PRVO potezo TE bitke
	# (glej PlayerManager.pending_move_bonus_next_battle - postavljen med
	# PREJŠNJO bitko, prebran in takoj počiščen tu).
	if turn_count == 1 and is_instance_valid(player_manager) and player_manager.pending_move_bonus_next_battle:
		player_manager.pending_move_bonus_next_battle = false
		add_bonus_move()

	# Item "decoy": vsaka vaba, ki je preživela do zdaj (ni bila zajeta med
	# sovražnikovo potezo, ki je pravkar minila), izgine - glej decoys_active
	# deklaracijo. Vaba, uporabljena MED to isto igralčevo potezo (po tem
	# klicu), se doda naprej in preživi do NASLEDNJEGA klica te funkcije.
	for decoy in decoys_active:
		if is_instance_valid(decoy):
			if is_instance_valid(grid_manager):
				grid_manager.vacate(decoy.grid_pos)
			decoy.queue_free()
	decoys_active.clear()

	# Item "permafrost_flare": iste "preživi natanko eno sovražnikovo potezo"
	# semantike kot decoy zgoraj - cone, dodane MED to isto igralčevo potezo
	# (po tem klicu), se dodajo naprej in odstranijo šele ob NASLEDNJEM klicu.
	if is_instance_valid(grid_manager):
		for zone_id in timed_zone_ids:
			grid_manager.remove_zone(zone_id)
	timed_zone_ids.clear()

	# Queen.Command: neporabljena brezplačna poteza se ne sme prenesti v
	# naslednjo potezo.
	free_move_character = null

	# Itema "bounty"/"courier_package": tarča/kurir se izbereta enkrat, ob
	# začetku prve poteze v bitki (sovražniki so do takrat že spawnani).
	if turn_count == 1 and is_instance_valid(player_manager) and is_instance_valid(grid_manager):
		if player_manager.has_passive("bounty"):
			var enemies: Array = []
			for character in grid_manager.get_all_characters():
				if character is BaseCharacter and character.is_enemy and not character.is_obstacle:
					enemies.append(character)
			if not enemies.is_empty():
				bounty_target = enemies.pick_random()
				bounty_marked.emit(bounty_target)

		if player_manager.has_passive("prospectors_pick"):
			var pp_enemies: Array = []
			for character in grid_manager.get_all_characters():
				if character is BaseCharacter and character.is_enemy and not character.is_obstacle:
					pp_enemies.append(character)
			if not pp_enemies.is_empty():
				prospectors_pick_target = pp_enemies.pick_random()
				prospectors_pick_marked.emit(prospectors_pick_target)

		# Artefakt "golden_quarry": kot bounty/prospectors_pick zgoraj, a
		# DVE neodvisni naključni tarči namesto ene (glej on_enemy_died -
		# nagrada, če katerakoli od njiju umre prva).
		if player_manager.has_passive("golden_quarry"):
			var gq_enemies: Array = []
			for character in grid_manager.get_all_characters():
				if character is BaseCharacter and character.is_enemy and not character.is_obstacle:
					gq_enemies.append(character)
			gq_enemies.shuffle()
			if gq_enemies.size() >= 1:
				golden_quarry_target_a = gq_enemies[0]
				golden_quarry_marked.emit(golden_quarry_target_a)
			if gq_enemies.size() >= 2:
				golden_quarry_target_b = gq_enemies[1]
				golden_quarry_marked.emit(golden_quarry_target_b)

		if player_manager.has_passive("bloodhounds"):
			_spawn_bloodhound_wolf()

		if player_manager.has_passive("courier_package"):
			var allies: Array = []
			for character in grid_manager.get_all_characters():
				if character is BaseCharacter and not character.is_enemy \
						and not character.is_obstacle and not character.is_converted_ally:
					allies.append(character)
			if not allies.is_empty():
				courier = allies.pick_random()
				courier_marked.emit(courier)

			if player_manager.has_passive("old_guard"):
				var og_allies: Array = []
				for character in grid_manager.get_all_characters():
					if character is BaseCharacter and not character.is_enemy \
							and not character.is_obstacle and not character.is_converted_ally:
						og_allies.append(character)
				if not og_allies.is_empty():
					old_guard_sentry = og_allies.pick_random()
					old_guard_marked.emit(old_guard_sentry)

		# Artefakt "starlit_vanguard" (Phase 6): +1 premik v skupni proračun
		# na PRVO potezo VSAKE bitke (ne enkratno kot winters_bargain's "next
		# battle" bonus) - EN add_bonus_move() na živo zavezniško figuro
		# (torej "vsi zavezniki dobijo +1 premik" bere se kot "skupni
		# proračun naraste za toliko, kolikor je zaveznikov").
		if player_manager.has_passive("starlit_vanguard"):
			for character in grid_manager.get_all_characters():
				if character is BaseCharacter and not character.is_enemy \
						and not character.is_obstacle and not character.is_decoy:
					add_bonus_move()

	# Pasiva "battle_start_reveal" (skill tree): ob začetku bitke razkrij
	# (2r+1)² kvadrat okoli vsake zavezniške figure s to pasivo. Vezano na
	# prvo potezo, ker so figure postavljene šele po placement fazi.
	if turn_count == 1 and is_instance_valid(grid_manager):
		for character in grid_manager.get_all_characters():
			if character is BaseCharacter and not character.is_enemy and not character.is_obstacle:
				for effect in character.passives:
					if effect.get("type", "") == "battle_start_reveal":
						var radius: int = int(effect.get("radius", 1))
						grid_manager.reveal_area(GridManager.square_radius_tiles(character.grid_pos, radius))

	# Artefakt "vanguards_oath": preverimo VSAKO igralčevo potezo (dokler se
	# enkrat ne sproži - ne samo prvo, glej vanguards_oath_used_this_battle),
	# ali kak zaveznik trenutno ogroža sovražnika - PRVI najden dobi bonus na
	# NASLEDNJI potezi (glej vanguards_oath_bonus_character prenos na vrhu te
	# funkcije). ZNANA POENOSTAVITEV (isti standard kot spyglass/
	# foresight_mirror): preverjeno samo TU, ob začetku poteze, ne
	# sproti med igralčevimi lastnimi premiki znotraj iste poteze.
	if not vanguards_oath_used_this_battle and is_instance_valid(player_manager) \
			and player_manager.has_passive("vanguards_oath") and is_instance_valid(grid_manager):
		for character in grid_manager.get_all_characters():
			if not (character is BaseCharacter) or character.is_enemy or character.is_obstacle:
				continue
			var threatens_enemy := false
			for pos in character.calculate_valid_targets():
				var t = grid_manager.get_character_at(pos)
				if t and t is BaseCharacter and t.is_enemy:
					threatens_enemy = true
					break
			if threatens_enemy:
				vanguards_oath_used_this_battle = true
				vanguards_oath_armed_character = character
				break

	moves_changed.emit(moves_remaining, player_manager.moves_per_turn)
	abilities_changed.emit(abilities_remaining, player_manager.abilities_per_turn)

	# Razkrijemo figure takoj, ko se poteza začne
	update_fog_after_turn_start()

	# Snow rework: smrt zaradi zamrznitve (npr. kralja) mora TAKOJ končati
	# bitko - update_fog_after_turn_start() zgoraj lahko pravkar pokliče die().
	if check_battle_end():
		return

	# Knight.Evade: imuniteta velja "za eno potezo" - torej natanko čez
	# sovražnikovo potezo, ki se je pravkar iztekla.
	_clear_expired_evade()

	# Artefakt "throne_of_frost": king.move_range povrnjen na pravi 1 - učinek
	# je veljal natanko "to potezo" (glej throne_of_frost_item.gd/deklaracijo
	# zgoraj).
	if is_instance_valid(throne_of_frost_active_king):
		throne_of_frost_active_king.move_range = 1
		throne_of_frost_active_king = null

	# Item "spectral_queen": kraljica je nezajemljiva PRVI 2 potezi bitke -
	# PONOVNO nastavljeno vsako potezo, dokler turn_count <= 2 (mora priti
	# TAKOJ PO _clear_expired_evade() zgoraj, ki bi sicer to prepisala nazaj
	# na false vsako potezo - isto "traja do naslednjega start_player_turn()"
	# pravilo kot Knight.Evade/iron_pawns, glej is_capture_immune deklaracijo
	# v base_character.gd).
	if turn_count <= 2 and is_instance_valid(player_manager) \
			and player_manager.has_passive("spectral_queen") and is_instance_valid(grid_manager):
		for character in grid_manager.get_all_characters():
			if character is BaseCharacter and not character.is_enemy and not character.is_obstacle \
					and character.strName == "queen":
				character.is_capture_immune = true

	# Item "undying_rank": reassert immunity while the 2-turn window (set by
	# maybe_trigger_undying_rank() above) is still open - same "survive
	# _clear_expired_evade()'s per-turn reset" pattern as spectral_queen, just
	# relative to the trigger turn instead of the battle's start.
	if is_instance_valid(undying_rank_character) and turn_count <= undying_rank_active_until_turn:
		undying_rank_character.is_capture_immune = true

	# Počasi izbledi poudarke sovražnikovih potez iz prejšnjega kroga
	if is_instance_valid(move_highlighter):
		move_highlighter.start_fade_out(ENEMY_MOVE_FADE_DURATION)

	# Artefakt "oracle_glass": vsako igralčevo potezo na novo prikaže
	# predvideno ciljno polje vsakega sovražnika, ki je igralca že opazil
	# (glej _compute_enemy_planned_targets - item "warhorn" isto funkcijo
	# sproži ročno, enkratno).
	if player_manager.has_passive("oracle_glass") and is_instance_valid(move_highlighter):
		move_highlighter.show_oracle_targets(_compute_enemy_planned_targets())

# Porabi 1 premik/zajetje iz proračuna te poteze. Poteza se NE konča
# samodejno, tudi če pade na 0 - igralec mora sam pritisniti END TURN.
func consume_move():
	moves_remaining = maxi(0, moves_remaining - 1)
	moves_changed.emit(moves_remaining, player_manager.moves_per_turn)

# Kot consume_move(), a preskoči porabo proračuna, če je "character" ravno
# figura, ki ji je Queen.Command podelila brezplačno potezo za to potezo
# (glej free_move_character zgoraj) - ta poteza je bila že "plačana" s samo
# Command ability-uporabo. map_behaviour.gd (oba consume_move() klicna mesta)
# kličeta TO namesto consume_move() neposredno.
func consume_move_for(character: BaseCharacter) -> void:
	if character == free_move_character:
		free_move_character = null
		return
	# Artefakt "vanguards_oath": ista "restricted-target free skip" logika kot
	# free_move_character zgoraj, glej vanguards_oath_bonus_character deklaracijo.
	if character == vanguards_oath_bonus_character:
		vanguards_oath_bonus_character = null
		return
	# Item "momentum": ista "restricted-target free skip" logika kot
	# vanguards_oath_bonus_character zgoraj, glej deklaracijo.
	if character == momentum_bonus_character:
		momentum_bonus_character = null
		return
	consume_move()

# Porabi 1 sposobnost iz proračuna te poteze (ločeno od premikov - glej
# opombo pri moves_remaining).
func consume_ability():
	abilities_remaining = maxi(0, abilities_remaining - 1)
	abilities_changed.emit(abilities_remaining, player_manager.abilities_per_turn)

# Item "extra_move": dodatni premik v trenutni potezi. Namerno lahko preseže
# moves_per_turn - UI label potem kaže npr. 2/1, kar je pravilno.
func add_bonus_move():
	moves_remaining += 1
	moves_changed.emit(moves_remaining, player_manager.moves_per_turn)

# Item "bloodhounds": prikliče enega volka na naključno prosto polje v
# spodnjih 3 vrsticah (isti obseg kot placement cona) - natanko en volk na
# bitko, ne glede na to, koliko kosov itema igralec ima.
func _spawn_bloodhound_wolf():
	if not is_instance_valid(grid_manager) or not is_instance_valid(tile_map):
		return
	var used_rect: Rect2i = tile_map.get_used_rect()
	var candidates: Array[Vector2i] = []
	for y in range(used_rect.end.y - 3, used_rect.end.y):
		for x in range(used_rect.position.x, used_rect.end.x):
			var pos := Vector2i(x, y)
			if grid_manager.is_inside_boundary(pos, used_rect) and not grid_manager.is_occupied(pos):
				candidates.append(pos)
	if candidates.is_empty():
		return

	var tile: Vector2i = candidates.pick_random()
	var battle_root = get_node("..")
	var wolf_scene: PackedScene = battle_root.friendly_pieces["friendly_wolf"]
	grid_manager.spawn_character(wolf_scene, grid_manager.grid_to_world(tile))

	# Začasen zaveznik - ni del trajnega rosterja (glej PlayerManager.
	# add_temporary_ally); is_converted_ally usmeri smrt skozi
	# remove_converted_ally(), ne register_dead_character().
	var wolf: BaseCharacter = grid_manager.get_character_at(tile)
	if is_instance_valid(wolf):
		wolf.is_converted_ally = true
		player_manager.add_temporary_ally("friendly_wolf")

# Item "bloodhounds": po igralčevi potezi (pred sovražnikovo) se vsaka
# avtonomna zavezniška figura (trenutno samo volk) premakne sama, po
# enaki poti kot sovražnikova AI poteza (glej _take_enemy_action).
func _move_autonomous_allies() -> void:
	if not is_instance_valid(grid_manager):
		return
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter):
			continue
		if character.is_enemy or not character.is_autonomous:
			continue

		await _take_enemy_action(character)

		if check_battle_end():
			return

# Itema "bounty"/"prospectors_pick": kliče base_character.die() za VSAKEGA
# sovražnika, ki umre - samo prva smrt v bitki šteje za vsak item posebej
# (poznejše zajetja tarče ne vplivajo). Ločena "resolved" zastavica na item,
# ker sta neodvisna in se lahko obe izplačata za isto (prvo) smrt.
func on_enemy_died(character: BaseCharacter):
	if not first_enemy_death_resolved:
		first_enemy_death_resolved = true
		if character == bounty_target and is_instance_valid(player_manager):
			player_manager.add_upgrade_items(ItemData.get_reward("bounty"))
			print("BOUNTY: tarča je padla prva - nagrada izplačana")

	if not prospectors_pick_resolved:
		prospectors_pick_resolved = true
		if character == prospectors_pick_target and is_instance_valid(player_manager):
			player_manager.add_upgrade_items(ItemData.get_reward("prospectors_pick"))
			print("PROSPECTORS_PICK: tarča je padla prva - nagrada izplačana")

	# Artefakt "golden_quarry": ena "resolved" zastavica pokriva OBE tarči (za
	# razliko od bounty/prospectors_pick zgoraj, ki imata vsak svojo) - to je
	# EN item, obe tarči se izplačata na isto (prvo od njiju) smrt.
	if not golden_quarry_resolved:
		if character == golden_quarry_target_a or character == golden_quarry_target_b:
			golden_quarry_resolved = true
			if is_instance_valid(player_manager):
				player_manager.add_upgrade_items(ItemData.get_reward("golden_quarry"))
				print("GOLDEN_QUARRY: ena od dveh tarč je padla prva - nagrada izplačana")

	# Status-effect reward family (Phase 5b, all three stack, per-death, NOT
	# gated to "first enemy" like bounty/golden_quarry above - see
	# BaseCharacter.was_frozen_by_player/marked_by_vision_item for the two
	# underlying flags, set once and never cleared for the rest of the battle).
	if is_instance_valid(player_manager):
		# Item "cold_case": specific to freeze, pays more than the general
		# hexers_ledger below.
		if player_manager.has_passive("cold_case") and character.was_frozen_by_player:
			player_manager.add_upgrade_items(ItemData.get_reward("cold_case"))
			print("COLD_CASE: sovražnik, ki je bil kdaj zamrznjen, je padel - nagrada izplačana")
		# Item "marked_man": specific to vision-marks, pays more than the
		# general hexers_ledger below.
		if player_manager.has_passive("marked_man") and character.marked_by_vision_item:
			player_manager.add_upgrade_items(ItemData.get_reward("marked_man"))
			print("MARKED_MAN: označen sovražnik je padel - nagrada izplačana")
		# Item "hexers_ledger": general - either flag counts (freeze OR
		# vision-mark; this game's status effects a player can inflict on an
		# enemy reduce to these two categories, see grid_manager.trigger_trap/
		# item scripts that set was_frozen_by_player).
		if player_manager.has_passive("hexers_ledger") \
				and (character.was_frozen_by_player or character.marked_by_vision_item):
			player_manager.add_upgrade_items(ItemData.get_reward("hexers_ledger"))
			print("HEXERS_LEDGER: sovražnik pod prekletim učinkom je padel - nagrada izplačana")

	# Item "salvage": VSAKO sovražnikovo smrt (ne samo prva) ima možnost
	# dodatnega upgrade itema. SALVAGE_DROP_CHANCE je placeholder vrednost -
	# brainstorm ni podal številke, Miha naj jo uravnoteži v kasnejšem balance
	# pass-u (isti "placeholder, potrebuje balance pass" vzorec kot drugod
	# v projektu).
	if is_instance_valid(player_manager) and player_manager.has_passive("salvage") and randf() < SALVAGE_DROP_CHANCE:
		player_manager.add_upgrade_items(1)
		print("SALVAGE: dodaten upgrade item izplačan")

# Item "courier_package": kurir mora PREŽIVETI do zmage - die() ga
# queue_free()-a, zaradi česar is_instance_valid() vrne false, torej zajeti
# kurirji ne izplačajo ničesar. Ločena funkcija (namesto inline v
# check_battle_end()), da je testljiva brez sprožitve GF.call_deferred().
func _maybe_pay_courier_reward():
	if is_instance_valid(courier) and is_instance_valid(player_manager):
		player_manager.add_upgrade_items(ItemData.get_reward("courier_package"))
		print("COURIER_PACKAGE: kurir je preživel - nagrada izplačana")

# Item "old_guard": enak vzorec kot _maybe_pay_courier_reward zgoraj, a
# ločeno stanje (glej old_guard_sentry).
func _maybe_pay_old_guard_reward():
	if is_instance_valid(old_guard_sentry) and is_instance_valid(player_manager):
		player_manager.add_upgrade_items(ItemData.get_reward("old_guard"))
		print("OLD_GUARD: stražar je preživel - nagrada izplačana")

# Artefakt "oracle_glass"/item "warhorn": zbere predvideno ciljno polje
# vsakega sovražnika, ki je igralca že opazil (has_spotted_player) - dormantne
# sovražnike NAMERNO izpustimo, ker bi jih sam klic calculate_best_move()
# "prebudil" prezgodaj (glej tam - "Wake-up turn" veja nastavi
# has_spotted_player na true že ob prvem klicu). Klic je sicer čisto
# poizvedovalen (ne premakne nikogar), a NI deterministična garancija - panic
# randomness (base_character.calculate_best_move) lahko ob dejanski
# sovražnikovi potezi izbere drugo tarčo kot ta predogled (isti "znana
# poenostavitev" kompromis kot map_behaviour.gd's spyglass, glej tam).
func _compute_enemy_planned_targets() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not is_instance_valid(grid_manager):
		return tiles
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character) or not (character is BaseCharacter):
			continue
		if not character.is_enemy or character.is_obstacle:
			continue
		if not character.has_spotted_player:
			continue
		var action: Dictionary = character.calculate_best_move()
		if not action.is_empty():
			tiles.append(action["target_pos"])
	return tiles

# Prekletstvo "stunning_gaze": kliče ga stunning_gaze_curse.gd.on_action_taken,
# da battle_ui.gd lahko takoj osveži značko/STATUS omamljene figure.
func notify_stun(character: BaseCharacter) -> void:
	piece_stunned.emit(character)

# Prekletstvo "entangle": kliče ga entangle_curse.gd.on_action_taken, enako
# kot notify_stun zgoraj.
func notify_root(character: BaseCharacter) -> void:
	piece_rooted.emit(character)

func end_player_turn():
	print("<<< KONEC POTEZE IGRALCA >>>")

	# Prekletstvo "stunning_gaze"/"entangle": oba statusa trajata NATANKO
	# igralčevo naslednjo potezo - odštejemo TUKAJ (ob koncu poteze, v kateri
	# je bila figura prizadeta), ne ob začetku naslednje, da actual "ena
	# poteza" učinek ne podaljša za dodatno potezo, če bi tikali v
	# start_player_turn.
	if is_instance_valid(grid_manager):
		for character in grid_manager.get_all_characters():
			if not is_instance_valid(character):
				continue
			if not (character is BaseCharacter):
				continue
			# Wave 2 items: effect_frozen_turns tika za OBE strani (igralec
			# lahko zamrzne sovražnika) - en tik na konec igralčeve poteze
			# pomeni "zamrznjen natanko eno naslednjo potezo" za katerokoli
			# stran, saj med dvema tikoma mine natanko ena sovražnikova poteza.
			if character.effect_frozen_turns > 0:
				character.effect_frozen_turns -= 1
			if character.is_enemy:
				continue
			if character.stunned_turns > 0:
				character.stunned_turns -= 1
			if character.rooted_turns > 0:
				character.rooted_turns -= 1

	if check_battle_end():
		return

	# Item "bloodhounds": avtonomni zavezniki (volk) delujejo TAKOJ po
	# igralčevi potezi, pred sovražnikovo. Klicatelji (battle_ui action
	# gumb) tega ne awaitajo - v redu, nadaljuje kot coroutine, enako kot
	# spodnji start_enemy_turn() await-i že delajo.
	await _move_autonomous_allies()
	if check_battle_end():
		return

	# Preklopimo na naslednjo fazo (nasprotnikovo potezo)
	start_enemy_turn()

# Item "war_council": VRSTNI RED, v katerem bo start_enemy_turn() spodaj
# dejansko obravnaval sovražnike - eno mesto resnice, ki ga uporablja TAKO
# dejanska izvedba (spodaj) KOT predogled (battle_ui._refresh_war_council_badges,
# poklican na začetku igralčeve poteze). Vrstni red izhaja iz
# grid_manager.occupied slovarja (insertion order) - figura, ki se premakne,
# se efektivno prestavi na konec (vacate+occupy je erase+re-insert), zato
# vrstni red NI "levo-desno"/"stabilen ID" temveč dejanski Dictionary red;
# deljenje TE funkcije med predogledom in izvedbo je edini način, da se
# predogled ne razsinhronizira z resničnim vrstnim redom.
func enemy_turn_order() -> Array[BaseCharacter]:
	var order: Array[BaseCharacter] = []
	if not is_instance_valid(grid_manager):
		return order
	for character in grid_manager.get_all_characters():
		if character is BaseCharacter and character.is_enemy and not character.is_obstacle:
			order.append(character)
	return order

func start_enemy_turn():
	_set_state(BattleState.ENEMY_TURN)
	print(">>> ZAČETEK POTEZE SOVRAŽNIKA <<<")

	# AI izklopljen (tutorial): poteza gre takoj nazaj igralcu, figure mirujejo.
	if not ai_enabled:
		end_enemy_turn()
		return

	# Počisti poudarke prejšnjega kroga (tudi če še niso do konca izginili),
	# da se ne mešajo s poudarki tega kroga.
	if is_instance_valid(move_highlighter):
		move_highlighter.clear_enemy_moves()
		# Item "warhorn"/artefakt "oracle_glass": predogled velja samo do konca
		# igralčeve poteze - dejanske sovražnikove poteze se zdaj izvedejo.
		# Item "storm_horn": persistira skozi 2 sovražnikovi potezi namesto
		# ene - dokler je counter > 0, PRESKOČIMO clear (isti snapshot ostane
		# viden, glej storm_horn_item.gd - namerno statičen predogled, ne
		# osvežen vsako potezo znova).
		if storm_horn_turns_remaining > 0:
			storm_horn_turns_remaining -= 1
		else:
			move_highlighter.clear_oracle_targets()

	if not is_instance_valid(grid_manager):
		push_error("GridManager ni veljaven za AI potezo.")
		end_enemy_turn()
		return

	for character in enemy_turn_order():
		# Snapshot may contain a piece captured earlier in this same loop -
		# await below means real frames pass, so queue_free() can have
		# actually deallocated it by the time we get here (unlike the old
		# fully-synchronous version, where nothing was freed mid-loop yet).
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter):
			continue
		if not character.is_enemy:
			continue

		# Prekletstvo "frenzy": nosilec dobi 1+extra_actions() akcij v TEJ
		# sovražnikovi potezi (glej frenzy_curse.gd). Zanka namesto enega
		# await-a, da vsaka akcija dobi svoj flash/pause + battle-end preverbo.
		# "actions" je NAMERNO mutable (while namesto for) - prekletstvo
		# "bloodlust" lahko med zanko doda dodatno akcijo po uspešnem zajetju
		# (glej grants_bonus_action_on_capture spodaj), do največ
		# max_bonus_actions (GameParameters/curses.json, difficulty-aware prek
		# max_bonus_actions_by_difficulty + SettingsManager.difficulty, glej
		# CurseData.get_param_by_difficulty) na to sovražnikovo potezo.
		var actions: int = 1 + (character.curse.extra_actions() if character.curse else 0)
		var bloodlust_bonus_used := 0
		var i := 0
		while i < actions:
			# Lahko je umrl/izginil med prejšnjo akcijo v tej isti zanki
			# (npr. Queen.Exterminate sprožen z lastnim premikom).
			if not is_instance_valid(character):
				break
			var was_capture: bool = await _take_enemy_action(character)

			# Če je ta akcija končala bitko, takoj prekinemo potezo
			if check_battle_end():
				return

			if was_capture and is_instance_valid(character) and character.curse \
					and character.curse.grants_bonus_action_on_capture():
				var max_bonus: int = curse_data.get_param_by_difficulty(character.curse.id, "max_bonus_actions", 2, SettingsManager.difficulty)
				if bloodlust_bonus_used < max_bonus:
					bloodlust_bonus_used += 1
					actions += 1

			i += 1

	end_enemy_turn()

# Izračuna najboljšo potezo za eno sovražnikovo figuro in jo izvede.
# Če je premik uspel, poskrbi za vizualizacijo + premor pred naslednjo potezo,
# in sproži morebiten curse hook (snowfall/stunning_gaze - glej curse
# variante v Scripts/Curses/). Vrne true, če je ta akcija dejansko zajela
# nasprotnika - glej "bloodlust" v start_enemy_turn() zgoraj, ki na podlagi
# tega dodeli bonus akcijo.
func _take_enemy_action(character: BaseCharacter) -> bool:
	var action = character.calculate_best_move()
	if action.is_empty():
		return false

	var from_pos: Vector2i = character.grid_pos
	var is_capture: bool = action.get("move_type", "") == "CAPTURE"

	# try_move sam ponovno preveri veljavnost tarče in izvede premik ALI zajetje
	var moved: bool = character.try_move(action["target_pos"])
	if moved:
		if character.curse:
			character.curse.on_action_taken(character, self)
		await _flash_move_and_pause(from_pos, action["target_pos"], is_capture, character)
	return moved and is_capture

# Prikaže vizualizacijo ene sovražnikove poteze (izvorno/ciljno polje + pot)
# in počaka kratek premor, preden se izvede naslednja poteza. "character":
# item "tracker" - glej MoveHighlighter.flash_enemy_move.
func _flash_move_and_pause(from_pos: Vector2i, to_pos: Vector2i, is_capture: bool, character: BaseCharacter = null) -> void:
	if is_instance_valid(move_highlighter):
		var path_tiles = _compute_path_tiles(from_pos, to_pos)
		move_highlighter.flash_enemy_move(from_pos, to_pos, path_tiles, is_capture, character)

	await get_tree().create_timer(ENEMY_MOVE_DELAY).timeout


func end_enemy_turn():
	print("<<< KONEC POTEZE SOVRAŽNIKA >>>")

	start_player_turn()

# Preveri, ali je bitke konec, in po potrebi sproži prehod scene.
# Prehod je call_deferred, da se trenutna akcija (capture/premik) varno dokonča,
# preden GameFlow odstrani sceno iz drevesa.
func check_battle_end() -> bool:
	if not is_instance_valid(player_manager):
		return false

	if player_manager.enemyGone():
		_set_state(BattleState.GAME_OVER)
		# Zmaga prinese upgrade iteme (boss bitke več) - porabijo se na
		# počivališču (glej CampfireUpgradePanel.gd).
		var was_boss_floor: bool = player_manager.is_boss_floor
		var upgrade_items_before: int = player_manager.upgrade_items
		if was_boss_floor:
			player_manager.add_upgrade_items(player_manager.UPGRADE_ITEMS_PER_BOSS_WIN
				+ player_manager.bonus_upgrade_items_per_win)
		else:
			player_manager.add_upgrade_items(player_manager.UPGRADE_ITEMS_PER_WIN
				+ player_manager.bonus_upgrade_items_per_win)

		_maybe_pay_courier_reward()
		_maybe_pay_old_guard_reward()
		# Delta, ne konstanta - _maybe_pay_courier_reward()/_maybe_pay_old_guard_reward()
		# lahko dodata dodatne iteme na vrh win/boss-win nagrade (glej definicijo zgoraj).
		var upgrade_items_gained: int = player_manager.upgrade_items - upgrade_items_before

		# Trajne "Legacy Points" (glej plans/META_PROGRESSION_PLAN.md §3 M4) -
		# ločeno od upgrade_items zgoraj, ne resetira se med runi.
		var battle_points := MetaUpgradeData.calculate_battle_points(
			player_manager.current_map_floor, battle_start_enemy_count, turn_count,
			player_manager.dead_party.is_empty(), MetaProgress.final_boss_beaten)
		MetaProgress.add_legacy_points(battle_points)

		GF.call_deferred("show_victory_summary",
			player_manager.friendly_party.duplicate(), player_manager.enemy_party.duplicate(),
			player_manager.new_friendly_piece, player_manager.new_enemy_piece,
			upgrade_items_gained, was_boss_floor)
		return true

	if player_manager.activeGone():
		_set_state(BattleState.GAME_OVER)
		# Item "divine_intervention": porabi 1 kos in reši igralca pred
		# porazom - vrne se na mapo (napredek mape se OHRANI, friendly_party
		# se s smrtjo v bitki ne spreminja), ne izgubi nadstropja/game_over.
		if player_manager.remove_item("divine_intervention"):
			print("DIVINE_INTERVENTION: rešeni pred porazom")
			# Artefakt "crown_of_the_long_night": dodaten bonus na vrh rešitve
			# same (glej ItemData "reward" polje) - preverimo ŠELE po uspešni
			# porabi divine_intervention, saj velja SAMO ob dejanski rešitvi.
			if player_manager.has_passive("crown_of_the_long_night"):
				player_manager.add_upgrade_items(ItemData.get_reward("crown_of_the_long_night"))
			GF.call_deferred("return_to_map_after_escape")
			return true
		# current_map_tier/current_map_floor je treba zajeti PRED
		# reset_floor_number() - ta sinhrono ponastavi floor na 0, tier pa
		# se ponastavi kasneje v _end_run() (klican iz game_over(), odloženo).
		var final_tier: int = player_manager.current_map_tier
		var final_floor: int = player_manager.current_map_floor
		player_manager.reset_floor_number()
		GF.call_deferred("show_defeat_summary", final_tier, final_floor)
		return true

	return false

# Izračuna vmesna polja med from in to, da MoveHighlighter lahko nariše
# pot sovražnikove poteze. Drseče figure (pešec/trdnjava/lovec/kraljica/
# kralj) se premikajo po ravni črti, zato je pot preprosto vsako polje
# med izhodiščem in ciljem. Skakač (vitez) nima resničnih vmesnih polj
# (skoči neposredno) - zanj vrnemo eno samo "upognjeno" polje, ki
# stilizirano nakaže obliko črke L (najprej daljša os, nato krajša).
func _compute_path_tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var delta = to - from
	var path: Array[Vector2i] = []

	var is_knight_jump = delta.x != 0 and delta.y != 0 and absi(delta.x) != absi(delta.y)
	if is_knight_jump:
		if absi(delta.x) > absi(delta.y):
			path.append(from + Vector2i(delta.x, 0))
		else:
			path.append(from + Vector2i(0, delta.y))
		return path

	var step = delta.sign()

	var current = from + step
	while current != to:
		path.append(current)
		current += step

	return path

# ----------------- FOG OF WAR LOGIC -----------------

# Ta funkcija posodobi meglo na podlagi trenutnih pozicij figur
func update_fog_after_turn_start():
	if not is_instance_valid(grid_manager):
		return

	var reveal_positions: Array[Vector2i] = []

	# Zberemo pozicije vseh ŽIVIH zavezniških figur na mreži - snow rework:
	# razkrijemo SAMO polje, na katerem figura stoji (ne več 3x3 okolico),
	# glej isto spremembo v execute_move().
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter):
			continue
		if character.is_enemy or character.is_obstacle:
			continue

		reveal_positions.append(character.grid_pos)

	# Item "watchtower": vsak zavezniški top dodatno razkrije prvega
	# sovražnika v vsaki od svojih ravnih smeri (find_visible_enemies že
	# "vidi skozi meglo" - fog ni del is_occupied, samo prava figura/ovira
	# ustavi pogled, glej base_character.gd).
	if player_manager.has_passive("watchtower"):
		for character in grid_manager.get_all_characters():
			if not is_instance_valid(character) or not (character is BaseCharacter):
				continue
			if character.is_enemy or character.is_obstacle or character.strName != "rook":
				continue
			for enemy in character.find_visible_enemies(character.move_range):
				reveal_positions.append(enemy.grid_pos)

	# Item "night_watch": glej night_watch_targets deklaracijo zgoraj.
	for target in night_watch_targets:
		if is_instance_valid(target):
			reveal_positions.append(target.grid_pos)

	grid_manager.reveal_area(reveal_positions)

	# Prekletstvena "snowfall" megla razpada 1 fazo na rundo - vezano na začetek
	# igralčeve poteze, torej po vsaki polni rundi (glej GridManager.tick_curse_fog_decay).
	grid_manager.tick_curse_fog_decay()

	# Vrstni red je pomemben: lastno-polje razkritje -> razpad -> freeze
	# preverjanje, da sneg, ki je pravkar skopnel, ne šteje več za obkrožujočega.
	_update_snow_freeze_states()

# Snow rework: preveri, ali je vsaka živa zavezniška figura obkrožena s
# snegom na vseh 4 ortogonalnih straneh - če DA, šteje ZAPOREDNE poteze
# (SNOW_FREEZE_TURNS -> FROZEN, SNOW_DEATH_TURNS -> smrt); če NE, ponastavi
# šteto na 0. get_all_characters() vrne occupied.values(), kar je že SNAPSHOT
# (Dictionary.values() vrne nov Array) - varno je iterirati, tudi če die()
# spodaj med iteracijo spremeni "occupied" preko vacate().
func _update_snow_freeze_states() -> void:
	if not is_instance_valid(grid_manager):
		return
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter):
			continue
		if character.is_enemy or character.is_obstacle:
			continue

		if grid_manager.is_snow_surrounded(character.grid_pos):
			character.snow_trapped_turns += 1
			if character.snow_trapped_turns >= SNOW_DEATH_TURNS:
				character.die()
				continue
			# Item "warm_cloak": imuna figura šteje snow_trapped_turns naprej
			# (smrtni odštevalnik zgoraj še vedno velja), a se dejansko nikoli
			# ne zamrzne (glej is_freeze_immune deklaracijo).
			if character.snow_trapped_turns >= SNOW_FREEZE_TURNS and not character.snow_frozen \
					and not character.is_freeze_immune:
				# Item "nightfall_ward"/"frostguard_talisman": prve N zavezniških
				# zamrznitev v tej bitki (kdorkoli, po vrsti kot pridejo na vrsto
				# v tej zanki) se namesto dejanskega zamrznjenja samo potrošijo -
				# snow_trapped_turns (smrtni odštevalnik) je že prištet zgoraj in
				# ostane veljaven.
				if nightfall_ward_saves_used < nightfall_ward_max_saves():
					nightfall_ward_saves_used += 1
				else:
					character.snow_frozen = true
					piece_frozen.emit(character)
		else:
			character.snow_trapped_turns = 0
			character.snow_frozen = false
