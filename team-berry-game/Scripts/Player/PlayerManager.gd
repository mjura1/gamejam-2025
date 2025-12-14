# res://Scripts/PlayerManager.gd
extends Node

# Inventar
var food: int = 5
var leather: int = 0
# TODO: Dodajte še druge predmete (pelt/leather)

# Party
# Ta seznam hrani SCENE (datoteke .tscn) ali shranjene podatke za figure.
# Za zdaj bomo hranili reference na pripeto skripto, ko bo figura v bitki.
var active_party: Array = []
var max_party_size: int = 4

# Ta array bo vseboval vse figure, ki jih ima igralec, tudi tiste v campu.
var all_player_pieces: Array = [] 

# Funkcija za dodajanje figure v aktivno ekipo
func add_to_active_party(character: Node):
	if character.is_enemy == false and not active_party.has(character):
		active_party.append(character)
		print("PlayerManager: Dodana figura. Nova velikost ekipe: %d" % active_party.size())

func _ready():
	print("PlayerManager naložen. Hrana: %d, Party size: %d" % [food, active_party.size()])

# Funckija, ki jo kličemo, ko se začne bitka
func setup_battle_party(active_characters_on_grid: Array):
	# Ta funkcija se kliče iz GridManagerja, ko so figure ustvarjene
	active_party = active_characters_on_grid
	
# Funckija za porabo hrane (za revive ali rest)
func use_food(amount: int) -> bool:
	if food >= amount:
		food -= amount
		print("Porabljena hrana. Ostalo: %d" % food)
		return true
	return false
	
# Funckija za dodajanje usnja/krzna
func add_leather(amount: int):
	leather += amount
	print("Dodan leather. Skupaj: %d" % leather)

# Funckija za oživitev figure (TODO: implementacija)
func revive_character(character_data) -> bool:
	# Kličemo, ko imamo revivanje v campu.
	if use_food(1): # ali ustrezen strošek hrane 
		# Koda za oživitev/dodajanje nazaj v all_player_pieces
		print("Figura oživljena.")
		return true
	return false
