# res://Scripts/map_behaviour.gd
extends Node2D

# Sproži se ob vsaki spremembi izbire (character ali null), da battle UI
# lahko posodobi prikaz izbrane figure.
signal selection_changed(character)
# Sproži se, ko se sposobnost dejansko izvede (glej begin_ability_targeting) -
# battle_ui.gd ga uporabi za osvežitev panela (npr. po Reposition, ki ne
# sproži selection_changed sam po sebi).
signal ability_activated(character)
# Sproži se, ko igralec klikne sovražnika, KO NI izbrana nobena zavezniška
# figura (glej _unhandled_input spodaj) - display-only inšpekcija, NE izbira
# (selected_character ostane nespremenjen). battle_ui.gd poveže to na
# podrobnostni panel (status/prekletstvo), move_highlighter na rdeč predogled
# dosega.
signal enemy_inspected(character)
# Sproži se, ko se HOVER-predogled sovražnika konča (miška se je premaknila
# stran), NE ob kliku - klik na sovražnika ostane "sticky" (glej _inspect_enemy
# spodaj) dokler ga ne prekine drug klik. battle_ui.gd poveže to na
# _clear_detail_panel, da se desni panel ne zatakne na sovražniku, ki ga
# igralec samo mimogrede prehoveria.
signal enemy_inspection_cleared

# ===============================================
# REFERENCE
# ===============================================

@onready var tile_selector = get_node("../TileSelector")
@onready var grid_manager = get_node("../GridManager")
@onready var tile_map = get_node("../Map/TileMapLayer")
@onready var move_highlighter = get_node("../MoveHighlighter")
@onready var battle_controller = get_node("../BattleController") # Dodana @onready referenca
@onready var player_manager = get_node("/root/PlayerManager")

var selected_character: BaseCharacter = null

# Nazadnje uspešno premaknjena/zajemajoča igralčeva figura (S bližnjica jo
# ponovno izbere). Samo igralčeve poteze - AI premiki gredo naravnost skozi
# BattleController._take_enemy_action(), ne skozi to datoteko.
var last_moved_character: BaseCharacter = null

# ===============================================
# HOVER PREDOGLED (nov igralec pogosto samo pomakne miško čez figuro, ne da
# bi kliknil) - po HOVER_DELAY sekundah miritve nad isto figuro prikažemo
# povsem isti predogled kot bi ga dobili s klikom (glej _update_hover spodaj),
# a BREZ dejanske izbire/akcije. Deluje samo, ko ni prave izbire ali sposobnosti
# v teku - te vedno same upravljajo move_highlighter in imajo prednost.
# ===============================================
const HOVER_DELAY := 0.2

var _hover_character: BaseCharacter = null
var _hover_elapsed: float = 0.0
var _hover_shown_for: BaseCharacter = null # figura, katere predogled TRENUTNO kaže hover (ne pravi klik)

# True, če je TRENUTNO prikazano sovražnikovo _inspect_enemy stanje (predogled
# + desni panel) sprožil hover, ne klik - klik ostane sticky, zato hover-out
# sme počistiti panel SAMO, če je bil on tisti, ki ga je nazadnje prikazal.
var _inspect_via_hover: bool = false

# ===============================================
# SPOSOBNOSTI, KI ZAHTEVAJO DODATEN KLIK (Bishop.Longshot, Knight.Reposition)
# ===============================================
# {} kadar ni v teku, sicer {"character": BaseCharacter, "slot": int,
# "def": Dictionary, "targets": Array[Vector2i]}. Naslednji klik na plošči
# se razreši glede na to, namesto po navadni izbirno/premik logiki spodaj.
var pending_ability: Dictionary = {}

func begin_ability_targeting(character: BaseCharacter, slot: int):
	if not is_instance_valid(character):
		return
	var targets := character.get_ability_targets(slot)
	if targets.is_empty():
		return

	# Ciljanje sposobnosti izključuje navadno izbiro/premik dokler ne razrešimo.
	_clear_selection()

	pending_ability = {
		"character": character,
		"slot": slot,
		"def": character.get_ability_defs()[slot - 1],
		"targets": targets,
	}
	move_highlighter.show_ability_targets(targets)

func _cancel_pending_ability():
	pending_ability = {}
	move_highlighter.clear_ability_targets()

