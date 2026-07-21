# res://Scripts/Player/PlayerManager.gd
extends Node

# Sproži se ob vsaki spremembi ekip (smrt figure ipd.), da se UI lahko osveži.
signal party_changed

# Sproži se ob vsaki spremembi števila itemov ALI nadgradenj figur
# (add_upgrade_items / try_buy_node).
signal items_changed

# Party Management
var default_friends: Array[String] = ["friendly_pawn", "friendly_pawn", "friendly_pawn"]
var default_enemies: Array[String] = ["enemy_pawn", "enemy_pawn", "enemy_pawn"]
var friendly_party: Array[String]
var enemy_party: Array[String]

# Figure, ki jih je igralec nabral čez omejitev max_party_size - niso
# izgubljene, samo čakajo. Zamenjava rezerva <-> aktivna ekipa se dogaja na
# počivališču prek Party gumba (UI za to pride kasneje - glej
# CampfirePartyPanel.gd).
var reserve_party: Array[String]

var active_enemies: Array[String]

var active_party: Array[String]

# Zavezniki, ki so padli v trenutni bitki. Ponastavi se v resetActives()
# (smrt zaenkrat NI trajna med bitkami - trajnost pride z revive itemom).
var dead_party: Array[String]

# Item counts (revive_items je še vedno samo prikaz - revive sistem pride
# kasneje, skupaj s trajno smrtjo figur med bitkami).
var upgrade_items: int = 0
var revive_items: int = 0

# Inventar shop itemov: item id ("extra_move") -> količina. Ne prenaša se
# med runi (glej reset v setStarting()) - enako pravilo kot upgrade_items.
var owned_items: Dictionary = {}

# Nagrade v upgrade itemih (glej BattleController.check_battle_end in
# MapController._handle_event za item sobo).
const UPGRADE_ITEMS_PER_WIN := 1
const UPGRADE_ITEMS_PER_BOSS_WIN := 3
const UPGRADE_ITEMS_PER_ITEM_ROOM := 2

# Trajne nadgradnje PO TIPU figure (velja za vse figure istega tipa - roster
# je seznam imen brez identitete posamezne figure, glej friendly_party).
# strName ("pawn" ipd.) -> {"nodes": Array kupljenih node id-jev iz
# GameParameters/skill_trees.json}. Figure ob registraciji na mrežo preberejo izpeljano
# stanje (glej get_ability_level / is_slot_unlocked / get_passive_effects) -
# poraba itemov je SAMO v try_buy_node.
var piece_upgrades: Dictionary = {}

# Koliko premikov/zajetij in koliko sposobnosti lahko igralec izvede v ENI
# potezi, preden mora ročno pritisniti END TURN (glej BattleController.gd).
# Ločena proračuna - deljen proračun je dovolil premakniti 3 različne figure
# v eni potezi, kar je bilo preveč močno. Var, ne const - meta-progression
# (upgrade) bo to lahko kasneje povečal.
var moves_per_turn: int = 1
var abilities_per_turn: int = 3


# Največ figur v AKTIVNI ekipi (vrstica "YOUR PIECES" v bitki, glej
# battle_ui.gd). Čez to mejo se figure še vedno nabirajo (glej
# reserve_party) - samo v bitko jih ni mogoče postaviti, dokler jih igralec
# ne zamenja z aktivno ekipo na počivališču. V bitko jih lahko postavi
# največ MAX_PLACED (glej battle_ui.gd).
var max_party_size = 10
var snowCount = 6

# NOVO: Sledenje napredku igralca na mapi (0 do 14)
var current_map_floor: int = 0

# NOVO: Sledenje napredku igralca med 3 zaporednimi mapami (0, 1, 2)
var current_map_tier: int = 0
# NOVO: Način igre za trenutni run ("classic" ali "infinite"), nastavi setStarting()
var game_mode: String = "classic"
# NOVO: Ali je soba, ki je sprožila trenutno bitko, boss soba te mape
var is_boss_floor: bool = false
# NOVO: Ali je soba, ki je sprožila trenutno bitko, mini-boss soba te mape
# (glej MapGenerator.mini_boss_floor/mini_boss_type - queen na tier 1-2)
var is_mini_boss_floor: bool = false
# NOVO: Ime figure, dodane v friendly_party/enemy_party TO bitko (za post-battle summary
# "+" badge). Nastavi/počisti MapController._handle_event(), največ ena figura na bitko.
var new_friendly_piece: String = ""
var new_enemy_piece: String = ""

