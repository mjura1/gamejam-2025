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

# Item "courier_package": enako kot bounty_marked, a za kurirja (glej
# start_player_turn()).
signal courier_marked(character: BaseCharacter)

# Prekletstvo "stunning_gaze": character je bil pravkar omamljen (glej
# stunning_gaze_curse.gd.on_action_taken -> notify_stun spodaj) - battle_ui.gd
# poveže to na značko/STATUS.
signal piece_stunned(character: BaseCharacter)

# Prekletstvo "entangle": character je bil pravkar ukoreninjen (glej
# entangle_curse.gd.on_action_taken -> notify_root spodaj) - battle_ui.gd
# poveže to na značko/STATUS, enako kot piece_stunned.
signal piece_rooted(character: BaseCharacter)

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

# Item "courier_package": naključen živ zaveznik je izbran ob začetku prve
# poteze v bitki (izključuje volka - glej start_player_turn()); če preživi
# bitko do zmage, igralec dobi nagrado (glej check_battle_end() victory
# branch). Resetira se v initialize_battle().
var courier: BaseCharacter = null

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
	exterminate_armed = {}

	if not is_instance_valid(grid_manager):
		return

	for pos in tiles:
		var target = grid_manager.get_character_at(pos)
		if target and target is BaseCharacter and target.is_enemy != owner_is_enemy and not target.is_obstacle:
			target.die()

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
	courier = null

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
		grid_manager.initialize_all_fog(current_floor)

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
	moves_changed.emit(moves_remaining, player_manager.moves_per_turn)
	abilities_changed.emit(abilities_remaining, player_manager.abilities_per_turn)

	# Razkrijemo figure takoj, ko se poteza začne
	update_fog_after_turn_start()

	# Knight.Evade: imuniteta velja "za eno potezo" - torej natanko čez
	# sovražnikovo potezo, ki se je pravkar iztekla.
	_clear_expired_evade()

	# Počasi izbledi poudarke sovražnikovih potez iz prejšnjega kroga
	if is_instance_valid(move_highlighter):
		move_highlighter.start_fade_out(ENEMY_MOVE_FADE_DURATION)

# Porabi 1 premik/zajetje iz proračuna te poteze. Poteza se NE konča
# samodejno, tudi če pade na 0 - igralec mora sam pritisniti END TURN.
func consume_move():
	moves_remaining = maxi(0, moves_remaining - 1)
	moves_changed.emit(moves_remaining, player_manager.moves_per_turn)

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

# Item "bounty": kliče base_character.die() za VSAKEGA sovražnika, ki umre -
# samo prva smrt v bitki šteje (poznejše zajetja bounty_targeta ne vplivajo).
func on_enemy_died(character: BaseCharacter):
	if first_enemy_death_resolved:
		return
	first_enemy_death_resolved = true
	if character == bounty_target and is_instance_valid(player_manager):
		player_manager.add_upgrade_items(ItemData.get_reward("bounty"))
		print("BOUNTY: tarča je padla prva - nagrada izplačana")

# Item "courier_package": kurir mora PREŽIVETI do zmage - die() ga
# queue_free()-a, zaradi česar is_instance_valid() vrne false, torej zajeti
# kurirji ne izplačajo ničesar. Ločena funkcija (namesto inline v
# check_battle_end()), da je testljiva brez sprožitve GF.call_deferred().
func _maybe_pay_courier_reward():
	if is_instance_valid(courier) and is_instance_valid(player_manager):
		player_manager.add_upgrade_items(ItemData.get_reward("courier_package"))
		print("COURIER_PACKAGE: kurir je preživel - nagrada izplačana")

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

func start_enemy_turn():
	_set_state(BattleState.ENEMY_TURN)
	print(">>> ZAČETEK POTEZE SOVRAŽNIKA <<<")

	# Počisti poudarke prejšnjega kroga (tudi če še niso do konca izginili),
	# da se ne mešajo s poudarki tega kroga.
	if is_instance_valid(move_highlighter):
		move_highlighter.clear_enemy_moves()

	if not is_instance_valid(grid_manager):
		push_error("GridManager ni veljaven za AI potezo.")
		end_enemy_turn()
		return

	for character in grid_manager.get_all_characters():
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
		# max_bonus_actions (Data/curses.json) na to sovražnikovo potezo.
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
				var max_bonus: int = curse_data.get_param(character.curse.id, "max_bonus_actions", 2)
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
		await _flash_move_and_pause(from_pos, action["target_pos"], is_capture)
	return moved and is_capture

# Prikaže vizualizacijo ene sovražnikove poteze (izvorno/ciljno polje + pot)
# in počaka kratek premor, preden se izvede naslednja poteza.
func _flash_move_and_pause(from_pos: Vector2i, to_pos: Vector2i, is_capture: bool) -> void:
	if is_instance_valid(move_highlighter):
		var path_tiles = _compute_path_tiles(from_pos, to_pos)
		move_highlighter.flash_enemy_move(from_pos, to_pos, path_tiles, is_capture)

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
		if player_manager.is_boss_floor:
			player_manager.add_upgrade_items(player_manager.UPGRADE_ITEMS_PER_BOSS_WIN)
			GF.call_deferred("advance_map_tier")
		else:
			player_manager.add_upgrade_items(player_manager.UPGRADE_ITEMS_PER_WIN)
			GF.call_deferred("return_to_map")

		_maybe_pay_courier_reward()
		return true

	if player_manager.activeGone():
		_set_state(BattleState.GAME_OVER)
		# Item "divine_intervention": porabi 1 kos in reši igralca pred
		# porazom - vrne se na mapo (napredek mape se OHRANI, friendly_party
		# se s smrtjo v bitki ne spreminja), ne izgubi nadstropja/game_over.
		if player_manager.remove_item("divine_intervention"):
			print("DIVINE_INTERVENTION: rešeni pred porazom")
			GF.call_deferred("return_to_map_after_escape")
			return true
		player_manager.reset_floor_number()
		GF.call_deferred("game_over")
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

	# Zberemo pozicije vseh ŽIVIH zavezniških figur na mreži
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter):
			continue
		if character.is_enemy or character.is_obstacle:
			continue

		var char_pos: Vector2i = character.grid_pos

		# Razkrijemo 3x3 območje okoli figure
		for x in range(-1, 2):
			for y in range(-1, 2):
				var new_pos = char_pos + Vector2i(x, y)
				if new_pos not in reveal_positions:
					reveal_positions.append(new_pos)

	grid_manager.reveal_area(reveal_positions)

	# Prekletstvena "snowfall" megla razpada 1 fazo na rundo - vezano na začetek
	# igralčeve poteze, torej po vsaki polni rundi (glej GridManager.tick_curse_fog_decay).
	grid_manager.tick_curse_fog_decay()
