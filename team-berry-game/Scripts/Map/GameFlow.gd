# res://Scripts/GameFlow.gd (Autoload/Singleton)
extends Node
class_name GameFlow

# =========================================================
# 1. REFERENCE IN STANJE
# =========================================================

const MAP_SCENE      = preload("res://Scenes/Map/map.tscn")
const CAMPFIRE_SCENE = preload("res://Scenes/Map/campfire.tscn") 

var current_map_instance: Node = null 

# =========================================================
# 2. INICIALIZACIJA IN ZAGON IGRE (Stabilno)
# =========================================================

func _ready():
	call_deferred("_initialize_game")

func _initialize_game():
	# 1. Ustvarimo in shranimo instanco mape 
	current_map_instance = MAP_SCENE.instantiate()
	current_map_instance.name = "MapInstance" 
	
	# 2. Naložimo shranjeno instanco mape kot prvo sceno
	_change_scene_instance(current_map_instance)

# =========================================================
# 3. ZAGON DOGODKOV
# =========================================================

func start_event(room_type: int):
	
	match room_type:
		# VSE sobe gredo na Campfire za testiranje
		Room.RoomType.MONSTER, Room.RoomType.SHOP, Room.RoomType.BOSS, Room.RoomType.TREASURE, Room.RoomType.CAMPFIRE:
			var campfire_instance = CAMPFIRE_SCENE.instantiate()
			_change_scene_instance(campfire_instance)
			
		_:
			push_error("GF: Neznan tip sobe: %d" % room_type)


# =========================================================
# 4. VRAČANJE NA MAPO
# =========================================================

func return_to_map(event_results: Dictionary = {}):
	print("GF: Vračanje na že obstoječo sceno Map.")
	
	# Koda za preverjanje veljavnosti ni več potrebna, saj mape ne uničujemo
	
	_change_scene_instance(current_map_instance)


# =========================================================
# 5. OSNOVNA LOGIKA MENJAVE SCENE (Popravljeno)
# =========================================================

func _change_scene_instance(new_instance: Node):
	
	if get_tree().current_scene:
		var old_scene = get_tree().current_scene
		
		# 1. ODSTRANIMO IZ DREVESA
		old_scene.get_parent().remove_child(old_scene) 
		
		# 2. KLJUČNO PREVERJANJE: Ali je stara scena naša trajna mapa?
		if old_scene == current_map_instance:
			# Če je to mapa, je NE uničimo (queue_free()). Pustimo jo pri življenju.
			print("GF: Stara scena je mapa, ki jo ohranjamo.")
		else:
			# Če je to Campfire ali katera koli druga scena dogodka, jo uničimo.
			print("GF: Stara scena ({old_scene.name}) bo uničena.")
			old_scene.queue_free()
		
	# 3. Dodamo novo instanco v korensko vozlišče (uporaba call_deferred za stabilnost)
	get_tree().root.call_deferred("add_child", new_instance)
	
	# 4. Nastavitev current_scene (uporaba call_deferred)
	get_tree().call_deferred("set_current_scene", new_instance)
	
	print("--- Uspešno naložena scena: {new_instance.name} ---")
