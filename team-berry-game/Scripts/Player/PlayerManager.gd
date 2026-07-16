# res://Scripts/PlayerManager.gd
extends Node

# Party Management
var default_friends: Array[String] = ["friendly_pawn", "friendly_pawn", "friendly_pawn"]
var default_enemies: Array[String] = ["enemy_pawn", "enemy_pawn", "enemy_pawn"]
var friendly_party: Array[String]
var enemy_party: Array[String]

var active_enemies: Array[String]

var active_party: Array[String]


var max_party_size = 32
var snowCount = 6

# NOVO: Sledenje napredku igralca na mapi (0 do 14)
var current_map_floor: int = 0 

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
			break
	for item in active_enemies:
		if character == item:
			active_enemies.erase(character)
			break
	print(friendly_party)
	print(active_party)
	print(enemy_party)
	print(active_enemies)
			
func add_to_enemy_party(character):
	enemy_party.append(character)

func resetActives():
	active_enemies = enemy_party.duplicate()
	active_party = friendly_party.duplicate()
	
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
