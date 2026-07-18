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
# Ali je 2. sposobnostni slot odklenjen. Trajno stanje živi v
# PlayerManager.piece_upgrades (po TIPU figure) - figura ga prebere ob
# registraciji na mrežo (glej _load_persistent_upgrades).
@export var ability2_unlocked: bool = false

# slot (1|2) -> trenutni nivo TE sposobnosti (1=base, 2=mid, ABILITY_LEVEL_MAX=upgraded).
# Vsak slot se dviguje NEODVISNO (glej AbilityData.get_level_up_cost) - ločeno
# od ability2_unlocked, ki samo odklene sam slot 2 (glej get_unlock_cost).
# Tudi to je samo bitki-lokalna kopija stanja iz PlayerManager.piece_upgrades.
const ABILITY_LEVEL_MAX := 3
const ABILITY_TIER_KEYS := ["base", "mid", "upgraded"]
var ability_levels: Dictionary = {1: 1, 2: 1}

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

# Prekletstvo sovražnika (od nadstropja 2 naprej, glej battle.gd._maybe_curse) -
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

	# 4. Preberemo trajne nadgradnje tipa (nivoji + odklep slota 2) in
	# napolnimo sposobnosti (velja tudi za figure, ki se pojavijo sredi
	# bitke - npr. King.Heal - in za test_sandbox figure).
	_load_persistent_upgrades()
	reset_ability_uses()

	# Za debug:
	print("%s: Uspešno registriran in inicializiran na mreži %s." % [self.name, str(grid_pos)])

# Dodeli prekletstvo tej figuri (glej battle.gd._maybe_curse) in doda njen
# vizualni marker (delci/pulzirajoč tint ali statična oblika, glej
# Scripts/Curses/curse_marker.gd - reduced_motion preklop). "new_curse"
# NAMERNO netipiziran (glej opombo pri "var curse" zgoraj). Iz istega razloga
# CurseMarker nalagamo z load() namesto z golim class_name identifikatorjem -
# ta bi enako prisilil zgodnji compile base_curse.gd/CurseData.
func apply_curse(new_curse) -> void:
	curse = new_curse
	var marker = load("res://Scripts/Curses/curse_marker.gd").new()
	marker.name = "CurseMarker"
	add_child(marker)
	marker.setup(self, curse)


# King.Cleanse: obrnjena figura NE obdrži prekletstva kot zaveznica - eno
# mesto resnice za "odstrani prekletstvo" (počisti stanje + vizualni marker/
# tint), da ga ni treba podvajati na vsakem klicnem mestu.
func clear_curse() -> void:
	curse = null
	var marker := get_node_or_null("CurseMarker")
	if marker:
		# remove_child() PRED queue_free(): queue_free() sam po sebi šele
		# odloženo (konec sličice) odstrani vozlišče - brez remove_child()
		# bi get_node_or_null("CurseMarker") še kratek čas vrnil staro
		# vozlišče, čeprav je "logično" že počiščeno.
		remove_child(marker)
		marker.queue_free()
	modulate = Color.WHITE


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

func calculate_valid_targets() -> Array[Vector2i]:
	var targets: Array[Vector2i] = []

	# Prekletstvo "stunning_gaze": omamljena figura se ne more premakniti
	# (traja natanko igralčevo naslednjo potezo, glej BattleController.end_player_turn).
	if stunned_turns > 0:
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
	
	# ===============================================
	# FOG OF WAR (NOVO)
	# ===============================================
	
	# Posodobitev megle okoli nove pozicije, samo za zaveznike!
	if not is_enemy and is_instance_valid(grid_manager):
		
		var positions_to_reveal: Array[Vector2i] = []
		
		# Vidni doseg: 3x3 območje okoli figure (x in y od -1 do 1)
		for x in range(-1, 2):
			for y in range(-1, 2):
				positions_to_reveal.append(grid_pos + Vector2i(x, y))
				
		# Naročimo GridManagerju, da odstrani meglo na teh poljih
		grid_manager.reveal_area(positions_to_reveal)

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
# (base_uses/max_uses) NI tu - to živi v Data/abilities.json (glej AbilityData
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

# Vrne max. število uporab za dani slot iz AbilityData (Data/abilities.json),
# glede na trenutni nivo TEGA slota (ability_levels[slot]).
func _ability_uses_max(slot: int) -> int:
	var defs := get_ability_defs()
	if slot < 1 or slot > defs.size():
		return 0
	var id: String = defs[slot - 1].get("id", "")
	match clampi(ability_levels.get(slot, 1), 1, ABILITY_LEVEL_MAX):
		1: return ability_data.get_base_uses(id)
		2: return ability_data.get_mid_uses(id)
		_: return ability_data.get_max_uses(id)

