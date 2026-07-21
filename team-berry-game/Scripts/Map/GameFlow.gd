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
const TUTORIAL_HUB_SCENE = preload("res://Scenes/Menu/tutorial_hub_menu.tscn")
const POST_BATTLE_SUMMARY_SCENE = preload("res://Scenes/Menu/post_battle_summary.tscn")

var game_initialized: bool = false
var current_map_instance: Node = null
var pause_menu_instance: Control = null
var pause_menu_layer: CanvasLayer = null
var floor_counter_layer: CanvasLayer = null
var floor_counter_label: Label = null
var post_battle_summary_layer: CanvasLayer = null

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

	_setup_floor_counter()


# Prikaže "TIER x/3" (ali samo "x" v infinite načinu) na sredini vrha zaslona,
# skozi CEL run (Map/Battle/Campfire/Shop) - isti CanvasLayer-na-rootu vzorec
# kot pause_menu_layer zgoraj, samo z nižjim layer (pod pavza menijem).
func _setup_floor_counter():
	floor_counter_layer = CanvasLayer.new()
	floor_counter_layer.name = "FloorCounterLayer"
	floor_counter_layer.layer = 9
	floor_counter_layer.visible = false

	# Full-width lopar pri vrhu zaslona - CenterContainer znotraj njega poskrbi
	# za vodoravno centriranje ne glede na dolžino besedila ("1" proti "1/3").
	var top_strip := Control.new()
	top_strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_strip.offset_top = 12
	top_strip.offset_bottom = 44
	top_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_counter_layer.add_child(top_strip)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_strip.add_child(center)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.12, 0.7)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	floor_counter_label = Label.new()
	floor_counter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_counter_label.add_theme_font_size_override("font_size", 20)
	panel.add_child(floor_counter_label)

	get_tree().root.call_deferred("add_child", floor_counter_layer)


# Klican ob začetku runa in ob vsakem advance_map_tier() - PlayerManager.current_map_tier
# je 0-based (tier 0 = "1"), MapGenerator.TIER_CONFIGS.size() je isti vir
# resnice kot hardcoded "3" v advance_map_tier() spodaj.
func _update_floor_counter():
	if not is_instance_valid(floor_counter_label):
		return
	var tier_display := PlayerManager.current_map_tier + 1
	if PlayerManager.game_mode == "infinite":
		floor_counter_label.text = str(tier_display)
	else:
		floor_counter_label.text = "%d/%d" % [tier_display, MapGenerator.TIER_CONFIGS.size()]


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

	if PlayerManager.current_map_tier >= 3 and PlayerManager.game_mode != "infinite":
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

	# Floor counter naj bo viden SAMO na mapi (raziskovanje med sobami), ne v
	# bitki/campfire/shopu/menijih - current_map_instance je edina scena, ki
	# se v _change_scene_instance kdaj ponovno uporabi (glej return_to_map*
	# zgoraj), zato je enakost z njo zanesljiv "smo na mapi?" test.
	if is_instance_valid(floor_counter_layer):
		var showing_map := new_instance == current_map_instance
		floor_counter_layer.visible = showing_map
		if showing_map:
			_update_floor_counter()

	print("--- Uspešno naložena scena: %s ---" % new_instance.name)

func game_over() -> Control:
	print("GF: Player lost. Returning to Main Menu.")
	_end_run()
	var new_menu := MAIN_MENU_SCENE.instantiate()
	_change_scene_instance(new_menu)
	return new_menu


# =========================================================
# 3b. POST-BATTLE SUMMARY
# =========================================================
# Dumb-view overlay (Scripts/Menu/post_battle_summary.gd) - GameFlow ostaja
# lastnik prehodne logike, scena samo oddaja signale ob pritisku gumbov.
# Layer 11: en nad pause_menu_layer (10), da pavza meni (če bi po nesreči
# pognan) ne prekrije summary-ja - bitka je itak že blokirana preko
# BattleState.GAME_OVER, zato tu NE nastavljamo get_tree().paused.

func show_victory_summary(friendly_party: Array, enemy_party: Array,
		new_friendly_piece: String, new_enemy_piece: String,
		upgrade_items_gained: int, is_boss_floor: bool) -> void:
	var summary_instance := POST_BATTLE_SUMMARY_SCENE.instantiate()
	var summary_layer := CanvasLayer.new()
	summary_layer.name = "PostBattleSummaryLayer"
	summary_layer.layer = 11
	summary_layer.add_child(summary_instance)
	post_battle_summary_layer = summary_layer
	get_tree().root.call_deferred("add_child", summary_layer)
	summary_instance.setup_victory(friendly_party, enemy_party, new_friendly_piece, new_enemy_piece, upgrade_items_gained)
	summary_instance.continue_pressed.connect(_on_victory_continue_pressed.bind(summary_layer, is_boss_floor))

func _on_victory_continue_pressed(summary_layer: CanvasLayer, is_boss_floor: bool) -> void:
	summary_layer.queue_free()
	post_battle_summary_layer = null
	if is_boss_floor:
		advance_map_tier()
	else:
		return_to_map()

func show_defeat_summary(final_tier: int, final_floor: int) -> void:
	var summary_instance := POST_BATTLE_SUMMARY_SCENE.instantiate()
	var summary_layer := CanvasLayer.new()
	summary_layer.name = "PostBattleSummaryLayer"
	summary_layer.layer = 11
	summary_layer.add_child(summary_instance)
	post_battle_summary_layer = summary_layer
	get_tree().root.call_deferred("add_child", summary_layer)
	summary_instance.setup_defeat(final_tier, final_floor)
	summary_instance.back_pressed.connect(_on_defeat_back_pressed.bind(summary_layer))

func _on_defeat_back_pressed(summary_layer: CanvasLayer) -> void:
	summary_layer.queue_free()
	post_battle_summary_layer = null
	var new_menu := game_over()
	new_menu.call_deferred("open_mode_select")


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


# =========================================================
# 6. TUTORIAL (hub + stopnje)
# =========================================================
# Hub in stopnje so PRAVE scene (ne overlayi kot settings/mode select) -
# stopnja je battle-like scena, po njej pa se mora hub zgraditi na novo.
# Nič od tega se ne dotika run stanja (game_initialized ostane false),
# zato hub-ov BACK varno uporabi return_to_main_menu() zgoraj.

func start_tutorial_hub():
	_change_scene_instance(TUTORIAL_HUB_SCENE.instantiate())

func start_tutorial_stage(stage_scene: PackedScene):
	_change_scene_instance(stage_scene.instantiate())

func return_to_tutorial_hub():
	_change_scene_instance(TUTORIAL_HUB_SCENE.instantiate())
