# res://Scripts/GameFlow.gd (Autoload/Singleton)
extends Node
class_name GameFlow

# =========================================================
# 1. REFERENCE IN STANJE
# =========================================================

const MAP_SCENE = preload("res://Scenes/Map/map.tscn")
const BATTLE_SCENE = preload("res://Scenes/Map/battle.tscn")
const CAMPFIRE_SCENE = preload("res://Scenes/Map/campfire.tscn")
const SHOP_SCENE = preload("res://Scenes/Map/shop.tscn")
const MAIN_MENU_SCENE = preload("res://Scenes/Menu/main_menu.tscn")
const PAUSE_MENU_SCENE = preload("res://Scenes/Menu/pause_menu.tscn")

var game_initialized: bool = false
var current_map_instance: Node = null
var pause_menu_instance: Control = null
var pause_menu_layer: CanvasLayer = null

# =========================================================
# 2. INICIALIZACIJA IN ZAGON IGRE (POPRVEK ZA MENU)
# =========================================================

func _ready():
	# CanvasLayer wrapper is required here: the map/battle scene's active
	# Camera2D transforms the whole viewport's 2D canvas, so a Control added
	# as a plain sibling would pan/zoom along with gameplay instead of
	# staying screen-locked. CanvasLayer content ignores that transform -
	# same fix already used by CampfirePartyPanel.tscn elsewhere in the project.
	pause_menu_instance = PAUSE_MENU_SCENE.instantiate()
	pause_menu_layer = CanvasLayer.new()
	pause_menu_layer.name = "PauseMenuLayer"
	# CanvasLayers draw in ascending "layer" order (ties break by tree add
	# order). PauseMenuLayer is created once here at boot, before any
	# gameplay CanvasLayer (e.g. BattleUI) exists - without an explicit
	# layer it defaults to 1, same as those, so it lost the tie and rendered
	# underneath them. Force it above anything gameplay adds later.
	pause_menu_layer.layer = 10
	pause_menu_layer.add_child(pause_menu_instance)
	get_tree().root.call_deferred("add_child", pause_menu_layer)


## Ta funkcija se kliče iz Main Menu ob pritisku gumba "Start"
func start_new_game():
	if game_initialized:
		push_error("GF: Igra je že inicializirana.")
		return
		
	game_initialized = true
	call_deferred("_initialize_game")


func _initialize_game():
	# 1. Ustvarimo in shranimo instanco mape
	current_map_instance = MAP_SCENE.instantiate()
	current_map_instance.name = "MapInstance"
	# pending_tier (ne initialize_map() neposredno!) - vozlišče še ni v drevesu,
	# zato @onready sklici (map_camera ipd.) še niso na voljo. _ready() bo
	# initialize_map(pending_tier) poklical sam, ko bo vozlišče dodano.
	current_map_instance.pending_tier = PlayerManager.current_map_tier

	# 2. Naložimo shranjeno instanco mape kot prvo sceno
	# (S tem preklopimo sceno iz Main Menu na Mapo)
	_change_scene_instance(current_map_instance)

# =========================================================
# 3. ZAGON DOGODKOV
# =========================================================

func start_event(room_type: int):
	if room_type == Room.RoomType.campfire:
		# Ni bitke - preskoči resetActives() (uporablja se le za pripravo
		# battle scene na aktivno/sovražno ekipo).
		_change_scene_instance(CAMPFIRE_SCENE.instantiate())
		return

	if room_type == Room.RoomType.shop:
		# Ni bitke - preskoči resetActives(), enako kot campfire.
		_change_scene_instance(SHOP_SCENE.instantiate())
		return

	if room_type == Room.RoomType.item:
		# Ni bitke in ni menjave scene - nagrada je bila že dodeljena v
		# MapController._handle_event(), igralec ostane na mapi.
		return

	PlayerManager.resetActives()
	_change_scene_instance(BATTLE_SCENE.instantiate())