# Prepiše ability2_unlocked/ability_levels iz trajnega stanja po tipu figure
# (PlayerManager.piece_upgrades). Samo za igralčeve figure - sovražniki in
# ovire sposobnosti ne uporabljajo in obdržijo privzete vrednosti.
func _load_persistent_upgrades():
	if is_enemy or is_obstacle:
		return
	if not is_instance_valid(player_manager):
		return
	var up: Dictionary = player_manager.get_piece_upgrades(strName)
	ability2_unlocked = up["slot2_unlocked"]
	ability_levels = {1: up["levels"][1], 2: up["levels"][2]}

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
	var id: String = def.get("id", "")
	return {
		"name": def.get("name", "-"),
		"desc": tier.get("desc", ""),
		"uses_remaining": ability_uses_remaining.get(slot, 0),
		"uses_max": _ability_uses_max(slot),
		"locked": slot == 2 and not ability2_unlocked,
		"level": ability_levels.get(slot, 1),
		"level_max": ABILITY_LEVEL_MAX,
		"unlock_cost": ability_data.get_unlock_cost(id),
		"level_up_cost": ability_data.get_level_up_cost(id),
	}

# Sledi tarčam, ki jih mora igralec izbrati PO kliku na gumb (glej
# map_behaviour.gd - pending_ability). Prazen seznam pomeni "ni potrebe po
# dodatnem kliku, sposobnost se izvede takoj".
func get_ability_targets(slot: int) -> Array[Vector2i]:
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
	if slot == 2 and not ability2_unlocked:
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
	
	# ---------------------------------
	# 3. SLEPO ISKANJE (BLIND SEEK) - NOV DODATEK
	# ---------------------------------
	if not has_spotted_player:
		const BLIND_SEEK_TARGET_ROW := 7 # Ciljna vrstica (približna sredina bojišča, če je 12 vrstic)
		var best_move: Vector2i = grid_pos
		var min_distance := INF

		# Izberemo potezo, ki sovražnika najbolj približa centru bojišča (navzdol)
		for move_pos in valid_targets:
			var distance_to_center = abs(move_pos.y - BLIND_SEEK_TARGET_ROW)

			if distance_to_center < min_distance:
				min_distance = distance_to_center
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

		if nearby_char.is_enemy == is_enemy or nearby_char.is_obstacle:
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
	# 6. CAPTURE HAS ABSOLUTE PRIORITY - VALUE-AWARE (vedno aktivno, ni
	# gated na težavnost - Miha: "captures stay aggressive, that's the
	# fun"). Zbere VSE zajemljive tarče na tej potezi in izbere najvrednejšo
	# (CurseData.get_piece_value, Data/ai_config.json) namesto prve najdene.
	# ---------------------------------
	var capture_candidates: Array[Vector2i] = []
	for pos in valid_targets:
		var target_char = grid_manager.get_character_at(pos)
		if target_char and target_char.is_obstacle:
			continue # skip any obstacle entirely
		if target_char and target_char.is_enemy != is_enemy:
			capture_candidates.append(pos)

	if not capture_candidates.is_empty():
		var best_capture: Vector2i = capture_candidates[0]
		var best_value := -1
		for pos in capture_candidates:
			var target_char = grid_manager.get_character_at(pos)
			var value: int = curse_data.get_piece_value(target_char.strName)
			if value > best_value:
				best_value = value
				best_capture = pos
		return {
			"move_type": "CAPTURE",
			"target_pos": best_capture
		}


	# ---------------------------------
	# 7. NORMAL CHASE (TOWARD LAST SEEN) - z difficulty-gated "danger
	# avoidance": z verjetnostjo danger_avoid_prob[difficulty] (EASY 0% /
	# NORMAL 50% / HARD 100%, Data/ai_config.json) med enako dobrimi
	# kandidati raje izbere polje, ki ga NOBENA zavezniška figura ne bi
	# mogla zajeti naslednjo potezo. Če so VSI kandidati nevarni, se vrne
	# na navadno najboljšo potezo (nikoli se ne "paralizira"). Namerno se
	# NE uporablja pri zajetju zgoraj - zajetja ostanejo agresivna.
	# ---------------------------------
	var best_move: Vector2i = valid_targets[0]
	var best_score := INF

	for pos in valid_targets:
		var score = pos.distance_to(last_known_player_pos)
		if score < best_score:
			best_score = score
			best_move = pos

	var avoid_prob: float = curse_data.get_ai_param(settings_manager.difficulty, "danger_avoid_prob", 0.0)
	if avoid_prob > 0.0 and randf() < avoid_prob:
		var danger_tiles: Array[Vector2i] = grid_manager.tiles_reachable_by(false)
		var safe_move: Vector2i = best_move
		var safe_score := INF
		var found_safe := false
		for pos in valid_targets:
			if pos in danger_tiles:
				continue
			var score = pos.distance_to(last_known_player_pos)
			if score < safe_score:
				safe_score = score
				safe_move = pos
				found_safe = true
		if found_safe:
			best_move = safe_move

	# ---------------------------------
	# 8. PANIC RANDOMNESS
	# ---------------------------------
	if is_panicking and randf() < panic_randomness:
		best_move = valid_targets[randi() % valid_targets.size()]

	return {
		"move_type": "MOVE",
		"target_pos": best_move
	}