func _resolve_pending_ability(clicked_grid: Vector2i):
	var character: BaseCharacter = pending_ability.character
	var slot: int = pending_ability.slot
	var targets: Array = pending_ability.targets

	if clicked_grid not in targets:
		# Klik izven veljavnih tarč: brezplačen preklic, brez porabljene uporabe.
		_cancel_pending_ability()
		return

	_cancel_pending_ability()
	var ok: bool = character.activate_ability(slot, clicked_grid)
	if not ok:
		return

	ability_activated.emit(character)

	if is_instance_valid(battle_controller):
		# Sposobnost porabi 1 iz LOČENEGA proračuna sposobnosti (ne premikov) -
		# poteza se NIKOLI ne konča sama (glej BattleController.consume_ability()),
		# zato konec bitke preverimo ročno (npr. zajetje zadnjega sovražnika).
		battle_controller.consume_ability()
		battle_controller.check_battle_end()

# ===============================================
# POMOŽNE FUNKCIJE ZA IZBIRO
# ===============================================

# Izbere figuro in pokaže njene veljavne poteze.
func _apply_selection(character: BaseCharacter):
	# Izbira zaveznika vedno prekine morebitno tekočo sovražnikovo inšpekcijo
	# (glej _inspect_enemy spodaj) - oboje se nikoli ne prikazuje hkrati.
	move_highlighter.clear_enemy_preview()

	if selected_character:
		selected_character.selected = false
	selected_character = character
	selected_character.selected = true

	var valid_moves = selected_character.calculate_valid_targets()
	move_highlighter.show_moves(valid_moves)

	# Item "farsight_lens": kot spyglass spodaj, a NE presekano z valid_moves
	# te figure - pokaže VSA polja, ki bi jih sovražnik lahko zajel naslednjo
	# potezo, za katerokoli zavezniško figuro. Prednost pred spyglass (širši
	# učinek), če ima igralec oba.
	if player_manager.has_passive("farsight_lens"):
		move_highlighter.show_risk_tiles(grid_manager.tiles_reachable_by(true))
	# Item "spyglass": obarva podmnožico valid_moves, ki bi jo sovražnik
	# lahko zajel naslednjo potezo.
	elif player_manager.has_passive("spyglass"):
		move_highlighter.show_risk_tiles(_compute_risk_tiles(valid_moves))

	selection_changed.emit(selected_character)

# Item "spyglass": presek grid_manager.tiles_reachable_by(true) (unija
# sovražnikovih dosegov - deljena tudi z AI "danger avoidance", glej
# Scripts/TileMap/grid_manager.gd) z valid_moves - v tej igri figura zajema
# natanko vzdolž svojega premika, zato so sovražnikova dosegljiva polja
# točno polja, ki bi jih lahko zajel naslednjo potezo. ZNANA POENOSTAVITEV:
# ne simulira spremembe plošče zaradi lastne poteze igralca (figura se še
# ni premaknila) - sprejemljivo, gre za opozorilni marker, ne za garancijo.
func _compute_risk_tiles(valid_moves: Array[Vector2i]) -> Array[Vector2i]:
	var risky: Array[Vector2i] = []
	if not is_instance_valid(grid_manager):
		return risky
	for target in grid_manager.tiles_reachable_by(true):
		if target in valid_moves and target not in risky:
			risky.append(target)
	return risky

# Odstrani izbiro in počisti poudarke.
func _clear_selection():
	if selected_character:
		selected_character.selected = false
		selected_character = null
	move_highlighter.clear_moves()
	move_highlighter.clear_enemy_preview()
	tile_selector.clear_selection()
	selection_changed.emit(null)

# Inšpekcija sovražnika (klik na sovražnika, KO NI izbrana nobena zavezniška
# figura - glej _unhandled_input LOGIKA 1.D spodaj). Display-only: NE
# nastavi selected_character, zato vsi premik/zajemi tokovi ostanejo
# nespremenjeni. Ponovni klik na isto ali drugo sovražnikovo figuro samo
# osveži predogled (kliče se znova od tam).
func _inspect_enemy(character: BaseCharacter, via_hover: bool = false):
	move_highlighter.show_enemy_preview(character.calculate_valid_targets())
	enemy_inspected.emit(character)
	_inspect_via_hover = via_hover

# Izbira figure preko UI (klik na ikono v battle UI panelu).
func select_character_via_ui(character):
	if not is_instance_valid(character) or not (character is BaseCharacter):
		return
	if character.is_enemy or character.is_obstacle:
		return
	if is_instance_valid(battle_controller) and not battle_controller.can_select():
		return

	_apply_selection(character)
	tile_selector.select_tile(character.grid_pos)

# Izbere nazadnje premaknjeno figuro (S bližnjica) - ista pot kot izbira
# preko UI, torej podeduje can_select()/enemy/obstacle preverjanja.
func select_last_moved():
	if is_instance_valid(last_moved_character):
		select_character_via_ui(last_moved_character)

