# res://Scripts/Map/MapController.gd
extends Node2D
class_name MapController

# Sklici na generator in vizualno predlogo
const MapGenerator = preload("res://Scripts/Map/MapGenerator.gd")
const RoomIconScene = preload("res://Scenes/Map/map_node_icon.tscn")

@onready var map_camera: Camera2D = $MapCamera 
@onready var click_sound = $ClickStreamer

var map_data: Array = []
var room_node_map: Dictionary = {}
var current_room: Room = null
var is_initialized: bool = false 

var pan_start_position: Vector2 = Vector2.ZERO
var is_panning: bool = false 

# NEW: Meje celotne mape za omejitev kamere
var map_boundary_min: Vector2 = Vector2.ZERO
var map_boundary_max: Vector2 = Vector2.ZERO

func _ready():
	if not is_initialized:
		initialize_map()
	else:
		queue_redraw()

func _on_button_pressed():
	UiAudio.play_click()
	print("predvajam zvok")

# =========================================================
# METODE ZA ZAGON, VIZUALIZACIJO IN STANJE 
# =========================================================

func initialize_map():
	if is_initialized: return
	
	var generator = MapGenerator.new()
	map_data = generator.generate_map()
	
	_visualize_rooms()
	_set_initial_state()
	
	_calculate_map_boundaries() # NEW: Izračun meje celotne mape
	_center_and_zoom_camera() 
	
	is_initialized = true
	queue_redraw()
	
func _set_initial_state():
	for room in map_data[MapGenerator.START_FLOOR]:
		if room != null:
			_set_room_unlocked(room, true)

# NEW: Izračun meje CELOTNE mape za kamero
func _calculate_map_boundaries():
	if map_data.is_empty():
		return

	var min_x = 1e9
	var max_x = -1e9
	var min_y = 1e9
	var max_y = -1e9
	
	# Iteriramo skozi VSA nadstropja in VSE sobe, da najdemo absolutne meje
	for i in range(map_data.size()):
		for room in map_data[i]:
			if room != null:
				var pos = room.position
				min_x = min(min_x, pos.x)
				max_x = max(max_x, pos.x)
				min_y = min(min_y, pos.y)
				max_y = max(max_y, pos.y)
	
	# Dodamo rob (margin), da imamo malo prostora okoli robov mape
	var margin = 200.0 
	
	map_boundary_min = Vector2(min_x - margin, min_y - margin)
	map_boundary_max = Vector2(max_x + margin, max_y + margin)


func _input(event):
	# ================= 1. Premikanje (Pan) =================
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: 
			if event.pressed:
				is_panning = true
				pan_start_position = event.position
			else:
				is_panning = false

	if is_panning and event is InputEventMouseMotion:
		var delta = event.relative
		
		# Izračunamo novo pozicijo kamere brez omejitev
		var new_camera_position = map_camera.position - delta / map_camera.zoom.x
		
		# NEW: Omejitev kamere (Clamping)
		# Izračunamo velikost vidnega polja (viewport), prilagojeno trenutnemu zoomu
		var viewport_size = get_viewport_rect().size / map_camera.zoom
		var half_viewport = viewport_size / 2.0
		
		# Izračunamo meje, kjer se center kamere lahko nahaja.
		# Omejitev_MIN = meja mape + polovica vidnega polja (da se rob ne pojavi)
		var clamp_min = map_boundary_min + half_viewport
		# Omejitev_MAX = meja mape - polovica vidnega polja
		var clamp_max = map_boundary_max - half_viewport
		
		# Varnostna funkcija za zelo majhne mape, kjer bi lahko bil MIN > MAX
		clamp_min.x = min(clamp_min.x, clamp_max.x)
		clamp_min.y = min(clamp_min.y, clamp_max.y)
		
		# Omejimo novo pozicijo kamere znotraj izračunanih meja
		new_camera_position.x = clampf(new_camera_position.x, clamp_min.x, clamp_max.x)
		new_camera_position.y = clampf(new_camera_position.y, clamp_min.y, clamp_max.y)
		
		map_camera.position = new_camera_position

	# ================= 2. Povečava (Zoom) =================
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			map_camera.zoom /= 1.1 
			map_camera.zoom = map_camera.zoom.max(Vector2(0.5, 0.5))
		
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map_camera.zoom *= 1.1
			map_camera.zoom = map_camera.zoom.min(Vector2(2.0, 2.0))
			
		# Če je zoom spremenjen, ponovno preveri omejitve
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Ko spremenimo zoom, moramo ponovno izračunati in omejiti pozicijo kamere,
			# saj so se clamp meje spremenile (zaradi half_viewport)
			var viewport_size = get_viewport_rect().size / map_camera.zoom
			var half_viewport = viewport_size / 2.0
			
			var clamp_min = map_boundary_min + half_viewport
			var clamp_max = map_boundary_max - half_viewport
			
			clamp_min.x = min(clamp_min.x, clamp_max.x)
			clamp_min.y = min(clamp_min.y, clamp_max.y)
			
			var current_pos = map_camera.position
			current_pos.x = clampf(current_pos.x, clamp_min.x, clamp_max.x)
			current_pos.y = clampf(current_pos.y, clamp_min.y, clamp_max.y)
			map_camera.position = current_pos

