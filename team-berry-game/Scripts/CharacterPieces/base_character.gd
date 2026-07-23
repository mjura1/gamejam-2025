# res://Scripts/CharacterPieces/base_character.gd
extends Node2D
class_name BaseCharacter

# Skoki viteza - eno mesto resnice, ki jo knight.gd.get_move_directions()
# vrne, in ki jo item "mounted_hunters" doda queen.gd/bishop.gd.
const KNIGHT_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 2),
	Vector2i(2, 1),
	Vector2i(-1, 2),
	Vector2i(-2, 1),
	Vector2i(1, -2),
	Vector2i(2, -1),
	Vector2i(-1, -2),
	Vector2i(-2, -1),
]

var grid_pos: Vector2i
# Tracks if the piece has ever seen a player

var has_spotted_player: bool = false
var last_known_player_pos: Vector2i = Vector2i.ZERO
var last_known_direction: Vector2i = Vector2i.ZERO
var is_panicking: bool = false


# ----------------- REFERENCE -----------------
# GridManager zdaj ročno dodeli referenco
var grid_manager
@onready var battle_controller = get_node("../BattleController")
@onready var tile_map = get_node("../Map/TileMapLayer")
@onready var player_manager = get_node("/root/PlayerManager")
@onready var ability_data = get_node("/root/AbilityData")
@onready var settings_manager = get_node("/root/SettingsManager")
# NAMENOMA get_node(), ne bare "CurseData" identifikator (glej Phase 1
# opombo pri "curse" spodaj/ENEMY_CURSES_PLAN.md): base_character.gd ima
# class_name, torej ga --script/headless zgodnji "global class scan"
# eagerly PREVEDE PREDEN so avtoloadi registrirani - CELO en sam gol
# "CurseData.karkoli()" klic KJERKOLI v telesu te datoteke (ne samo v
# tipiziranih deklaracijah) sproži "Identifier not found: CurseData" v
# VSEH smoke testih (preverjeno). get_node() se razreši šele ob teku, ne
# ob prevajanju - varno.
@onready var curse_data = get_node("/root/CurseData")
# NAMENOMA get_node(), ne bare "AiStrategyData" identifikator - isti razlog kot
# curse_data zgoraj. get_strategy() vrne EnemyAIStrategy, a spodaj v
# calculate_best_move() ostane ne-tipizirano iz istega razloga kot "var curse"
# (glej opombo tam) - ne SME se statično tipizirati na EnemyAIStrategy NIKJER v
# tej datoteki.
@onready var ai_strategy_data = get_node("/root/AiStrategyData")

# ----------------- NASTAVITVE IN VREDNOSTI -----------------
@export var selected: bool = false
@export var move_range: int = 1
@export var is_enemy: bool = false
@export var is_obstacle: bool = false
@export var character_scene_path: String = ""
@export var panic_distance: int = 2
@export var panic_randomness: float = 0.5 # 0 = calm, 1 = total chaos
@export var strName: String

# ----------------- ABILITIES -----------------
# Odklenjeni sposobnostni sloti (slot 1 je vedno odklenjen). Trajno stanje
# živi v PlayerManager.piece_upgrades (po TIPU figure, kupljena vozlišča
# drevesa iz GameParameters/skill_trees.json) - figura ga prebere ob registraciji na
# mrežo (glej _load_persistent_upgrades in is_slot_unlocked).
var unlocked_slots: Array[int] = [1]

# slot (1|2|3) -> trenutni nivo TE sposobnosti (1=base, 2=mid, ABILITY_LEVEL_MAX=upgraded).
# Vsak slot se dviguje NEODVISNO (kupljena a*_lv* vozlišča drevesa) - ločeno
# od unlocked_slots, ki samo odklene slot.
# Tudi to je samo bitki-lokalna kopija stanja iz PlayerManager.piece_upgrades.
const ABILITY_LEVEL_MAX := 3
const ABILITY_TIER_KEYS := ["base", "mid", "upgraded"]
var ability_levels: Dictionary = {1: 1, 2: 1, 3: 1}

# Effect slovarji kupljenih PASIVNIH vozlišč drevesa za ta tip figure (vse
# razen ability_level/ability_unlock - glej SKILL_TREE_PLAN.md §2.1). Napolni
# jih _load_persistent_upgrades; beri prek has_passive/get_passive/has_flag.
var passives: Array = []

# Osnovni move_range iz scene - _load_persistent_upgrades ga zajame ob prvem
# klicu, da "move_range" pasiva ob morebitni ponovni registraciji iste
# instance ne prišteje bonusa dvakrat.
var _base_move_range: int = -1

# slot (1|2) -> preostalo število uporab v tej bitki.
var ability_uses_remaining: Dictionary = {}

# ID cone (glej GridManager.zones), ki jo trenutno drži ta figura (Traps/
# Reinforce) - -1, če nobene. Cona se počisti, ko se figura naslednjič
# premakne ali umre.
var owned_zone_id: int = -1

# Knight: Evade - dokler je true, te figure ni mogoče zajeti.
var is_capture_immune: bool = false

# King: Cleanse - obrnjen sovražnik. Ostane oznaka, da die() ne poroča
# napačnega vnosa v trajni roster/dead_party (glej register_dead_character).
var is_converted_ally: bool = false

# Item "bloodhounds": prijazna figura (trenutno samo volk), ki deluje sama
# po igralčevi potezi, kot AI (glej BattleController._move_autonomous_allies).
var is_autonomous: bool = false