## Kliče se, ko igralec premaga boss sobo trenutne mape.
## Napreduje na naslednjo (težjo) mapo ali, po 3. mapi, konča run.
func advance_map_tier():
	PlayerManager.current_map_tier += 1

	if PlayerManager.current_map_tier >= 3:
		print("GF: Igralec je premagal vse 3 mape. Vračanje na Main Menu.")
		_end_run()
		_change_scene_instance(MAIN_MENU_SCENE.instantiate())
		return

	if is_instance_valid(current_map_instance):
		current_map_instance.queue_free()

	current_map_instance = MAP_SCENE.instantiate()
	current_map_instance.name = "MapInstance"
	current_map_instance.pending_tier = PlayerManager.current_map_tier
	PlayerManager.reset_floor_number()
	# Vojska sovražnikov je rasla čez celotno prejšnjo mapo (glej
	# PlayerManager.add_to_enemy_party) - nova (težja) mapa naj se začne
	# spet z osnovno ekipo, ne s celotno vojsko iz prejšnje mape.
	PlayerManager.enemy_party = PlayerManager.default_enemies.duplicate()
	_change_scene_instance(current_map_instance)


# =========================================================
# 4. VRAČANJE NA MAPO
# =========================================================

func return_to_map():
	print("GF: Vračanje na že obstoječo sceno Map.")
	_change_scene_instance(current_map_instance)

## Kliče se, ko igralec pobegne iz bitke z Divine Intervention. Za razliko
## od return_to_map() (uporablja se po zmagi) razveljavi izbiro sobe, iz
## katere je pobegnil - sicer MapController._update_reachable_rooms() to
## sobo trajno označi kot selected/zaklenjeno, čeprav je igralec izgubil,
## ne zmagal (glej BattleController.check_battle_end()).
func return_to_map_after_escape():
	print("GF: Vračanje na mapo po Divine Intervention - soba ostaja igriva.")
	if is_instance_valid(current_map_instance) and current_map_instance.has_method("revert_current_room_selection"):
		current_map_instance.revert_current_room_selection()
	_change_scene_instance(current_map_instance)

# =========================================================
# 5. OSNOVNA LOGIKA MENJAVE SCENE
# =========================================================

func _change_scene_instance(new_instance: Node):
	
	if get_tree().current_scene:
		var old_scene = get_tree().current_scene
		
		old_scene.get_parent().remove_child(old_scene)
		
		if old_scene == current_map_instance:
			print("GF: Stara scena je mapa, ki jo ohranjamo.")
		else:
			print("GF: Stara scena (%s) bo uničena." % old_scene.name)
			old_scene.queue_free()
		
	get_tree().root.call_deferred("add_child", new_instance)
	get_tree().call_deferred("set_current_scene", new_instance)
	
	print("--- Uspešno naložena scena: %s ---" % new_instance.name)

func game_over():
	print("GF: Player lost. Returning to Main Menu.")
	_end_run()
	_change_scene_instance(MAIN_MENU_SCENE.instantiate())


## Kliče se iz pavza menija (gumb "Main Menu"), da se izognemo isti sceni,
## ki jo `game_over()` uporablja za lastno "izgubil si" pot.
func return_to_main_menu():
	print("GF: Vračanje na Main Menu (ročno, iz pavze).")
	_end_run()
	_change_scene_instance(MAIN_MENU_SCENE.instantiate())


# Počisti stanje trenutnega runa. Mapa med bitkami živi IZVEN drevesa,
# zato je get_tree() ne sprosti sam - brez tega klica pušča spomin (leak).
func _end_run():
	game_initialized = false
	PlayerManager.current_map_tier = 0
	get_tree().paused = false
	if is_instance_valid(pause_menu_instance):
		pause_menu_instance.hide()
	if is_instance_valid(current_map_instance) and not current_map_instance.is_inside_tree():
		current_map_instance.queue_free()
	current_map_instance = null
