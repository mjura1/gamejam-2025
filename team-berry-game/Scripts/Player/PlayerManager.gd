# res://Scripts/PlayerManager.gd
extends Node

# Party Management
var friendly_party: Array[String] = ["friendly_king", "friendly_pawn", "friendly_pawn"] # ČE JE TO PRAZNO JE IGRE KONEC
var enemy_party: Array[String] = ["enemy_king", "enemy_pawn", "enemy_pawn"]

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

func addSnow():
	snowCount += 2

# Funkcija za posodobitev trenutnega nadstropja (kliče se, ko igralec premaga sobo)
func set_current_floor(new_floor: int):
	# Logika, ki preprečuje, da bi se current_map_floor zmanjšal
	if new_floor > 10:
		current_map_floor = 10
		
	if new_floor > current_map_floor:
		current_map_floor = current_map_floor + 1
		print("PlayerManager: Igralec je sedaj na nadstropju %d." % current_map_floor)
	else:
		# Če je novo nadstropje nižje ali enako, ohrani najvišjo vrednost
		current_map_floor = current_map_floor + 1
		print("PlayerManager: Ohranjeno nadstropje: %d (novo nadstropje je bilo %d)." % [current_map_floor, new_floor])


func activeGone() -> bool:
	if active_party.is_empty():
		return true
		print("active gone")
	return false
	
func enemyGone() -> bool:
	if active_enemies.is_empty():
		print("enemy gone")
		return true
	return false