# Prekletstvo sovražnika (od nadstropja CurseData.get_min_floor() naprej,
# glej battle.gd._apply_curses) -
# null, če figura ni prekleta. Glej Scripts/Curses/base_curse.gd.
# NAMERNO netipizirano (ne "var curse: BaseCurse", glej tudi apply_curse
# spodaj): base_character.gd je del enega globalno skeniranih class_name
# skriptov (BaseCharacter), ki se v --script/headless zagonih (VSI smoke
# testi + run_unit_tests.gd) eagerly prevedejo PREDEN so avtoloadi (CurseData)
# sploh registrirani kot globalni identifikatorji. Vsaka statična tipizacija
# (class var, funkcijski parameter, celo lokalen typed var znotraj metode) na
# BaseCurse tu prisili GDScript, da polno prevede base_curse.gd (ki bere
# CurseData v svojih metodah) v tem zgodnjem koraku -> "Identifier not found:
# CurseData" compile error. Zato ostane ne-tipizirano povsod v tej datoteki;
# curse_marker.gd sam SME tipizirati na BaseCurse (glej apply_curse spodaj -
# nalagamo ga z load(), ne z golim CurseMarker identifikatorjem, iz istega
# razloga).
var curse = null

# Prekletstvo "stunning_gaze": koliko igralčevih potez ta figura še ne more
# premikati/uporabljati sposobnosti (glej calculate_valid_targets/
# activate_ability spodaj in BattleController.end_player_turn tick-down).
var stunned_turns: int = 0

# Prekletstvo "entangle": koliko igralčevih potez ta figura še ne more
# premakniti na PRAZNO polje (zajetja so še vedno dovoljena, za razliko od
# stunning_gaze - glej calculate_valid_targets spodaj in
# BattleController.end_player_turn tick-down).
var rooted_turns: int = 0

# Snow rework: koliko ZAPOREDNIH igralčevih potez je ta figura obkrožena s
# snegom na vseh 4 ortogonalnih straneh (glej GridManager.is_snow_surrounded in
# BattleController._update_snow_freeze_states) - resetira se na 0, takoj ko se
# obroč prekine. Pri SNOW_DEATH_TURNS figura umre.
var snow_trapped_turns: int = 0

# Snow rework: ali je ta figura trenutno ZAMRZNJENA (ne more se premakniti,
# sposobnosti pa še vedno delujejo) - glej is_snow_frozen_now spodaj za
# "leno" (lazy) odmrzovanje, ki dovoljuje reševanje SREDI poteze.
var snow_frozen: bool = false

# Wave 2 items (frost_nova, camp_kit, stormcaller, ...): NEODVISEN fiksno-
# trajajoč "zamrznjen" status, ločen od snow_frozen zgoraj - snow_frozen se
# leno odmrzne takoj, ko se snežni obroč prekine (is_snow_frozen_now), kar ni
# uporabno za "zamrzni za natanko N potez" učinke. Za razliko od snega velja
# za OBE strani (igralec lahko zamrzne sovražnika). Tik-tok v
# BattleController.end_player_turn (glej tam).
var effect_frozen_turns: int = 0

# Item "smoke_screen": ta figura je skrita sovražnikovemu ciljanju (AI je ne
# izbere za zajetje/gonjo - glej calculate_best_move spodaj), dokler se ne
# premakne ali zajame (glej execute_move, ki to počisti).
var is_hidden: bool = false

# Item "warm_cloak": ta figura za PRESTANEK BITKE ne more biti zamrznjena od
# snega (glej BattleController._update_snow_freeze_states - preskoči snow_frozen
# nastavitev, snow_trapped_turns pa še vedno šteje).
var is_freeze_immune: bool = false

# ----------------- audio -----------------------
@onready var move_sound: AudioStreamPlayer = get_node_or_null("MoveSound")
@onready var take_sound: AudioStreamPlayer = get_node_or_null("TakeSound")

# ----------------- INITIALIZACIJA (KLJUČNA ZA IZBIRO) -----------------

func _ready():
	pass
		
# NOVO: Kliče ga GridManager, ko je pripravljen in je dodeljena referenca.
func on_grid_manager_registered():
	# Tu smo 100% prepričani, da je self.grid_manager že nastavljen.
	
	# 1. Izračunamo mrežno pozicijo iz globalne pozicije
	grid_pos = grid_manager.world_to_grid(global_position)
	
	# 2. Poravnamo globalno pozicijo (centriranje)
	global_position = grid_manager.grid_to_world(grid_pos)
	
	# 3. Registriramo figuro v slovar zasedenosti
	grid_manager.occupy(grid_pos, self)

	# 4. Preberemo trajne nadgradnje tipa (nivoji + odklenjeni sloti + pasive)
	# in napolnimo sposobnosti (velja tudi za figure, ki se pojavijo sredi
	# bitke - npr. King.Heal - in za test_sandbox figure).
	_load_persistent_upgrades()
	reset_ability_uses()

	# Za debug:
	print("%s: Uspešno registriran in inicializiran na mreži %s." % [self.name, str(grid_pos)])