# ===============================================
# HOVER PREDOGLED
# ===============================================

func _process(delta: float) -> void:
	_update_hover(delta)

# Vsako sličico preveri, katera figura je pod miško. Po HOVER_DELAY sekundah
# nad ISTO figuro pokaže enak predogled kot klik (glej _unhandled_input LOGIKA
# 1.D in _inspect_enemy) - za sovražnika torej DEJANSKO pokliče _inspect_enemy
# (kot bi igralec kliknil nanj), za zaveznika pa samo prikaže valid_moves brez
# nastavitve selected_character (display-only, da se ne prekriva s pravo izbiro).
func _update_hover(delta: float) -> void:
	var blocked: bool = (is_instance_valid(battle_controller) and battle_controller.current_state == battle_controller.BattleState.PLACEMENT) \
		or selected_character != null or not pending_ability.is_empty()

	if blocked:
		# Prava izbira/sposobnost/placement upravlja prikaz sama (in ga je
		# morda pravkar nastavila na isto figuro, ki jo je prej kazal hover) -
		# zato tu SAMO opustimo sledenje, ne kličemo clear_*.
		_hover_character = null
		_hover_elapsed = 0.0
		_hover_shown_for = null
		return

	var mouse_world_pos = get_global_mouse_position()
	var hovered_grid = grid_manager.world_to_grid(mouse_world_pos)
	var used_rect = tile_map.get_used_rect()
	var hovered_character: BaseCharacter = null
	if grid_manager.is_inside_boundary(hovered_grid, used_rect):
		hovered_character = grid_manager.get_character_at(hovered_grid)

	if hovered_character != _hover_character:
		if is_instance_valid(_hover_shown_for):
			if _hover_shown_for.is_enemy:
				move_highlighter.clear_enemy_preview()
				# Desni panel počistimo SAMO, če ga je nazadnje prikazal hover
				# (ne klik) - glej _inspect_via_hover zgoraj.
				if _inspect_via_hover:
					enemy_inspection_cleared.emit()
			else:
				move_highlighter.clear_moves()
		_hover_character = hovered_character
		_hover_elapsed = 0.0
		_hover_shown_for = null

	if not is_instance_valid(hovered_character) or hovered_character.is_obstacle:
		return

	_hover_elapsed += delta
	if _hover_elapsed < HOVER_DELAY or _hover_shown_for == hovered_character:
		return

	# Isto pravilo kot pri kliku (LOGIKA 1.D): sneg skrije sovražnika, hover
	# ga torej ne sme razkriti.
	if hovered_character.is_enemy and grid_manager.has_snow_at(hovered_grid):
		return

	_hover_shown_for = hovered_character
	if hovered_character.is_enemy:
		_inspect_enemy(hovered_character, true)
	else:
		move_highlighter.show_moves(hovered_character.calculate_valid_targets())

# ===============================================
# VNOS (INPUT)
# ===============================================

