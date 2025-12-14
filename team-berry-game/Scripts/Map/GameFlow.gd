# res://Scripts/GameFlow.gd (Autoload/Singleton)
extends Node
class_name GameFlow

# =========================================================
# 1. REFERENCE IN STANJE
# =========================================================

const MAP_SCENE      = preload("res://Scenes/Map/map.tscn")
const BATTLE_SCENE = preload("res://Scenes/Map/battle.tscn")

var game_initialized: bool = false 
var current_map_instance: Node = null

# =========================================================
# 2. INICIALIZACIJA IN ZAGON IGRE (POPRVEK ZA MENU)
# =========================================================

func _ready():
	# KLJUČNO POPRAVILO: _ready() v Autoloadu je zdaj prazen!
	# Vse čaka na klic iz Main Menu.
	pass


## Ta funkcija se kliče iz Main Menu ob pritisku gumba "Start"
func start_new_game():
	if game_initialized:
		push_error("GF: Igra je že inicializirana.")
		return
		
	game_initialized = true
	# (Tukaj bi prišlo do preklopa scene na loading screen, če bi bil ustvarjen)
	call_deferred("_initialize_game")


func _initialize_game():
	# 1. Ustvarimo in shranimo instanco mape
	current_map_instance = MAP_SCENE.instantiate()
	current_map_instance.name = "MapInstance"
	
	# 2. Naložimo shranjeno instanco mape kot prvo sceno
	# (S tem preklopimo sceno iz Main Menu na Mapo)
	_change_scene_instance(current_map_instance)

# =========================================================
# 3. ZAGON DOGODKOV
# =========================================================
# (Ostaja nespremenjeno)
func start_event(room_type: int):
	_change_scene_instance(BATTLE_SCENE.instantiate())


# =========================================================
# 4. VRAČANJE NA MAPO
# =========================================================
# (Ostaja nespremenjeno)
func return_to_map(event_results: Dictionary = {}):
	print("GF: Vračanje na že obstoječo sceno Map.")
	_change_scene_instance(current_map_instance)

# =========================================================
# 5. OSNOVNA LOGIKA MENJAVE SCENE
# =========================================================
# (Ostaja nespremenjeno)
func _change_scene_instance(new_instance: Node):
	
	if get_tree().current_scene:
		var old_scene = get_tree().current_scene
		
		old_scene.get_parent().remove_child(old_scene)
		
		if old_scene == current_map_instance:
			print("GF: Stara scena je mapa, ki jo ohranjamo.")
		else:
			print("GF: Stara scena ({}) bo uničena.".format([old_scene.name]))
			old_scene.queue_free()
		
	get_tree().root.call_deferred("add_child", new_instance)
	get_tree().call_deferred("set_current_scene", new_instance)
	
	print("--- Uspešno naložena scena: {} ---".format([new_instance.name]))