# Dodeli prekletstvo tej figuri (glej battle.gd._apply_curses) in doda njen
# vizualni marker (delci/pulzirajoč tint ali statična oblika, glej
# Scripts/Curses/curse_marker.gd - reduced_motion preklop). "new_curse"
# NAMERNO netipiziran (glej opombo pri "var curse" zgoraj). Iz istega razloga
# CurseMarker nalagamo z load() namesto z golim class_name identifikatorjem -
# ta bi enako prisilil zgodnji compile base_curse.gd/CurseData.
func apply_curse(new_curse) -> void:
	# Pasiva "curse_immune" (skill tree): prekletstva se te figure ne primejo -
	# brez stanja IN brez vizualnega markerja.
	if has_passive("curse_immune"):
		return
	# Odstrani morebiten OBSTOJEČI marker PRED dodajanjem novega - sicer bi
	# add_child sam preimenoval novega (podvojeno ime), clear_curse pa bi
	# kasneje z get_node_or_null("CurseMarker") našel samo enega od dveh in
	# drugega pustil za sabo (glej curse_marker._exit_tree - ta osirotel
	# marker bi obdržal svoj pulzirajoč tween, ki se prepira z novim).
	_remove_curse_marker()
	curse = new_curse
	var marker = load("res://Scripts/Curses/curse_marker.gd").new()
	marker.name = "CurseMarker"
	add_child(marker)
	marker.setup(self, curse)
	if curse:
		curse.on_applied(self)


# King.Cleanse: obrnjena figura NE obdrži prekletstva kot zaveznica - eno
# mesto resnice za "odstrani prekletstvo" (počisti stanje + vizualni marker/
# tint), da ga ni treba podvajati na vsakem klicnem mestu.
func clear_curse() -> void:
	curse = null
	_remove_curse_marker()
	modulate = Color.WHITE


func _remove_curse_marker() -> void:
	var marker := get_node_or_null("CurseMarker")
	if marker:
		# remove_child() PRED queue_free(): queue_free() sam po sebi šele
		# odloženo (konec sličice) odstrani vozlišče - brez remove_child()
		# bi get_node_or_null("CurseMarker") še kratek čas vrnil staro
		# vozlišče, čeprav je "logično" že počiščeno.
		remove_child(marker)
		marker.queue_free()


# ----------------- GIBANJE IN CILJANJE -----------------

func get_move_directions() -> Array[Vector2i]:
	# Podrazredi (Bishop, Rook) implementirajo to
	return []

# Item "castle": kralj je nezajemljiv, dokler ga vidi prijateljska trdnjava
# (ravna črta, prvi zadetek na poti mora biti trdnjava). Zaščiti samo pred
# navadnimi zajetji (glej calculate_valid_targets spodaj) - NE pred Queen.
# Exterminate ali drugimi sposobnostmi, ki ne gredo skozi to preverjanje.
func is_castle_protected() -> bool:
	if is_enemy or strName != "king": return false
	if not player_manager.has_passive("castle"): return false
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir in directions:
		var step: Vector2i = grid_pos + dir
		while grid_manager.is_inside_boundary(step, tile_map.get_used_rect()):
			if grid_manager.is_occupied(step):
				var c = grid_manager.get_character_at(step)
				if c and not c.is_enemy and not c.is_obstacle and c.strName == "rook":
					return true
				break
			step += dir
	return false

# Snow rework: PRAVI vir resnice za "ali je figura trenutno zamrznjena" -
# leno (lazy) preveri, ali se je obroč snega že prekinil, in če DA, takoj
# odmrzne (thaw je torej TAKOJŠNJI, znotraj iste poteze - npr. ko druga
# figura prime nanjo prosto polje in prekine obroč). Klicati namesto branja
# gole "snow_frozen" spremenljivke povsod, kjer je pomembno trenutno stanje
# (gibanje, UI značke/status).
func is_snow_frozen_now() -> bool:
	if snow_frozen and is_instance_valid(grid_manager) \
			and not grid_manager.is_snow_surrounded(grid_pos):
		snow_frozen = false
		snow_trapped_turns = 0
	return snow_frozen

func calculate_valid_targets() -> Array[Vector2i]:
	var targets: Array[Vector2i] = []

	# Prekletstvo "stunning_gaze": omamljena figura se ne more premakniti
	# (traja natanko igralčevo naslednjo potezo, glej BattleController.end_player_turn).
	if stunned_turns > 0:
		return targets

	# Snow rework: zamrznjena figura (obkrožena s snegom na vseh 4 straneh)
	# se ne more premakniti - samo zavezniki zamrznejo (glej
	# BattleController._update_snow_freeze_states).
	if not is_enemy and is_snow_frozen_now():
		return targets

	# Wave 2 items: effect_frozen_turns (glej deklaracijo zgoraj) - za razliko
	# od snega velja za OBE strani.
	if effect_frozen_turns > 0:
		return targets

	# Bishop.Traps: dokler je ta figura ujeta v sovražnikovo cono, se ne more
	# premakniti nikamor.
	if is_instance_valid(grid_manager) and grid_manager.is_frozen(grid_pos, is_enemy):
		return targets

	# Item "fortress": za sovražnike so polja med prijateljsko trdnjavo in
	# hišo v njeni liniji neprehodna (ne moreš vstopiti niti drseti skoznje).
	var fortress: Array[Vector2i] = []
	if is_enemy:
		fortress = grid_manager.fortress_blocked_tiles()

	for dir in get_move_directions():
		for step in range(1, move_range + 1):
			var target_pos := grid_pos + dir * step

			# 1. Preverjanje mej
			if not grid_manager.is_inside_boundary(target_pos, tile_map.get_used_rect()):
				break

			if target_pos in fortress:
				break

			# 2. Preverjanje zasedenosti
			if grid_manager.is_occupied(target_pos):
				var target_char = grid_manager.get_character_at(target_pos)

				# PREVERJANJE: Ali je tarča sovražnik?
				if target_char and target_char.is_enemy != is_enemy and target_char.is_obstacle != true:
					# Knight.Evade: imunska figura ne more biti zajeta z
					# navadnim premikom/zajetjem. Item "castle": enako za
					# kralja, dokler ga vidi prijateljska trdnjava.
					if target_char.is_capture_immune or target_char.is_castle_protected():
						break
					# Rook.Reinforce: polje je znotraj sovražnikove cone - ni
					# dovoljeno niti zajetje na to polje.
					if not grid_manager.is_entry_denied(target_pos, is_enemy):
						targets.append(target_pos)

				# Gibanje se vedno ustavi ob prvi zasedeni celici
				break

			# 3. Polje je prazno - Rook.Reinforce ga lahko izloči kot cilj.
			if not grid_manager.is_entry_denied(target_pos, is_enemy):
				targets.append(target_pos)

	# Prekletstvo "entangle": ukoreninjena figura obdrži SAMO zajetja (polja,
	# ki jih že zgoraj zasede nasprotnik) - navadni premiki na prazna polja
	# odpadejo.
	if rooted_turns > 0:
		targets = targets.filter(func(pos):
			var t = grid_manager.get_character_at(pos)
			return t != null and t.is_enemy != is_enemy)

	return targets

