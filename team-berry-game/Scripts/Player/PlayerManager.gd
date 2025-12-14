# res://Scripts/PlayerManager.gd
extends Node

# Inventar
var food: int = 5
var leather: int = 0

# Party Management
var active_party: Array[String] = [] # ČE JE TO PRAZNO JE IGRE KONEC
var enemy_party: Array[String] = []

var max_party_size = 32
var snowCount = 0

func _ready():
	print("PlayerManager naložen. Party size: %d" % [active_party.size()])

# ----------------- PARTY MANAGEMENT (Aktivna ekipa) -----------------

func add_to_active_party(character):
	if active_party.size() < max_party_size:
		active_party.append(character)
		print("PlayerManager: Dodana figura. Nova velikost ekipe: %d" % active_party.size())

# ----------------- SMRT IN OŽIVITEV (Revive) -----------------

# Registrira podatke o padli figuri (Klic iz BaseCharacter.die())
func register_dead_ally(character):
	for item in active_party:
		if character == item:
			active_party.erase(character)
			
func add_to_enemy_party(character):
	enemy_party.append(character)
