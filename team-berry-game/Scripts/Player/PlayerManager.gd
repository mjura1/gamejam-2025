# res://Scripts/Player/PlayerManager.gd
extends Node

# Sproži se ob vsaki spremembi ekip (smrt figure ipd.), da se UI lahko osveži.
signal party_changed

# Party Management
var default_friends: Array[String] = ["friendly_pawn", "friendly_pawn", "friendly_pawn"]
var default_enemies: Array[String] = ["enemy_pawn", "enemy_pawn", "enemy_pawn"]
var friendly_party: Array[String]
var enemy_party: Array[String]

var active_enemies: Array[String]

var active_party: Array[String]

# Zavezniki, ki so padli v trenutni bitki. Ponastavi se v resetActives()
# (smrt zaenkrat NI trajna med bitkami - trajnost pride z revive itemom).
var dead_party: Array[String]

# Item counts (samo prikaz v battle UI - item sistem pride kasneje)
var upgrade_items: int = 0
var revive_items: int = 0


# Največ figur, ki jih igralec sploh lahko ima (vrstica "YOUR PIECES").
# V bitko jih lahko postavi največ MAX_PLACED (glej battle_ui.gd).
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
	if friendly_party.size() < max_party_size:
		print("char name ", character)
		friendly_party.append(character)
		print("PlayerManager: Dodana figura. Nova velikost ekipe: %d" % friendly_party.size())

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