func _visualize_rooms():
	for i in range(map_data.size()):
		for j in range(map_data[i].size()):
			var room_resource = map_data[i][j]
			
			if room_resource == null:
				continue
			
			var room_node = RoomIconScene.instantiate()
			add_child(room_node)
			
			room_node.initialize(room_resource)
			room_node.room_clicked.connect(_on_room_selected)
			
			room_node.position = room_resource.position
			room_node_map[room_resource] = room_node


func _set_room_unlocked(room: Room, unlocked: bool):
	if room != null and not room.selected:
		room.is_unlocked = unlocked
		
		if room_node_map.has(room):
			var room_node = room_node_map[room]
			room_node.update_look(unlocked, room.selected)


func _refresh_all_icons():
	for room in room_node_map.keys():
		var room_node = room_node_map[room]
		room_node.update_look(room.is_unlocked, room.selected)


func _update_reachable_rooms(new_room: Room):
	
	new_room.selected = true
	current_room = new_room
	
	var reachable_rooms: Array[Room] = new_room.next_rooms.duplicate()
	
	for i in range(map_data.size()):
		for j in range(map_data[i].size()):
			var room = map_data[i][j]
			
			if room == null:
				continue
			
			if room.selected:
				room.is_unlocked = false
			elif reachable_rooms.has(room):
				_set_room_unlocked(room, true)
			else:
				_set_room_unlocked(room, false)
	
	_refresh_all_icons()


# =========================================================
# METODA ZA RISANJE IN KLIK
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
				
				draw_line(start_pos, end_pos, color_line, line_width)

func _center_and_zoom_camera():
	# Ta funkcija ostane enaka, kot je bila določena v prejšnji seji, 
	# saj že osredotoča kamero na prva dve nadstropja.
	if map_data.is_empty():
		return

	const START_FLOOR_INDEX = 0
	const END_FLOOR_INDEX = 1 
	
	var min_x = 1e9 
	var max_x = -1e9
	var min_y = 1e9
	var max_y = -1e9
	var found_nodes = false

	for i in range(START_FLOOR_INDEX, min(map_data.size(), END_FLOOR_INDEX + 1)):
		for room in map_data[i]:
			if room != null:
				var pos = room.position
				min_x = min(min_x, pos.x)
				max_x = max(max_x, pos.x)
				min_y = min(min_y, pos.y)
				max_y = max(max_y, pos.y)
				found_nodes = true
	
	if not found_nodes:
		return

	var margin = 150.0 
	min_x -= margin
	max_x += margin
	min_y -= margin
	max_y += margin
	
	var center_x = (min_x + max_x) / 2.0
	var center_y = (min_y + max_y) / 2.0
	
	map_camera.position = Vector2(center_x, center_y)
	
	var map_width = max_x - min_x
	var map_height = max_y - min_y
	
	var viewport_size = get_viewport_rect().size
	var viewport_width = viewport_size.x
	var viewport_height = viewport_size.y
	
	var zoom_x = map_width / viewport_width
	var zoom_y = map_height / viewport_height
	
	var required_zoom = max(zoom_x, zoom_y)
	var final_zoom = required_zoom * 1.05 
	
	var new_zoom = Vector2(1.0, 1.0) / final_zoom 
	
	new_zoom.x = clamp(new_zoom.x, 0.5, 2.0) 
	new_zoom.y = clamp(new_zoom.y, 0.5, 2.0)
	
	map_camera.zoom = new_zoom


func _on_room_selected(room_data: Room):
	print("Igralec izbral sobo: %s pri %s" % [Room.RoomType.keys()[room_data.type], room_data.grid_position])
	_on_button_pressed()
	_handle_event(room_data)
	_update_reachable_rooms(room_data)
	
	queue_redraw()

func _handle_event(room_data: Room):
	var name = Room.RoomTypeNames.get(room_data.type, "unknown_event")
	print("Zagon %s..." % name)
	
	if name.begins_with("enemy_"):
		PlayerManager.add_to_enemy_party(name)
	else:
		PlayerManager.add_to_friendly_party(name)
	
	PlayerManager.addSnow()
	
	GF.start_event(room_data.type)