func _ready():
	print("PlayerManager naložen. Party size: %d" % [active_party.size()])

# ----------------- PARTY MANAGEMENT (Aktivna ekipa) -----------------

func add_to_friendly_party(character) -> bool:
	print("char name ", character)
	if friendly_party.size() < max_party_size:
		friendly_party.append(character)
		print("PlayerManager: Dodana figura v aktivno ekipo. Nova velikost: %d" % friendly_party.size())
		return true
	else:
		reserve_party.append(character)
		print("PlayerManager: Aktivna ekipa polna (%d/%d) - figura shranjena v rezervo. Rezerva: %d" % [friendly_party.size(), max_party_size, reserve_party.size()])
		return false

# ----------------- REZERVA <-> AKTIVNA EKIPA (počivališče, CampfirePartyPanel) -----------------

# Prestavi figuro iz aktivne ekipe (indeks v friendly_party) nazaj v rezervo.
# Zavrne, če bi aktivna ekipa ostala prazna - v bitko moraš iti z vsaj eno figuro.
func move_active_to_reserve(index: int) -> bool:
	if index < 0 or index >= friendly_party.size():
		return false
	if friendly_party.size() <= 1:
		return false
	var piece_name: String = friendly_party[index]
	friendly_party.remove_at(index)
	reserve_party.append(piece_name)
	party_changed.emit()
	return true

# Prestavi figuro iz rezerve (indeks v reserve_party) v aktivno ekipo, če je prostor.
func move_reserve_to_active(index: int) -> bool:
	if index < 0 or index >= reserve_party.size():
		return false
	if friendly_party.size() >= max_party_size:
		return false
	var piece_name: String = reserve_party[index]
	reserve_party.remove_at(index)
	friendly_party.append(piece_name)
	party_changed.emit()
	return true

# ----------------- UPGRADE ITEMI IN NADGRADNJE FIGUR -----------------

# Interno: ŽIV seznam kupljenih node id-jev za dani tip figure (po potrebi
# ustvari prazen vnos). Spreminja naj ga samo try_buy_node/debug_max_all_upgrades.
func _get_owned_nodes(piece_type: String) -> Array:
	if not piece_upgrades.has(piece_type):
		piece_upgrades[piece_type] = {"nodes": []}
	return piece_upgrades[piece_type]["nodes"]

# Def-i kupljenih vozlišč (preskoči id-je, ki jih v GameParameters/skill_trees.json ni).
func _owned_node_defs(piece_type: String) -> Array:
	var defs: Array = []
	for node_id in _get_owned_nodes(piece_type):
		var node_def: Dictionary = SkillTreeData.get_node_def(piece_type, node_id)
		if not node_def.is_empty():
			defs.append(node_def)
	return defs

func add_upgrade_items(amount: int):
	upgrade_items += amount
	print("PlayerManager: +%d upgrade item(ov). Skupaj: %d" % [amount, upgrade_items])
	items_changed.emit()

func has_tree_node(piece_type: String, node_id: String) -> bool:
	return _get_owned_nodes(piece_type).has(node_id)

# false, če: je vozlišče že kupljeno, manjka kakšen "requires", je kupljen
# kakšen "excludes" (izbrana druga specializacija), ali ni dovolj itemov.
func can_buy_node(piece_type: String, node_def: Dictionary) -> bool:
	var node_id: String = node_def.get("id", "")
	if node_id == "" or has_tree_node(piece_type, node_id):
		return false
	for req in node_def.get("requires", []):
		if not has_tree_node(piece_type, req):
			return false
	for excl in node_def.get("excludes", []):
		if has_tree_node(piece_type, excl):
			return false
	return upgrade_items >= int(node_def.get("cost", 0))

# Kupi vozlišče drevesa za CEL tip figure. Edino mesto porabe upgrade itemov
# za nadgradnje figur.
func try_buy_node(piece_type: String, node_id: String) -> bool:
	var node_def: Dictionary = SkillTreeData.get_node_def(piece_type, node_id)
	if node_def.is_empty() or not can_buy_node(piece_type, node_def):
		return false
	upgrade_items -= int(node_def.get("cost", 0))
	_get_owned_nodes(piece_type).append(node_id)
	items_changed.emit()
	return true

# ----------------- IZPELJANO STANJE DREVESA (bere BaseCharacter) -----------------