const MOVE_SLIDE_DURATION := 0.18

# Premakne figuro na dano svetovno pozicijo - drsenje (tween), razen če je v
# Settings vklopljen "reduced motion" (dostopnost), kjer skoči nanjo takoj.
# Uporablja ga execute_move (premiki v bitki) in battle_ui.move_placed_piece
# (drag&drop v placement fazi).
func slide_to(new_global_pos: Vector2):
	if settings_manager.reduced_motion:
		global_position = new_global_pos
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", new_global_pos, MOVE_SLIDE_DURATION)

# Premesti figuro na novo lokacijo
func execute_move(target: Vector2i):
	# Item "snowshoes"/"iron_pawns": zajameta IZVORNO polje PRED premikom
	# (grid_pos spodaj postane target).
	var from_pos: Vector2i = grid_pos

	# Item "smoke_screen": premik ALI zajetje (capture() spodaj samo pokliče
	# execute_move za dejanski premik napadalca) prekine skritost.
	is_hidden = false

	# Bishop.Traps/Rook.Reinforce: premik te figure sprosti njeno cono.
	if owned_zone_id != -1 and is_instance_valid(grid_manager):
		grid_manager.remove_zone(owned_zone_id)
		owned_zone_id = -1

	# 1. Posodobitev mreže in pozicije
	grid_manager.vacate(grid_pos)
	grid_pos = target
	grid_manager.occupy(grid_pos, self)
	slide_to(grid_manager.grid_to_world(grid_pos))
	if move_sound: move_sound.play()

	# Item "iron_pawns": pešec, ki se premakne ZA NATANKO 1 polje (ne 2+, kar
	# je pešcu obiajen dvojni korak), za preostanek te poteze ne more biti
	# zajet - deli is_capture_immune z Knight.Evade, torej se ponastavi po
	# istem "za eno potezo" pravilu (glej BattleController._clear_expired_evade).
	# Namerno BREZPOGOJNO nastavljeno (ne samo "or"): če se ista figura v isti
	# potezi premakne znova (dodaten premik), imuniteta odraža SAMO zadnji premik.
	if not is_enemy and strName == "pawn" and is_instance_valid(player_manager) \
			and player_manager.has_passive("iron_pawns"):
		var step: Vector2i = grid_pos - from_pos
		is_capture_immune = maxi(absi(step.x), absi(step.y)) == 1

	# ===============================================
	# FOG OF WAR (NOVO)
	# ===============================================

	# Snow rework: figura razkrije SAMO polje, na katerega stopi (ne več
	# 3x3 okolico) - snežno odejo/prekletstveno meglo zdaj razkrivajo samo
	# namenske sposobnosti/predmeti (rook/pawn/flare/pasive), premikanje pa
	# je zdaj tvegano-nagradna mehanika (glej SNOW_REWORK_PLAN.md).
	if not is_enemy and is_instance_valid(grid_manager):
		grid_manager.reveal_area([grid_pos])

		# Item "snowshoes": za TO potezo se sneg stopi na vsakem polju, ki ga
		# figura prečka na poti (ne samo na pristajalnem polju) - deli pot
		# BattleController._compute_path_tiles uporablja tudi za vizualizacijo
		# sovražnikovih potez.
		if is_instance_valid(battle_controller) and battle_controller.snowshoes_active_this_turn:
			grid_manager.reveal_area(battle_controller._compute_path_tiles(from_pos, grid_pos))

		# Pasiva "move_reveal" (skill tree): po zaključenem premiku dodatno
		# razkrij (2r+1)² kvadrat okoli pristajalnega polja.
		if has_passive("move_reveal"):
			var reveal_radius: int = int(get_passive("move_reveal").get("radius", 1))
			grid_manager.reveal_area(GridManager.square_radius_tiles(grid_pos, reveal_radius))

	# Queen.Lure: ta figura je s premikom "ubogala" vabo - status se sprosti.
	if is_instance_valid(battle_controller) and self in battle_controller.lured_enemies:
		battle_controller.lured_enemies.erase(self)

	# Queen.Exterminate: kakršenkoli premik/zajetje (zaveznika ALI sovražnika)
	# med naboritvijo sproži eksplozijo okoli kraljičine pozicije.
	if is_instance_valid(battle_controller) and not battle_controller.exterminate_armed.is_empty():
		battle_controller.trigger_exterminate_if_armed()


