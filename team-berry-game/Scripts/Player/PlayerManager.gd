# res://Scripts/Player/PlayerManager.gd
extends Node

# Sproži se ob vsaki spremembi ekip (smrt figure ipd.), da se UI lahko osveži.
signal party_changed

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

# Item counts (samo prikaz v battle UI - item sistem pride kasneje)
var upgrade_items: int = 0
var revive_items: int = 0


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
# NOVO: Ali je soba, ki je sprožila trenutno bitko, boss soba te mape
var is_boss_floor: bool = false

func _ready():
	print("PlayerManager naložen. Party size: %d" % [active_party.size()])

# ----------------- PARTY MANAGEMENT (Aktivna ekipa) -----------------

func add_to_friendly_party(character):
	print("char name ", character)
	if friendly_party.size() < max_party_size:
		friendly_party.append(character)
		print("PlayerManager: Dodana figura v aktivno ekipo. Nova velikost: %d" % friendly_party.size())
	else:
		reserve_party.append(character)
		print("PlayerManager: Aktivna ekipa polna (%d/%d) - figura shranjena v rezervo. Rezerva: %d" % [friendly_party.size(), max_party_size, reserve_party.size()])

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
	
func setStarting() -> void:
	friendly_party = default_friends.duplicate()
	enemy_party = default_enemies.duplicate()

func addSnow():
	snowCount += 2

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