# 1 + število kupljenih {"type":"ability_level","slot":slot} vozlišč.
func get_ability_level(piece_type: String, slot: int) -> int:
	var level := 1
	for node_def in _owned_node_defs(piece_type):
		var effect: Dictionary = node_def.get("effect", {})
		if effect.get("type", "") == "ability_level" and int(effect.get("slot", 0)) == slot:
			level += 1
	return level

# Slot 1 je vedno odklenjen; slota 2/3 odklene {"type":"ability_unlock"} vozlišče.
func is_slot_unlocked(piece_type: String, slot: int) -> bool:
	if slot <= 1:
		return true
	for node_def in _owned_node_defs(piece_type):
		var effect: Dictionary = node_def.get("effect", {})
		if effect.get("type", "") == "ability_unlock" and int(effect.get("slot", 0)) == slot:
			return true
	return false

# Effect slovarji vseh kupljenih PASIVNIH vozlišč (vse razen
# ability_level/ability_unlock - glej vocabulary v SKILL_TREE_PLAN.md §2.1).
func get_passive_effects(piece_type: String) -> Array:
	var effects: Array = []
	for node_def in _owned_node_defs(piece_type):
		var effect: Dictionary = node_def.get("effect", {})
		var effect_type: String = effect.get("type", "")
		if effect_type != "" and effect_type != "ability_level" and effect_type != "ability_unlock":
			effects.append(effect)
	return effects

# SAMO za teste in dev sandbox scene (test_sandbox, piece_test, smoke testi):
# vsem tipom figur podari vsa vozlišča drevesa razen spec_b (specializaciji
# se izključujeta - izbrana je spec_a), brez porabe itemov.
func debug_max_all_upgrades():
	for piece_type in ["pawn", "knight", "rook", "bishop", "queen", "king"]:
		var owned: Array = []
		for node_def in SkillTreeData.get_tree_nodes(piece_type):
			var node_id: String = node_def.get("id", "")
			if node_id != "" and node_id != "spec_b":
				owned.append(node_id)
		piece_upgrades[piece_type] = {"nodes": owned}
	items_changed.emit()

# ----------------- SMRT IN OŽIVITEV (Revive) -----------------

# Registrira podatke o padli figuri (Klic iz BaseCharacter.die())
func register_dead_character(character):
	for item in active_party:
		if character == item:
			active_party.erase(character)
			dead_party.append(character)
			break
	for item in active_enemies:
		if character == item:
			active_enemies.erase(character)
			break
	print(friendly_party)
	print(active_party)
	print(enemy_party)
	print(active_enemies)
	party_changed.emit()
			
# ----------------- SPOSOBNOSTI: King.Heal / King.Cleanse -----------------

# King.Heal: prestavi ime iz dead_party nazaj v active_party (figura se je
# ravnokar znova pojavila na plošči - glej King._do_heal()).
func revive_character(character_name: String) -> bool:
	var idx = dead_party.find(character_name)
	if idx == -1:
		return false
	dead_party.remove_at(idx)
	active_party.append(character_name)
	party_changed.emit()
	return true

# King.Cleanse: sovražnik zamenja stran za preostanek TE bitke. enemy_name je
# oblike "enemy_<strName>", ally_name "friendly_<strName>" - ne dotika se
# trajnega rosterja (friendly_party/enemy_party).
func convert_enemy_to_ally(enemy_name: String, ally_name: String) -> bool:
	var idx = active_enemies.find(enemy_name)
	if idx == -1:
		return false
	active_enemies.remove_at(idx)
	active_party.append(ally_name)
	party_changed.emit()
	return true

# King.Cleanse spremljava: ko obrnjena figura umre, jo samo odstranimo iz
# active_party - NE gre skozi register_dead_character(), ker ne ustreza
# nobenemu vnosu v trajnem friendly_party rosterju.
func remove_converted_ally(character_name: String):
	var idx = active_party.find(character_name)
	if idx != -1:
		active_party.remove_at(idx)
	party_changed.emit()

# Item "bloodhounds": doda začasnega zaveznika (npr. "friendly_wolf") v
# active_party za TO bitko - ni del trajnega rosterja (friendly_party), zato
# ne gre skozi noben nakup/prodajo. Smrt take figure mora iti skozi
# remove_converted_ally() (glej BaseCharacter.die() is_converted_ally veja),
# NE register_dead_character(), da ne pusti fantomskega dead_party vnosa.
func add_temporary_ally(character_name: String):
	active_party.append(character_name)
	party_changed.emit()

