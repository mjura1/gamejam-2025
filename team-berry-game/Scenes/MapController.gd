# res://Scripts/Map/MapController.gd
extends Node2D
class_name MapController

# Sklici na generator in vizualno predlogo
const MapGenerator = preload("res://Scripts/Map/MapGenerator.gd")
const RoomIconScene = preload("res://Scenes/map_node_icon.tscn")

@onready var map_camera: Camera2D = $MapCamera # Povezava do vozlišča Camera2D

var map_data: Array = []
var room_node_map: Dictionary = {}
var current_room: Room = null

# Za sledenje, kje je bila miška v prejšnjem okviru
var pan_start_position: Vector2 = Vector2.ZERO
var is_panning: bool = false # Ali trenutno premikamo kamero

func _ready():
	var generator = MapGenerator.new()
	map_data = generator.generate_map()
	
	
	
	_visualize_rooms()
	_set_initial_state() # Odkleni začetne sobe!
	
	queue_redraw()

# =========================================================
# METODE ZA ZAGON, VIZUALIZACIJO IN STANJE
# =========================================================

func _set_initial_state():
	# Odklenemo vse sobe na 0. nadstropju (startne točke)
	for room in map_data[MapGenerator.START_FLOOR]:
		if room != null:
			_set_room_unlocked(room, true)

# MapController.gd

func _input(event):
	# ================= 1. Premikanje (Pan) =================
	
	# Preverimo, ali je pritisnjen desni gumb miške (ali levi, če želite)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Začnemo premikati (pan) in shranimo začetno pozicijo miške
				is_panning = true
				pan_start_position = event.position
			else:
				# Končamo premikanje
				is_panning = false

	# Če se premikamo in se miška premika
	if is_panning and event is InputEventMouseMotion:
		# Izračunamo razliko v premiku miške med okvirji
		var delta = event.relative
		
		# Premaknemo kamero. Kamero premikamo v nasprotno smer od premika miške.
		# Opomba: map_camera.global_position lahko uporabite tudi kot map_camera.position,
		# ker se nahaja pod Node2D.
		map_camera.position -= delta / map_camera.zoom.x

	# ================= 2. Povečava (Zoom) =================
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Povečava (zoom in): Zmanjšamo vrednost zoom.x in zoom.y
			map_camera.zoom /= 1.1 
			# Omejimo največjo povečavo, da ne gre preblizu
			map_camera.zoom = map_camera.zoom.max(Vector2(0.5, 0.5))
		
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Pomanjšanje (zoom out): Povečamo vrednost zoom.x in zoom.y
			map_camera.zoom *= 1.1
			# Omejimo najmanjšo povečavo, da ne gre predaleč
			map_camera.zoom = map_camera.zoom.min(Vector2(2.0, 2.0))

func _visualize_rooms():
	for i in range(map_data.size()):
		for j in range(map_data[i].size()):
			var room_resource = map_data[i][j]
			
			if room_resource == null:
				continue
			
			var room_node = RoomIconScene.instantiate()
			add_child(room_node)
			
			# Inicializacija vozlišča
			room_node.initialize(room_resource)
			
			# Povezava signala klika na to skripto
			room_node.room_clicked.connect(_on_room_selected)
			
			room_node.position = room_resource.position
			room_node_map[room_resource] = room_node


func _set_room_unlocked(room: Room, unlocked: bool):
	if room != null and not room.selected:
		room.is_unlocked = unlocked
		
		# Posodobimo vizualni gumb
		if room_node_map.has(room):
			var room_node = room_node_map[room]
			room_node.update_look(unlocked, room.selected)


func _refresh_all_icons():
	for room in room_node_map.keys():
		var room_node = room_node_map[room]
		room_node.update_look(room.is_unlocked, room.selected)


# MapController.gd

func _update_reachable_rooms(new_room: Room):
	
	# 1. Nastavite novo sobo kot izbrano
	new_room.selected = true
	current_room = new_room
	
	# 2. Definirajte dosegljive sobe (naslednje nadstropje)
	var reachable_rooms: Array[Room] = new_room.next_rooms.duplicate()
	
	# 3. Glavna Zanka: Pregled vseh sob v mapi in ponovno določanje stanja
	for i in range(map_data.size()):
		for j in range(map_data[i].size()):
			var room = map_data[i][j]
			
			if room == null:
				continue
			
			if room.selected:
				# Pustimo sobo v stanju "selected" (siva)
				room.is_unlocked = false
			elif reachable_rooms.has(room):
				# Odklenemo samo sobe v naslednjem koraku
				_set_room_unlocked(room, true)
			else:
				# VSE ostale sobe (na prejšnjih/istih/daljnih nadstropjih)
				_set_room_unlocked(room, false) 
	
	# 4. Posodobimo vizualizacijo vseh ikon
	_refresh_all_icons()


# =========================================================
# METODA ZA RISANJE POVEZAV IN OBRNAVNO KLIKA
# =========================================================

func _draw():
	if map_data.is_empty():
		return

	var color_line = Color(0.5, 0.5, 0.5, 0.7)
	var line_width = 4.0

	for current_room_resource in room_node_map.keys():
		var start_node = room_node_map[current_room_resource]
		var start_pos = start_node.position
		
		for next_room_resource in current_room_resource.next_rooms:
			if room_node_map.has(next_room_resource):
				var end_node = room_node_map[next_room_resource]
				var end_pos = end_node.position
				
				# Risanje črte med centroma dveh gumbov 
				draw_line(start_pos, end_pos, color_line, line_width)


func _on_room_selected(room_data: Room):
	print("Igralec izbral sobo: %s pri %s" % [Room.RoomType.keys()[room_data.type], room_data.grid_position])
	
	_handle_event(room_data)
	_update_reachable_rooms(room_data)
	
	queue_redraw() # Posodobitev, če bi črte menjale barvo/stil

# CHANGE SCENES, DODAJ 
func _handle_event(room_data: Room):
	match room_data.type:
		Room.RoomType.MONSTER:
			print("Zagon BITKE...")
			# get_tree().chadkenge_scene_to_file("res://Scenes/Battle.tscn")
		Room.RoomType.SHOP:
			print("Zagon TRGOVINE...")
		Room.RoomType.BOSS:
			print("Zagon ŠEFA!")
		Room.RoomType.CAMPFIRE:
			print("OPEN SHOP")
			
		_:
			print("Zagon neznanega dogodka.")
