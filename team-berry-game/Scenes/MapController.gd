extends Node2D
class_name MapController

# Sklici na generator in vizualno predlogo
const MapGenerator = preload("res://Scripts/Map/MapGenerator.gd") 
const RoomIconScene = preload("res://Scenes/map_node_icon.tscn")    

# Shranimo generirane podatke
var map_data: Array = [] 

# Slovar za hitro iskanje vizualnega vozlišča na podlagi vira Room
# KLJUČ: Room Resource | VREDNOST: MapNodeIcon (vozlišče)
var room_node_map: Dictionary = {} 


func _ready():
	# 1. Zagon generiranja
	var generator = MapGenerator.new()
	map_data = generator.generate_map()
	
	# 2. Vizualizacija ikon
	_visualize_rooms()
	
	# 3. Narišemo povezovalne črte (pride do klica _draw())
	queue_redraw()


# =========================================================
# METODA ZA VIZUALIZACIJO
# =========================================================

func _visualize_rooms():
	# Instanciranje vseh ikon, ki so del poti
	for i in range(map_data.size()): # Iteracija po vrsticah (nadstropjih)
		for j in range(map_data[i].size()): # Iteracija po stolpcih
			var room_resource = map_data[i][j]
			
			# Preskočimo vozlišča, ki niso del poti (so NULL po cleanup-u)
			if room_resource == null:
				continue
			
			# Instanciranje vizualnega gumba
			var room_node = RoomIconScene.instantiate()
			add_child(room_node)
			
			# Inicializacija vozlišča s podatki iz vira Room
			room_node.initialize(room_resource)
			
			# Nastavitev 2D položaja glede na izračun iz MapGeneratorja
			room_node.position = room_resource.position
			
			# Shranimo sklic za risanje črt in interaktivnost
			room_node_map[room_resource] = room_node
			
			# Ker je to startna soba, jo takoj odklenemo (če še nismo)
			if i == MapGenerator.START_FLOOR:
				# To je prva soba, ki jo igralec lahko klikne
				# room_node.set_unlocked(true) # Če imate to logiko v RoomIcon.gd
				pass

# =========================================================
# METODA ZA RISANJE POVEZAV
# =========================================================

## To funkcijo kliče Godot avtomatsko, ko pokličemo queue_redraw()
func _draw():
	if map_data.is_empty():
		return

	# Nastavitve za črto
	var color_line = Color(0.5, 0.5, 0.5, 0.7)
	var line_width = 4.0

	# Iteriramo skozi vse sobe, ki so bile ustvarjene (so v room_node_map)
	for current_room_resource in room_node_map.keys():
		
		# Lokacija začetne točke (ikona sobe A)
		var start_node = room_node_map[current_room_resource]
		var start_pos = start_node.position
		
		# Iteriramo skozi vse povezave (next_rooms)
		for next_room_resource in current_room_resource.next_rooms:
			
			# Lokacija končne točke (ikona sobe B)
			if room_node_map.has(next_room_resource):
				var end_node = room_node_map[next_room_resource]
				var end_pos = end_node.position
				
				# Risanje črte med centroma dveh gumbov 
				draw_line(start_pos, end_pos, color_line, line_width)
