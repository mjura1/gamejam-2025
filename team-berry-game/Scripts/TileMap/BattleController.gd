extends Node
class_name BattleController

# ===============================================
# REFERENCE
# ===============================================

@onready var grid_manager: GridManager = get_node("../GridManager")
@onready var player_manager = get_node("/root/PlayerManager")
@onready var move_highlighter = get_node("../MoveHighlighter")

# Sproži se ob vsaki spremembi stanja bitke (za battle UI: turn label,
# START/END TURN gumb, placement overlay).
signal state_changed(new_state)

# Sproži se ob vsaki spremembi moves_remaining/abilities_remaining (za
# battle UI prikaz nad turn labelom). Ločena proračuna - glej opombo pri
# moves_remaining spodaj za razlog.
signal moves_changed(remaining: int, max_moves: int)
signal abilities_changed(remaining: int, max_abilities: int)

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
	# 1. Pridobimo trenutni napredek igralca
	var current_floor = 0
	if is_instance_valid(player_manager):
		# Uporabimo current_map_floor, ki smo ga dodali v PlayerManager.gd
		current_floor = player_manager.current_map_floor

	# 2. Pokrijemo mapo z dinamično meglo (snežno odejo)
	if is_instance_valid(grid_manager):
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

func end_player_turn():
	print("<<< KONEC POTEZE IGRALCA >>>")

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

		await _take_enemy_action(character)

		# Če je ta akcija končala bitko, takoj prekinemo potezo
		if check_battle_end():
			return

	end_enemy_turn()

# Izračuna najboljšo potezo za eno sovražnikovo figuro in jo izvede.
# Če je premik uspel, poskrbi za vizualizacijo + premor pred naslednjo potezo.
func _take_enemy_action(character: BaseCharacter) -> void:
	var action = character.calculate_best_move()
	if action.is_empty():
		return

	var from_pos: Vector2i = character.grid_pos
	var is_capture: bool = action.get("move_type", "") == "CAPTURE"

	# try_move sam ponovno preveri veljavnost tarče in izvede premik ALI zajetje
	var moved: bool = character.try_move(action["target_pos"])
	if moved:
		await _flash_move_and_pause(from_pos, action["target_pos"], is_capture)

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
		if player_manager.is_boss_floor:
			GF.call_deferred("advance_map_tier")
		else:
			GF.call_deferred("return_to_map")
		return true

	if player_manager.activeGone():
		_set_state(BattleState.GAME_OVER)
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
