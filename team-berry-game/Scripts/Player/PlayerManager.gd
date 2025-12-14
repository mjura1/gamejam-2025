# res://Scripts/PlayerManager.gd
extends Node

# Inventar
var food: int = 5
var leather: int = 0

# Party Management
var active_party: Array = [] # Trenutno aktivne figure v boju (vozlišča BaseCharacter)
var dead_party: Array = []   # Podatki o figurah, ki so padle (za Campfire/Revive)
var enemy_party: Array = []
var character_roster: Array = [
	# To je seznam VSEH figur, ki jih igralec poseduje in so na voljo.
	# Uporablja se za inicializacijo bitke in za Campfire po oživitvi.
	{"name": "Bishop", "revive_cost": 1, "scene_path": "res://Scenes/Characters/Bishop.tscn"},
]
const max_party_size: int = 4

func _ready():
	print("PlayerManager naložen. Hrana: %d, Party size: %d" % [food, active_party.size()])

# ----------------- INVENTORY -----------------

func use_food(amount: int) -> bool:
	if food >= amount:
		food -= amount
		return true
	return false

# ----------------- PARTY MANAGEMENT (Aktivna ekipa) -----------------

func add_to_active_party(character):
	if active_party.size() < max_party_size:
		active_party.append(character)
		print("PlayerManager: Dodana figura. Nova velikost ekipe: %d" % active_party.size())

# ----------------- SMRT IN OŽIVITEV (Revive) -----------------

# Registrira podatke o padli figuri (Klic iz BaseCharacter.die())
func register_dead_character(character_name: String, revive_cost: int = 1, scene_path: String = ""):
	var piece_data = {
		"name": character_name,
		"revive_cost": revive_cost,
		"scene_path": scene_path
	}
	# Prepričamo se, da figura ni že na seznamu (za vsak slučaj)
	var already_dead = false
	for item in dead_party:
		if item.name == character_name:
			already_dead = true
			break
	
	if not already_dead:
		dead_party.append(piece_data)
		print("!!! Padla figura registrirana: %s. Dead Party size: %d" % [character_name, dead_party.size()])

# Funkcija, ki se kliče iz Campfire menija za oživitev
func revive_character(character_data) -> bool:
	var revive_cost: int = character_data.get("revive_cost", 1)
	
	if not use_food(revive_cost):
		print("Oživitev %s neuspešna: Premalo hrane." % character_data.name)
		return false
	
	# 1. Odstranimo podatke iz Dead Party
	var index = dead_party.find(character_data)
	if index != -1:
		dead_party.remove_at(index)
	
	# 2. DODAMO PODATKE NAZAJ V ROSTER (pripravljen za naslednjo bitko)
	var exists_in_roster = false
	for item in character_roster:
		if item.name == character_data.name:
			exists_in_roster = true
			break
			
	if not exists_in_roster:
		character_roster.append(character_data)

	print("Figura %s oživljena in vrnjena v Roster. Strošek: %d hrane." % [character_data.name, revive_cost])
	return true