func try_move(target: Vector2i) -> bool:
	# Omogoči AI-ju (in item "bloodhounds" avtonomnim zaveznikom) premik brez
	# preverjanja proračuna premikov igralca - ta je že porabljen do konca
	# igralčeve poteze.
	if not is_enemy and not is_autonomous and not battle_controller.can_move():
		return false
	
	# 1. Ali je tarča veljavna tarča za premik/zajetje?
	if target not in calculate_valid_targets():
		return false
	
	var target_char = grid_manager.get_character_at(target)
	
	# 2. Preverimo zasedenost
	if target_char:
		# Polje je zasedeno. Preverimo frakcijo.
		
		# 2a. Poskus ZAJETJA (Tarča je sovražnik)
		if target_char.is_enemy != is_enemy:
			
			# Izvedemo zajetje tarče!
			capture(target_char)
			
			return true # Uspešno zajetje
		
		# 2b. Klik na ZAVEZNIKA (Ni dovoljeno, saj smo v dosegu)
		else:
			return false
	
	# 3. Polje je PRAZNO (Navaden premik)
	execute_move(target)
	return true

# ----------------- SMRT IN ZAJETJE (KLJUČNO ZA REVIVE) -----------------

# Odstranitev figure iz igre (umre). Funkcija SAMO poroča in odstrani figuro -
# konec bitke po koncu akcije zazna BattleController.check_battle_end().
func die():
	print("Figura %s je bila uničena in odstranjena." % name)

	# Bishop.Traps/Rook.Reinforce: smrt lastnika sprosti njeno cono.
	if owned_zone_id != -1 and is_instance_valid(grid_manager):
		grid_manager.remove_zone(owned_zone_id)
		owned_zone_id = -1

	# Queen.Exterminate: če umre naboritev prav zaradi te figure, se
	# eksplozija ne sproži post-mortem - raje razorožimo.
	if is_instance_valid(battle_controller) and battle_controller.exterminate_armed.get("owner") == self:
		battle_controller.exterminate_armed = {}

	# Osvobodi polje na mreži
	if is_instance_valid(grid_manager):
		grid_manager.vacate(grid_pos)

	if is_converted_ally:
		# King.Cleanse: obrnjena figura ni del trajnega rosterja - samo
		# odstranimo jo iz aktivne ekipe za to bitko, brez dead_party vnosa.
		player_manager.remove_converted_ally("friendly_" + strName)
	elif is_enemy:
		player_manager.register_dead_character("enemy_" + strName)
	else:
		player_manager.register_dead_character("friendly_" + strName)

	# Item "bounty": prva sovražnikova smrt v bitki odloči zmago/poraz stave.
	if is_enemy and not is_obstacle and is_instance_valid(battle_controller):
		battle_controller.on_enemy_died(self)

	queue_free() # Uniči vozlišče

# Logika zajetja tarče in premika napadalca na tarčino polje
func capture(target: BaseCharacter):
	print("Izvajam zajetje tarče...")
	
	# KRITIČNO: Shranimo pozicijo tarče, preden jo uničimo
	var target_pos = target.grid_pos
	
	# 1. Zajem/Smrt tarče
	target.die()
	if take_sound: take_sound.play()
	
	# 2. Premik napadalca na tarčino zdaj prosto polje
	# Klic execute_move zdaj poskrbi tudi za posodobitev FOG OF WAR
	execute_move(target_pos)


# ----------------- AI LOGIKA (POPRAVLJENA) -----------------
func can_see_player(max_view_range: int) -> BaseCharacter:
	var seen := find_visible_enemies(max_view_range)
	return seen[0] if not seen.is_empty() else null

# ----------------- SPOSOBNOSTI: SKUPNE POGLED/GEOMETRIJA POMOŽNE FUNKCIJE -----------------

# Sprehodi se po vseh smereh gibanja te figure (glej get_move_directions) in
# zbere PRVEGA nasprotnika, ki ga vsaka smer zadene (blokira jo prva figura
# ali ovira na poti - enako kot can_see_player, le da zbira iz VSEH smeri
# namesto da se ustavi pri prvi najdeni). Uporabljajo ga Bishop.Longshot in
# King.Cleanse. directions: prazno = privzete smeri te figure
# (get_move_directions) - Bishop.Longshot poda svoje (glej _longshot_directions),
# da lahko z nivojem sposobnosti razširi tarčni vzorec (X -> X + ravne smeri).
func find_visible_enemies(max_view_range: int, directions: Array[Vector2i] = []) -> Array[BaseCharacter]:
	var found: Array[BaseCharacter] = []
	var search_directions := directions if not directions.is_empty() else get_move_directions()

	for dir in search_directions:
		for step in range(1, max_view_range + 1):
			var check_pos = grid_pos + dir * step

			if not grid_manager.is_inside_boundary(check_pos, tile_map.get_used_rect()):
				break

			if grid_manager.is_occupied(check_pos):
				var seen_char = grid_manager.get_character_at(check_pos)

				if seen_char and seen_char.is_enemy != is_enemy and not seen_char.is_obstacle:
					found.append(seen_char)

				# Pogled blokira katerakoli figura (ali ovira)
				break

	return found