func add_to_enemy_party(character):
	# Namerno: vojska sovražnikov RASTE, ko igralec napreduje globlje v isto mapo
	# (vsaka bitka doda k prejšnjim, ne le k default_enemies). Ponastavi se samo
	# ob prehodu na novo mapo (glej GameFlow.advance_map_tier()) - ne ob vsaki bitki.
	enemy_party.append(character)

func resetActives():
	active_enemies = enemy_party.duplicate()
	active_party = friendly_party.duplicate()
	dead_party.clear()
	party_changed.emit()
	
func setStarting(mode: String = "classic") -> void:
	game_mode = mode
	friendly_party = default_friends.duplicate()
	if MetaProgress.tutorial_reward_granted:
		# Trajna nagrada za dokončan (ne skip-an) tutorial map (glej
		# plans/TUTORIAL_MAP_PLAN.md M5) - eno mesto za VSAK nov run, saj
		# tako Classic kot Infinite kličeta samo setStarting().
		friendly_party.append("friendly_pawn")
		friendly_party.append("friendly_rook")
	enemy_party = default_enemies.duplicate()
	# Nov run: nadgradnje in itemi se ne prenašajo iz prejšnjega runa.
	piece_upgrades = {}
	upgrade_items = 0
	owned_items = {}
	items_changed.emit()

func addSnow():
	snowCount += 2

# ----------------- SHOP: ITEM INVENTAR IN NAKUP/PRODAJA -----------------

func add_item(id: String, amount: int = 1):
	owned_items[id] = owned_items.get(id, 0) + amount
	items_changed.emit()

# Vrne false, če itema ni na voljo. Odšteje 1 in počisti ključ pri 0.
func remove_item(id: String) -> bool:
	if owned_items.get(id, 0) <= 0:
		return false
	owned_items[id] -= 1
	if owned_items[id] <= 0:
		owned_items.erase(id)
	items_changed.emit()
	return true

func get_item_count(id: String) -> int:
	return owned_items.get(id, 0)

# Pasivni itemi: aktivni, dokler je v inventarju vsaj 1 kos.
func has_passive(id: String) -> bool:
	return owned_items.get(id, 0) > 0 and ItemData.get_kind(id) == "passive"

# Kupi 1x item po ceni iz ItemData. Zavrne, če ni dovolj upgrade_items.
func try_buy_item(id: String) -> bool:
	var cost: int = ItemData.get_buy_cost(id)
	if upgrade_items < cost:
		return false
	upgrade_items -= cost
	add_item(id, 1)
	return true

# Proda 1x item iz inventarja nazaj za upgrade_items po ItemData ceni.
func try_sell_item(id: String) -> bool:
	if not remove_item(id):
		return false
	upgrade_items += ItemData.get_sell_value(id)
	items_changed.emit()
	return true

# Proda figuro iz aktivne ekipe. Zavrne, če bi aktivna ekipa ostala prazna
# (ista zaščita kot move_active_to_reserve).
func try_sell_active_piece(index: int) -> bool:
	if index < 0 or index >= friendly_party.size():
		return false
	if friendly_party.size() <= 1:
		return false
	var roster_name: String = friendly_party[index]
	friendly_party.remove_at(index)
	upgrade_items += ItemData.get_piece_sell_value(roster_name)
	party_changed.emit()
	items_changed.emit()
	return true

func try_sell_reserve_piece(index: int) -> bool:
	if index < 0 or index >= reserve_party.size():
		return false
	var roster_name: String = reserve_party[index]
	reserve_party.remove_at(index)
	upgrade_items += ItemData.get_piece_sell_value(roster_name)
	party_changed.emit()
	items_changed.emit()
	return true

# Funkcija za posodobitev trenutnega nadstropja (kliče se, ko igralec premaga sobo)
# Posodobi napredek igralca. new_floor je INDEKS NADSTROPJA sobe (grid_position.x).
# Vrednost samo narašča - nikoli ne pada.
func set_current_floor(new_floor: int):
	if new_floor > current_map_floor:
		current_map_floor = new_floor
		print("PlayerManager: Igralec je sedaj na nadstropju %d." % current_map_floor)

func reset_floor_number():
	current_map_floor = 0

func activeGone() -> bool:
	if active_party.is_empty():
		print("active gone")
		return true
	return false
	
func enemyGone() -> bool:
	if active_enemies.is_empty():
		print("enemy gone")
		return true
	return false