func _unhandled_input(event):
	# 1. Preverimo, ali gre za levi klik miške.
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	# Med placement fazo klike na ploščo obravnava battle UI (drag & drop),
	# ne izbirna logika bitke.
	if is_instance_valid(battle_controller) and battle_controller.current_state == battle_controller.BattleState.PLACEMENT:
		return

	var mouse_world_pos = get_global_mouse_position()
	var clicked_grid = grid_manager.world_to_grid(mouse_world_pos)
	var used_rect = tile_map.get_used_rect()

	# Sposobnost čaka na klik tarče (Longshot/Reposition) - ta klik razreši
	# NJO namesto navadne izbire/premika, ne glede na kar je bilo izbrano prej.
	if not pending_ability.is_empty():
		_resolve_pending_ability(clicked_grid)
		return

	# 2. ZAVRNITEV KLIKA ZUNAJ MEJA MAPE
	if not grid_manager.is_inside_boundary(clicked_grid, used_rect):
		# Če je bila figura izbrana, jo deselektujemo in počistimo poudarek
		if selected_character:
			_clear_selection()
		# Klik zunaj plošče vedno počisti morebitno sovražnikovo inšpekcijo,
		# tudi če ni bila izbrana nobena zavezniška figura.
		move_highlighter.clear_enemy_preview()
		return

	# Pokaži indikator klika (TileSelector)
	tile_selector.select_tile(clicked_grid)
	
	var clicked_character = grid_manager.get_character_at(clicked_grid)

	# ===================================================
	# LOGIKA 1: KLIK NA FIGURO (ATTEMPT CAPTURE / SWITCH SELECTION)
	# ===================================================
	
	if clicked_character:
		# A) KLIK NA ISTO FIGURO → DESELECT
		if selected_character == clicked_character:
			_clear_selection()
			return

		# B) KLIK NA ŽE IZBRANO FIGURO (selected_character je nastavljen)
		if selected_character:

			# Ali je kliknjena figura SOVRAŽNIK? (Poskus zajetja)
			if clicked_character.is_enemy != selected_character.is_enemy:

				# try_move() v BaseCharacter.gd zdaj obravnava logiko capture()
				var mover := selected_character
				if selected_character.try_move(clicked_grid):
					last_moved_character = selected_character

					# Uspešno zajetje (captured)
					_clear_selection()

					# Zajetje porabi 1 iz proračuna premikov te poteze - poteza
					# se ne konča sama (glej consume_move()). consume_move_for()
					# namesto consume_move() neposredno, da Queen.Command lahko
					# preskoči porabo za svojo tarčo (glej free_move_character).
					if is_instance_valid(battle_controller):
						battle_controller.consume_move_for(mover)

						# Item "vicious_knights": trmoglavo zajetje s skakačem
						# podeli +1 premik, omejeno na 1x na potezo.
						if mover.strName == "knight" and player_manager.has_passive("vicious_knights") \
								and not battle_controller.vicious_knight_used:
							battle_controller.vicious_knight_used = true
							battle_controller.add_bonus_move()

						battle_controller.check_battle_end()

					return
				else:
					# Neveljavno zajetje (izven dosega). Ohranimo izbiro ali deselektiramo?
					# Odločitev: Pokažemo napako in ohranimo izbiro, če je to igralčeva poteza.
					# Tukaj deselektiramo, če ni bilo uspešno, za preprostejši UX.
					_clear_selection()
					return


			# C) KLIK NA ZAVEZNIKA (SWITCH SELECTION)
			else:
				# Item "decoy": ni prava izbirna figura (glej is_decoy deklaracijo
				# na base_character.gd) - klik nanjo ne zamenja izbire.
				if clicked_character.is_decoy:
					return
				# Deselektiraj staro figuro in izberi novo
				_apply_selection(clicked_character)
				return

		# D) KLIK NA FIGURO, KO NI BILA IZBRANA NOBENA DRUGA
		else:
			# Dovolimo izbiro samo IGRALČEVIH, NE-decoy figur - igralec ne sme
			# povleči/premakniti vabe kot da bi bila prava figura.
			if clicked_character.is_decoy:
				return
			if not clicked_character.is_enemy:
				_apply_selection(clicked_character)
				return
			else:
				# Klik na sovražnika, ko ni izbrana nobena figura: inšpekcija
				# (prikaz dosega + statusa/prekletstva - glej _inspect_enemy zgoraj).
				# Snow rework: če sovražnik stoji na zasneženem polju, ga NE
				# razkrijemo z inšpekcijo - to bi razkrilo, kaj se skriva pod
				# snegom, brez tveganja premika nanj (glej SNOW_REWORK_PLAN.md
				# odločitev 8). Premik/zajetje (LOGIKA 1.B/2 zgoraj) ostane
				# nespremenjeno - presenečeno zajetje je namerno.
				if grid_manager.has_snow_at(clicked_grid):
					return
				_inspect_enemy(clicked_character)
				return
	
	# ===================================================
	# LOGIKA 2: KLIK NA PRAZNO POLJE (PREMIK)
	# ===================================================
	
	if selected_character:
		# Poskus premika na kliknjeno polje
		var mover := selected_character
		if selected_character.try_move(clicked_grid):
			last_moved_character = selected_character

			# Uspešen premik
			_clear_selection()

			# Premik porabi 1 iz proračuna premikov te poteze - poteza se ne
			# konča sama (glej consume_move()). consume_move_for() namesto
			# consume_move() neposredno, da Queen.Command lahko preskoči
			# porabo za svojo tarčo (glej free_move_character). Uporabimo
			# `mover`, ujeto PRED _clear_selection(), ker ta selected_character
			# nastavi na null (glej isti vzorec pri zajetju zgoraj).
			if is_instance_valid(battle_controller):
				battle_controller.consume_move_for(mover)
				battle_controller.check_battle_end()

			return

		# Če premik ni bil uspešen (klikal je na prazno polje, ki ni veljavna tarča):
		_clear_selection()
		return

	# Klik na prazno polje, ko ni bila izbrana nobena figura: počisti
	# morebitno sovražnikovo inšpekcijo (glej _inspect_enemy zgoraj).
	move_highlighter.clear_enemy_preview()
