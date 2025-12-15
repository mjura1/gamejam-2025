# res://Scripts/PlayerManager.gd
extends Node

# Party Management
var active_party: Array[String] = ["friendly_pawn", "friendly_pawn", "friendly_pawn"] # ČE JE TO PRAZNO JE IGRE KONEC
var enemy_party: Array[String] = ["enemy_pawn", "enemy_pawn", "enemy_pawn"]
var active_enemies: Array[String]

var max_party_size = 32
var snowCount = 6

func _ready():
	print("PlayerManager naložen. Party size: %d" % [active_party.size()])

# ----------------- PARTY MANAGEMENT (Aktivna ekipa) -----------------

func add_to_active_party(character):
	if active_party.size() < max_party_size:
		print("char name ", character)
		active_party.append(character)
		print("PlayerManager: Dodana figura. Nova velikost ekipe: %d" % active_party.size())

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
	print(active_party)
	print(enemy_party)
	print(active_enemies)
			
func add_to_enemy_party(character):
	enemy_party.append(character)

func resetActiveEnemies():
	active_enemies = enemy_party.duplicate()

func addSnow():
	snowCount += 2

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