# Enak sprehod kot find_visible_enemies, a zbira PRVEGA ZAVEZNIKA (ne
# sovražnika) na vsaki poti - Rook.Castling in Queen.Command potrebujeta LOS
# do zaveznika, ki ga lahko izbereta kot tarčo, ne do sovražnika za zajetje.
# Isto "prva figura na poti blokira pogled" obnašanje (glej find_visible_enemies).
func find_visible_allies(max_view_range: int, directions: Array[Vector2i] = []) -> Array[BaseCharacter]:
	var found: Array[BaseCharacter] = []
	var search_directions := directions if not directions.is_empty() else get_move_directions()

	for dir in search_directions:
		for step in range(1, max_view_range + 1):
			var check_pos = grid_pos + dir * step

			if not grid_manager.is_inside_boundary(check_pos, tile_map.get_used_rect()):
				break

			if grid_manager.is_occupied(check_pos):
				var seen_char = grid_manager.get_character_at(check_pos)

				if seen_char and seen_char.is_enemy == is_enemy and not seen_char.is_obstacle and seen_char != self:
					found.append(seen_char)

				break

	return found

# Enak sprehod kot find_visible_enemies, a zbira PRAZNA polja (za King.Heal -
# kam lahko postavimo oživljene figure). Vsaka smer se ustavi pri prvi
# zasedeni celici, da ne razkrije mest "za" blokado.
func get_empty_tiles_in_los(max_view_range: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []

	for dir in get_move_directions():
		for step in range(1, max_view_range + 1):
			var check_pos = grid_pos + dir * step

			if not grid_manager.is_inside_boundary(check_pos, tile_map.get_used_rect()):
				break

			if grid_manager.is_occupied(check_pos):
				break

			found.append(check_pos)

	return found

# ----------------- SPOSOBNOSTI: DISPATCH -----------------

# Podrazredi (Ally/pawn.gd ipd.) povozijo to in vrnejo TOČNO 2 slovarja
# (za slot 1 in slot 2) v obliki:
# {
#   "id": "rally", "name": "Rally", "needs_target": false,
#   "base":     {"desc": "..."},
#   "upgraded": {"desc": "..."},
# }
# Dodatni "znanci" ability-specifičnih vrednosti (radius ipd.) gredo v
# base/upgraded slovarja in jih _execute_ability prebere sam. Število uporab
# (base_uses/max_uses) NI tu - to živi v GameParameters/abilities.json (glej AbilityData
# autoload), da lahko balansiramo brez posega v kodo.
func get_ability_defs() -> Array:
	return []

# Vrne base/mid/upgraded pod-slovar za dani slot, glede na NJEGOV nivo
# (ability_levels[slot], ne glede na to, ali je slot 2 sploh odklenjen).
func _tier_data(slot: int) -> Dictionary:
	var defs := get_ability_defs()
	if slot < 1 or slot > defs.size():
		return {}
	var def: Dictionary = defs[slot - 1]
	var level := clampi(ability_levels.get(slot, 1), 1, ABILITY_LEVEL_MAX)
	return def.get(ABILITY_TIER_KEYS[level - 1], {})

# Vrne relativne odmike (Vector2i, glede na (0,0)) za dano AOE obliko - bere
# tier.shape ("square", privzeto, ali "plus") in tier.radius (samo za
# "square"). Uporabljajo ga vse AOE sposobnosti (Lantern Signal, Traps,
# Exterminate, Lookout, Reinforce), da lahko delijo isto "square"/"plus"
# stopnjevanje brez podvajanja kode. Glej GridManager.plus_extended_offsets.
func _area_offsets(tier: Dictionary) -> Array[Vector2i]:
	if tier.get("shape", "square") == "plus":
		return GridManager.plus_extended_offsets()
	return GridManager.square_radius_tiles(Vector2i.ZERO, tier.get("radius", 1))

# Kot zgoraj, a že premaknjeno na dejanski center (world/grid pozicijo).
func _area_tiles(tier: Dictionary, center: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for offset in _area_offsets(tier):
		tiles.append(center + offset)
	return tiles

# Vrne max. število uporab za dani slot iz AbilityData (GameParameters/abilities.json),
# glede na trenutni nivo TEGA slota (ability_levels[slot]), plus morebitne
# "extra_uses" pasive drevesa za ta slot.
func _ability_uses_max(slot: int) -> int:
	var defs := get_ability_defs()
	if slot < 1 or slot > defs.size():
		return 0
	var id: String = defs[slot - 1].get("id", "")
	var uses: int
	match clampi(ability_levels.get(slot, 1), 1, ABILITY_LEVEL_MAX):
		1: uses = ability_data.get_base_uses(id)
		2: uses = ability_data.get_mid_uses(id)
		_: uses = ability_data.get_max_uses(id)
	for effect in passives:
		if effect.get("type", "") == "extra_uses" and int(effect.get("slot", 0)) == slot:
			uses += int(effect.get("amount", 0))
	return uses

# Ali je dani sposobnostni slot odklenjen za to figuro (slot 1 vedno).
func is_slot_unlocked(slot: int) -> bool:
	return slot in unlocked_slots

# ----------------- SKILL TREE PASIVE -----------------

func has_passive(effect_type: String) -> bool:
	return not get_passive(effect_type).is_empty()

# Prvi effect slovar danega tipa ali {}, če ga figura nima.
func get_passive(effect_type: String) -> Dictionary:
	for effect in passives:
		if effect.get("type", "") == effect_type:
			return effect
	return {}

# "flag" pasive - prosti markerji, ki jih berejo skripte figur
# (npr. queen spec_a "blast_clears_snow").
func has_flag(flag_name: String) -> bool:
	for effect in passives:
		if effect.get("type", "") == "flag" and effect.get("flag", "") == flag_name:
			return true
	return false

# Prepiše unlocked_slots/ability_levels/passives iz trajnega stanja po tipu
# figure (PlayerManager izpeljanke iz kupljenih vozlišč drevesa). Samo za
# igralčeve figure - sovražniki in ovire sposobnosti ne uporabljajo in
# obdržijo privzete vrednosti.
func _load_persistent_upgrades():
	if is_enemy or is_obstacle:
		return
	if not is_instance_valid(player_manager):
		return
	unlocked_slots = [1]
	for slot in [2, 3]:
		if player_manager.is_slot_unlocked(strName, slot):
			unlocked_slots.append(slot)
	for slot in [1, 2, 3]:
		ability_levels[slot] = player_manager.get_ability_level(strName, slot)
	passives = player_manager.get_passive_effects(strName)

	# Takojšnje pasive: move_range. Izhajamo iz zajete osnovne vrednosti
	# (glej _base_move_range), ne iz trenutne, da je klic idempotenten.
	if _base_move_range == -1:
		_base_move_range = move_range
	move_range = _base_move_range
	for effect in passives:
		if effect.get("type", "") == "move_range":
			move_range += int(effect.get("amount", 0))

# Napolni ability_uses_remaining iz get_ability_defs(). Kliče se ob vsaki
# (re)registraciji na mreži (placement, King.Heal spawn, test_sandbox).
func reset_ability_uses():
	ability_uses_remaining.clear()
	var defs := get_ability_defs()
	for i in range(defs.size()):
		var slot := i + 1
		ability_uses_remaining[slot] = _ability_uses_max(slot)

# Podatki za battle_ui prikaz (ime/opis/preostale uporabe/zaklenjeno/nivo).
func get_ability_info(slot: int) -> Dictionary:
	var defs := get_ability_defs()
	if slot < 1 or slot > defs.size():
		return {}
	var def: Dictionary = defs[slot - 1]
	var tier := _tier_data(slot)
	return {
		"name": def.get("name", "-"),
		"desc": tier.get("desc", ""),
		"uses_remaining": ability_uses_remaining.get(slot, 0),
		"uses_max": _ability_uses_max(slot),
		"locked": slot >= 2 and not is_slot_unlocked(slot),
		"level": ability_levels.get(slot, 1),
		"level_max": ABILITY_LEVEL_MAX,
	}

# Sledi tarčam, ki jih mora igralec izbrati PO kliku na gumb (glej
# map_behaviour.gd - pending_ability). Prazen seznam pomeni "ni potrebe po
# dodatnem kliku, sposobnost se izvede takoj".
func get_ability_targets(_slot: int) -> Array[Vector2i]:
	return []

# Glavni vstop iz UI (battle_ui.gd) / map_behaviour.gd (za ciljane
# sposobnosti). target je Vector2i za ciljane sposobnosti, sicer null.
func activate_ability(slot: int, target = null) -> bool:
	if is_enemy:
		return false
	# Prekletstvo "stunning_gaze": omamljena figura ne more uporabiti sposobnosti.
	if stunned_turns > 0:
		return false
	if not is_instance_valid(battle_controller) or not battle_controller.can_use_ability():
		return false
	var defs := get_ability_defs()
	if slot < 1 or slot > defs.size():
		return false
	if not is_slot_unlocked(slot):
		return false
	if ability_uses_remaining.get(slot, 0) <= 0:
		return false

	var def: Dictionary = defs[slot - 1]
	var ok: bool = _execute_ability(def.get("id", ""), target)
	if ok:
		ability_uses_remaining[slot] = ability_uses_remaining.get(slot, 0) - 1
	return ok

# Podrazredi povozijo to z "match id:" blokom za svoji 2 sposobnosti. Vrne
# true, če se je sposobnost dejansko izvedla (in naj se torej porabi 1 uporaba).
func _execute_ability(_id: String, _target) -> bool:
	return false

# Queen.Lure: premakni se na polje najbliže kraljici, izmed veljavnih tarč,
# a nikoli na kraljičino lastno polje (ne sme je zajeti, dokler je zvabljena).
func _lured_move() -> Dictionary:
	var queen: BaseCharacter = battle_controller.lure_source
	if not is_instance_valid(queen):
		return {}

	var candidates: Array[Vector2i] = []
	for pos in calculate_valid_targets():
		if pos != queen.grid_pos:
			candidates.append(pos)
	if candidates.is_empty():
		return {}

	var best_move: Vector2i = candidates[0]
	var best_score := INF
	for pos in candidates:
		var score = pos.distance_to(queen.grid_pos)
		if score < best_score:
			best_score = score
			best_move = pos

	var move_type := "CAPTURE" if grid_manager.get_character_at(best_move) else "MOVE"
	return {"move_type": move_type, "target_pos": best_move}

func calculate_best_move() -> Dictionary:
	# Logika samo za sovražnike
	if not is_enemy:
		return {}

	# Queen.Lure: ta figura je zvabljena - povozimo normalno AI logiko in se
	# premaknemo proti kraljici (a je ne moremo zajeti).
	if is_instance_valid(battle_controller) and self in battle_controller.lured_enemies:
		return _lured_move()

	# -------------------------------
	# 1. LINE-OF-SIGHT SPOTTING
	# -------------------------------
	# Uporabimo move_range kot domet vida, da se ne premakne v prvem krogu, ko ga zagleda
	var seen_player = can_see_player(move_range) 

	if seen_player and not has_spotted_player:
		has_spotted_player = true
		last_known_player_pos = seen_player.grid_pos
		last_known_direction = (seen_player.grid_pos - grid_pos).sign()
		# Wake-up turn, no movement (to se bo izvajalo samo, ko prvič zagleda)
		return {} 

	if seen_player:
		last_known_player_pos = seen_player.grid_pos
		last_known_direction = (seen_player.grid_pos - grid_pos).sign()

	# ---------------------------------
	# 2. MOVEMENT OPTIONS
	# ---------------------------------
	var valid_targets = calculate_valid_targets()
	if valid_targets.is_empty():
		return {}

	# Prekletstvo "fey_step": nosilec ne sme zajemati - odstranimo sovražnikova
	# (=igralčeva) zasedena polja iz veljavnih ciljev PREDEN se karkoli spodaj
	# odloči zanje (tudi slepo iskanje/lov spodaj bi sicer lahko "slučajno"
	# pristala na zajemljivem polju - try_move zajame samodejno, če je polje
	# zasedeno z nasprotnikom, ne glede na predlagani move_type).
	if curse and not curse.can_capture():
		valid_targets = valid_targets.filter(func(pos):
			var t = grid_manager.get_character_at(pos)
			return not (t and t.is_enemy != is_enemy))
		if valid_targets.is_empty():
			return {}

	# ---------------------------------
	# 3. SLEPO ISKANJE (BLIND SEEK) - NOV DODATEK
	# ---------------------------------
	if not has_spotted_player:
		const BLIND_SEEK_TARGET_ROW := 7 # Ciljna vrstica (približna sredina bojišča, če je 12 vrstic)
		var best_move: Vector2i = grid_pos
		var blind_seek_min_distance := INF

		# Izberemo potezo, ki sovražnika najbolj približa centru bojišča (navzdol)
		for move_pos in valid_targets:
			var distance_to_center = abs(move_pos.y - BLIND_SEEK_TARGET_ROW)

			if distance_to_center < blind_seek_min_distance:
				blind_seek_min_distance = distance_to_center
				best_move = move_pos
				
		# Če se sploh lahko premakne
		if best_move != grid_pos:
			return {"move_type": "MOVE", "target_pos": best_move}
		else:
			return {} # Ne more se premakniti bližje, ostane na mestu
			
	# NASLEDNJI KORAKI (4-7) SE ZGODIJO SAMO, ČE JE 'has_spotted_player' TRUE!
	
	# ---------------------------------
	# 4. CHECK FOR CURRENTLY VISIBLE PLAYER
	# ---------------------------------
	var closest_player: BaseCharacter = null
	var min_distance := INF

	for nearby_char in grid_manager.get_all_characters():
		if not is_instance_valid(nearby_char):
			continue

		if not nearby_char is BaseCharacter:
			continue

		# Item "smoke_screen": skrita figura se ne šteje kot "closest_player" za
		# gonjo (heuristika HARD/NORMAL) - minimax (IMPOSSIBLE) tega ne pozna,
		# glej opombo pri is_hidden deklaraciji.
		if nearby_char.is_enemy == is_enemy or nearby_char.is_obstacle or nearby_char.is_hidden:
			continue

		var dist = grid_pos.distance_to(nearby_char.grid_pos)
		if dist <= move_range and dist < min_distance:
			min_distance = dist
			closest_player = nearby_char

	# Update tracking if visible this turn
	if closest_player:
		last_known_player_pos = closest_player.grid_pos
		last_known_direction = (closest_player.grid_pos - grid_pos).sign()

	# ---------------------------------
	# 5. PANIC CHECK
	# ---------------------------------
	is_panicking = false
	if closest_player and min_distance <= panic_distance:
		is_panicking = true

	# ---------------------------------
	# 6-7. CAPTURE + CHASE, delegated to the tier-specific decision strategy
	# (SettingsManager.ai_difficulty, GameParameters/ai_difficulty.json) - see
	# Scripts/AI/enemy_ai_strategy.gd and plans/AI_DIFFICULTY_PLAN.md §2.3. Capture
	# priority still always wins ("captures stay aggressive" - Miha's words); the
	# strategy just decides HOW aggressively/carefully to chase/capture/search per tier.
	# ---------------------------------
	var capture_candidates: Array[Vector2i] = []
	for pos in valid_targets:
		var target_char = grid_manager.get_character_at(pos)
		if target_char and target_char.is_obstacle:
			continue # skip any obstacle entirely
		if target_char and target_char.is_enemy != is_enemy and not target_char.is_hidden:
			capture_candidates.append(pos)

	var strategy = ai_strategy_data.get_strategy(settings_manager.ai_difficulty)
	var action: Dictionary = strategy.choose_action(self, {
		"valid_targets": valid_targets,
		"capture_candidates": capture_candidates,
		"last_known_player_pos": last_known_player_pos,
	})
	if action.is_empty():
		return {}

	# ---------------------------------
	# 8. PANIC RANDOMNESS - stays a base_character-level trait, NOT part of the
	# difficulty ladder (every tier's characters panic the same way). Matches the
	# pre-refactor invariant: only ever overrides a MOVE, never a CAPTURE.
	# ---------------------------------
	if is_panicking and action.get("move_type") != "CAPTURE" and randf() < panic_randomness:
		action = {
			"move_type": "MOVE",
			"target_pos": valid_targets[randi() % valid_targets.size()]
		}

	return action
