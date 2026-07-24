# res://Scripts/Battle/battle_ui.gd
# Desni UI panel v bitki: roster, aktivne figure, itemi, podrobnosti izbrane
# figure, turn indikator in START/END TURN gumb. Vodi tudi placement fazo
# (drag & drop figur iz rosterja v spodnje 3 vrstice plošče).
# Živi na CanvasLayerju, da ga Camera2D ne transformira (enak pristop kot
# pause menu - glej GameFlow._ready()).
extends CanvasLayer

# Največ figur, ki jih igralec lahko postavi v eno bitko.
const MAX_PLACED := 5

@onready var player_manager = get_node("/root/PlayerManager")
# Za ceno a2_unlock vozlišča v "locked" sporočilu (glej _show_abilities) -
# cene ne živijo več v GameParameters/abilities.json, ampak v GameParameters/skill_trees.json.
@onready var skill_tree_data = get_node("/root/SkillTreeData")
@onready var grid_manager = get_node("../GridManager")
@onready var map_behaviour = get_node("../Map")
@onready var battle_controller = get_node("../BattleController")
@onready var placement_highlighter = get_node("../PlacementHighlighter")
@onready var move_highlighter = get_node("../MoveHighlighter")
# Koren battle scene - battle.gd nosi friendly_pieces slovar (ime -> scena).
@onready var battle_root = get_node("..")

@onready var roster_row: HFlowContainer = %RosterRow
@onready var active_row: HFlowContainer = %ActiveRow
@onready var upgrade_count_label: Label = %UpgradeCount
@onready var revive_count_label: Label = %ReviveCount
@onready var portrait: TextureRect = %Portrait
@onready var status_header: Label = %StatusHeader
@onready var status_value: Label = %StatusValue
@onready var curse_block: VBoxContainer = %CurseBlock
@onready var curse_name_label: Label = %CurseNameLabel
@onready var curse_explanation_label: Label = %CurseExplanationLabel
@onready var hsep1: HSeparator = %HSep1
@onready var hsep2: HSeparator = %HSep2
@onready var hsep3: HSeparator = %HSep3
@onready var ability1_row: HBoxContainer = %Ability1Row
@onready var ability1_icon: TextureRect = %Ability1Icon
@onready var ability1_name: Label = %Ability1Name
@onready var ability1_level: Label = %Ability1Level
@onready var ability1_uses: Label = %Ability1Uses
@onready var ability1_button: Button = %Ability1Button
@onready var ability2_row: HBoxContainer = %Ability2Row
@onready var ability2_icon: TextureRect = %Ability2Icon
@onready var ability2_name: Label = %Ability2Name
@onready var ability2_level: Label = %Ability2Level
@onready var ability2_uses: Label = %Ability2Uses
@onready var ability2_button: Button = %Ability2Button
@onready var ability3_row: HBoxContainer = %Ability3Row
@onready var ability3_icon: TextureRect = %Ability3Icon
@onready var ability3_name: Label = %Ability3Name
@onready var ability3_level: Label = %Ability3Level
@onready var ability3_uses: Label = %Ability3Uses
@onready var ability3_button: Button = %Ability3Button
@onready var ability_bubble: PanelContainer = %AbilityBubble
@onready var ability_bubble_label: Label = %AbilityBubbleLabel
@onready var moves_label: Label = %MovesLabel
@onready var abilities_label: Label = %AbilitiesLabel
@onready var turn_label: Label = %TurnLabel
@onready var action_button: Button = %ActionButton
@onready var board_area: Control = %BoardArea
@onready var drag_ghost: TextureRect = %DragGhost
@onready var placement_actions_row: HBoxContainer = %PlacementActionsRow
@onready var auto_fill_button: Button = %AutoFillButton
@onready var remove_all_button: Button = %RemoveAllButton
@onready var tile_map = get_node("../Map/TileMapLayer")
@onready var items_toggle_button: Button = %ItemsToggleButton
@onready var detail_panel: PanelContainer = %DetailPanel
@onready var item_grid_panel: PanelContainer = %ItemGridPanel
@onready var item_grid: GridContainer = %ItemGrid

const STATUS_ALIVE_COLOR := Color(0.5, 1.0, 0.5)
const STATUS_DEAD_COLOR := Color(1.0, 0.4, 0.4)
const STATUS_BENCHED_COLOR := Color(0.75, 0.75, 0.75)
const STATUS_STUNNED_COLOR := Color(0.8, 0.5, 1.0)
const STATUS_ROOTED_COLOR := Color(0.45, 0.65, 0.25)
const STATUS_FROZEN_COLOR := Color(0.55, 0.8, 1.0)
const STATUS_MARKED_COLOR := Color(0.95, 0.55, 0.85)

const ABILITY_ICON_PLACEHOLDER := preload("res://Assets/Sprites/ability_placeholder.png")
# Isti "sivi" ton kot PieceIcon.COLOR_DEAD, da je "nedosegljivo" vizualno
# skladno povsod po tem UI-ju.
const ABILITY_ICON_LOCKED_TINT := Color(0.35, 0.35, 0.35)
const ABILITY_ICON_UNLOCKED_TINT := Color(1, 1, 1)
const ABILITY_BUBBLE_WIDTH := 260.0
const ABILITY_BUBBLE_MARGIN := 8.0
const ABILITY_BUTTON_TEXT_UNLOCKED := "Use Ability"
const ABILITY_BUTTON_TEXT_LOCKED := "?"

var placement_active: bool = false

# Slot (1-3) -> hover bubble text ("" = no bubble on hover), napolnjen iz
# _show_abilities()/_clear_ability_rows(), bran samo iz
# _on_ability_row_mouse_entered spodaj. Prekletstvo sovražnika ima od
# BATTLE_UI_CONTEXTUAL_PANEL_PLAN.md dalje svoj lasten, vedno viden blok
# (glej CurseBlock/_show_enemy) in ne uporablja več tega mehanizma.
var _slot_bubble_state: Dictionary = {1: "", 2: "", 3: ""}

# Stanje drag & dropa med placement fazo. drag_source_character je nastavljen,
# ko premikamo že postavljeno figuro; sicer postavljamo novo iz rosterja.
var dragging: bool = false
var drag_piece_name: String = ""
var drag_source_character: BaseCharacter = null

# Stanje drag & dropa za itemsko mrežo (ločeno od figur, da se drag-a ne
# moreta prepletati - glej _input()). _item_view_open sledi ItemsToggleButtonu -
# selekcija figure/inšpekcija sovražnika jo VEDNO zapre (glej
# BATTLE_UI_CONTEXTUAL_PANEL_PLAN.md §3.3).
var _item_view_open: bool = false
var dragging_item: bool = false
var drag_item_id: String = ""

# Figura, ki je trenutno prikazana v detail panelu (null, če gre za mrtvo/
# klopno figuro brez žive instance - takrat gumbi ostanejo onemogočeni).
var _shown_character: BaseCharacter = null


func _ready():
	player_manager.party_changed.connect(_on_party_changed)
	player_manager.items_changed.connect(_update_item_counts)
	map_behaviour.selection_changed.connect(_on_selection_changed)
	map_behaviour.ability_activated.connect(_on_ability_activated)
	map_behaviour.enemy_inspected.connect(_show_enemy)
	map_behaviour.enemy_inspection_cleared.connect(_clear_detail_panel)
	battle_controller.state_changed.connect(_on_battle_state_changed)
	battle_controller.moves_changed.connect(_on_moves_changed)
	battle_controller.abilities_changed.connect(_on_abilities_changed)
	battle_controller.bounty_marked.connect(func(character): _set_board_badge(character, "☠"))
	battle_controller.prospectors_pick_marked.connect(func(character): _set_board_badge(character, "$"))
	battle_controller.courier_marked.connect(func(character): _set_board_badge(character, "C"))
	battle_controller.old_guard_marked.connect(func(character): _set_board_badge(character, "OG"))
	battle_controller.golden_quarry_marked.connect(func(character): _set_board_badge(character, "GQ"))
	battle_controller.piece_stunned.connect(_on_piece_stunned)
	battle_controller.piece_rooted.connect(_on_piece_rooted)
	battle_controller.piece_frozen.connect(_on_piece_frozen)
	board_area.gui_input.connect(_on_board_area_input)
	action_button.pressed.connect(_on_action_button_pressed)
	auto_fill_button.pressed.connect(_on_auto_fill_pressed)
	remove_all_button.pressed.connect(_on_remove_all_pressed)
	items_toggle_button.pressed.connect(_on_item_toggle_pressed)
	player_manager.items_changed.connect(_rebuild_item_grid)
	ability1_button.pressed.connect(_on_ability_pressed.bind(1))
	ability2_button.pressed.connect(_on_ability_pressed.bind(2))
	ability3_button.pressed.connect(_on_ability_pressed.bind(3))
	for slot_row in [[1, ability1_row], [2, ability2_row], [3, ability3_row]]:
		var slot: int = slot_row[0]
		var row: HBoxContainer = slot_row[1]
		row.mouse_entered.connect(_on_ability_row_mouse_entered.bind(slot, row))
		row.mouse_exited.connect(_hide_ability_bubble)
	# Preberi rebindane bližnjice v živo (npr. igralec spremeni bind med pavzo
	# sredi bitke) - značke slotov naj se takoj osvežijo.
	KeybindManager.rebinds_changed.connect(_rebuild_rows)

	for w in _ability_slot_widgets().values():
		w.icon.texture = ABILITY_ICON_PLACEHOLDER
	ability_bubble_label.custom_minimum_size.x = ABILITY_BUBBLE_WIDTH

	_update_item_counts()
	_clear_detail_panel()
	_rebuild_item_grid()

	# Figure (sovražniki/ovire) se spawnajo šele v battle.gd._ready() (starš
	# se inicializira ZA otroki), zato prvo gradnjo vrstic odložimo za en frame.
	_rebuild_rows.call_deferred()


# ===============================================
# TIPKOVNE BLIŽNJICE
# ===============================================

# Bližnjice za tipke 1-0 (izbira roster mesta), presledek (END TURN/START),
# S (izberi nazadnje premaknjeno figuro), D/F (sposobnost 1/2) in G (odpri/
# zapri predalo z itemi). Vsaka preprosto pokliče isto funkcijo, ki bi jo
# sprožil ustrezen klik z miško, zato podeduje vso obstoječo logiko/omejitve
# (can_select, disabled gumbi ...).
func _unhandled_input(event):
	if event.is_action_pressed("end_turn") and not action_button.disabled:
		_on_action_button_pressed()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ability_1") and not ability1_button.disabled:
		_on_ability_pressed(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ability_2") and not ability2_button.disabled:
		_on_ability_pressed(2)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ability_3") and not ability3_button.disabled:
		_on_ability_pressed(3)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_items") and not items_toggle_button.disabled:
		_on_item_toggle_pressed()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("select_last_moved"):
		map_behaviour.select_last_moved()
		get_viewport().set_input_as_handled()
		return
	for i in range(10):
		if event.is_action_pressed("piece_slot_%d" % (i + 1)):
			_select_roster_slot(i)
			get_viewport().set_input_as_handled()
			return


# Simulira klik na roster ikono na mestu `index` (0-based) - _rebuild_rows()
# gradi roster_row v istem vrstnem redu kot player_manager.friendly_party, zato
# je pozicija stabilna dokler se roster ne spremeni.
func _select_roster_slot(index: int):
	if index >= roster_row.get_child_count():
		return
	var icon := roster_row.get_child(index) as PieceIcon
	if icon:
		_on_icon_clicked(icon)


# ===============================================
# STANJE BITKE (turn label + gumb + placement vklop)
# ===============================================

func _on_battle_state_changed(new_state):
	# Itemska mreža med placementom nima smisla (itemi se uporabljajo na
	# figurah/plošči med bitko) - onemogočimo gumb, dokler igralec ne potrdi
	# postavitve. Če je bila mreža odprta, ko smo VSTOPILI v placement (rob
	# primer - ne bi se smelo zgoditi sredi bitke, a stanje naj ostane
	# konsistentno), jo prisilno zapremo.
	items_toggle_button.disabled = new_state == battle_controller.BattleState.PLACEMENT
	if items_toggle_button.disabled and _item_view_open:
		_item_view_open = false
		_refresh_shared_area()

	match new_state:
		battle_controller.BattleState.PLACEMENT:
			placement_active = true
			placement_highlighter.show_zone()
			board_area.mouse_filter = Control.MOUSE_FILTER_STOP
			placement_actions_row.visible = true
			moves_label.text = ""
			abilities_label.text = ""
			_update_placement_ui()
		battle_controller.BattleState.PLAYER_TURN:
			if placement_active:
				placement_active = false
				placement_highlighter.clear_zone()
				board_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
				placement_actions_row.visible = false
			turn_label.text = "PLAYER TURN"
			action_button.text = "END TURN"
			action_button.disabled = false
			# moves_remaining/abilities_remaining se posodobita malo kasneje v
			# isti klicni verigi (glej BattleController.start_player_turn()) -
			# moves_changed/abilities_changed ju takoj zatem osvežita tudi tukaj.
			# Prekletstvo "stunning_gaze": ob vsakem vstopu v igralčevo potezo
			# preberemo dejansko stunned_turns stanje vseh zaveznikov (odštevanje
			# se zgodi v BattleController.end_player_turn) - značka se s tem
			# zanesljivo pojavi/izgine, tudi če je bilo vmes več sprememb.
			_refresh_stun_badges()
			_refresh_root_badges()
			_refresh_frozen_badges()
			_refresh_marked_badges()
			_refresh_war_council_badges()
		battle_controller.BattleState.ENEMY_TURN:
			turn_label.text = "ENEMY TURN"
			action_button.disabled = true
			moves_label.text = ""
			abilities_label.text = ""
		battle_controller.BattleState.GAME_OVER:
			turn_label.text = "BATTLE OVER"
			action_button.disabled = true
			moves_label.text = ""
			abilities_label.text = ""

	# Sovražnik nima pravih sposobnosti (glej _show_enemy - prva vrstica tam
	# kaže prekletstvo, ne sposobnost) - ne prepišimo tega z generičnim
	# "-"/onemogočenim gumbom ob vsaki spremembi stanja bitke.
	if is_instance_valid(_shown_character) and not _shown_character.is_enemy:
		_show_abilities(_shown_character)


func _on_action_button_pressed():
	if placement_active:
		confirm_placement()
	elif battle_controller.can_end_turn():
		# END TURN je edini način za konec igralčeve poteze - premiki in
		# sposobnosti samo porabljajo svoja LOČENA proračuna (glej
		# consume_move()/consume_ability() klicatelje), zato mora biti gumb
		# pritisljiv tudi pri 0 premikih/sposobnostih.
		battle_controller.end_player_turn()


func _on_moves_changed(remaining: int, max_moves: int):
	moves_label.text = "MOVES: %d/%d" % [remaining, max_moves]
	# Snow rework: a mid-turn rescue (another piece moving next to a frozen
	# ally) thaws it the SAME turn - moves_changed fires right after that
	# move, so the badge/status update without waiting for next turn start.
	_refresh_frozen_badges()


func _on_abilities_changed(remaining: int, max_abilities: int):
	abilities_label.text = "ABILITIES: %d/%d" % [remaining, max_abilities]
	_refresh_frozen_badges()


# ===============================================
# PLACEMENT FAZA
# ===============================================

func _max_placeable() -> int:
	return mini(MAX_PLACED, player_manager.friendly_party.size())


func _placed_characters() -> Array:
	var placed: Array = []
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter):
			continue
		if character.is_enemy or character.is_obstacle:
			continue
		placed.append(character)
	return placed


func _is_free_placement_cell(grid_pos: Vector2i) -> bool:
	return placement_highlighter.is_placement_cell(grid_pos) and not grid_manager.is_occupied(grid_pos)


# Ali je bitka v placement fazi (vir resnice je BattleController, ne lokalni
# placement_active - ta se nastavi šele v našem signal handlerju).
func _in_placement_phase() -> bool:
	return battle_controller.current_state == battle_controller.BattleState.PLACEMENT


# Postavi novo figuro iz rosterja na polje. Vrne false, če polje ni veljavno,
# je dosežen limit ali te figure ni več na voljo.
func place_piece(roster_name: String, grid_pos: Vector2i) -> bool:
	if not _in_placement_phase():
		return false
	if not _is_free_placement_cell(grid_pos):
		return false
	if _placed_characters().size() >= _max_placeable():
		return false
	if _count_available(roster_name) <= 0:
		return false

	var piece_scene: PackedScene = battle_root.friendly_pieces[roster_name]
	grid_manager.spawn_character(piece_scene, grid_manager.grid_to_world(grid_pos))
	_after_placement_change()
	return true


func move_placed_piece(character: BaseCharacter, grid_pos: Vector2i) -> bool:
	if not _in_placement_phase() or not _is_free_placement_cell(grid_pos):
		return false
	grid_manager.vacate(character.grid_pos)
	character.grid_pos = grid_pos
	grid_manager.occupy(grid_pos, character)
	character.slide_to(grid_manager.grid_to_world(grid_pos))
	_after_placement_change()
	return true


func remove_placed_piece(character: BaseCharacter):
	if not _in_placement_phase():
		return
	grid_manager.vacate(character.grid_pos)
	character.queue_free()
	_after_placement_change()


# Koliko figur tega tipa je še na klopi (v rosterju, a ne na plošči).
func _count_available(roster_name: String) -> int:
	var owned := 0
	for entry in player_manager.friendly_party:
		if entry == roster_name:
			owned += 1
	var placed := 0
	for character in _placed_characters():
		if "friendly_" + character.strName == roster_name:
			placed += 1
	return owned - placed


# Potrdi postavitev: active_party postanejo postavljene figure, bitka se začne.
func confirm_placement():
	var placed := _placed_characters()
	if placed.is_empty():
		return

	var placed_names: Array[String] = []
	for character in placed:
		placed_names.append("friendly_" + character.strName)
	player_manager.active_party = placed_names

	battle_controller.confirm_placement()


func _after_placement_change():
	placement_highlighter.refresh()
	_rebuild_rows()
	_update_placement_ui()


func _update_placement_ui():
	var placed_count := _placed_characters().size()
	turn_label.text = "PLACE YOUR PIECES (%d/%d)" % [placed_count, _max_placeable()]
	action_button.text = "START"
	action_button.disabled = placed_count == 0
	auto_fill_button.disabled = placed_count >= _max_placeable() or not _has_available_piece()
	remove_all_button.disabled = placed_count == 0


# Ali je na klopi še vsaj ena figura, ki bi jo auto-fill lahko postavil.
func _has_available_piece() -> bool:
	for roster_name in player_manager.friendly_party:
		if _count_available(roster_name) > 0:
			return true
	return false


# Vsa prosta polja v placement coni, v vrstnem redu vrstica za vrstico.
func _free_placement_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var used_rect: Rect2i = tile_map.get_used_rect()
	for y in range(used_rect.position.y, used_rect.end.y):
		for x in range(used_rect.position.x, used_rect.end.x):
			var grid_pos := Vector2i(x, y)
			if _is_free_placement_cell(grid_pos):
				cells.append(grid_pos)
	return cells


# AUTO FILL: postavi figure s klopi na prosta polja, dokler ne doseže 5 (ali
# zmanjka figur/prostora - kar prej nastopi).
func _on_auto_fill_pressed():
	if not _in_placement_phase():
		return
	var free_cells := _free_placement_cells()
	for roster_name in player_manager.friendly_party:
		if _placed_characters().size() >= _max_placeable() or free_cells.is_empty():
			break
		if _count_available(roster_name) <= 0:
			continue
		place_piece(roster_name, free_cells.pop_front())


# REMOVE ALL: pobere vse trenutno postavljene figure nazaj na klop.
func _on_remove_all_pressed():
	if not _in_placement_phase():
		return
	for character in _placed_characters():
		grid_manager.vacate(character.grid_pos)
		character.queue_free()
	_after_placement_change()


# ===============================================
# DRAG & DROP (samo med placement fazo)
# ===============================================

func _begin_drag(piece_name: String, source_character: BaseCharacter):
	dragging = true
	drag_piece_name = piece_name
	drag_source_character = source_character

	if is_instance_valid(source_character):
		source_character.modulate.a = 0.4

	drag_ghost.texture = load("res://Assets/Sprites/%s.png" % piece_name)
	drag_ghost.position = get_viewport().get_mouse_position() - drag_ghost.size / 2
	drag_ghost.visible = true


# Klik na ploščo med placementom: poberi že postavljeno figuro.
func _on_board_area_input(event):
	if not placement_active or dragging:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Pozicija iz eventa (ne get_global_mouse_position() - ta sledi
		# dejanskemu OS kazalcu in se lahko razlikuje od sinteticnih eventov).
		var grid_pos := _screen_to_grid(board_area.get_global_transform() * event.position)
		var character = grid_manager.get_character_at(grid_pos)
		if character is BaseCharacter and not character.is_enemy and not character.is_obstacle:
			_begin_drag("friendly_" + character.strName, character)
			board_area.accept_event()


func _input(event):
	if dragging_item:
		if event is InputEventMouseMotion:
			drag_ghost.position = event.position - drag_ghost.size / 2
			_update_item_aim(event.position)
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_resolve_item_drop(event.position)
			get_viewport().set_input_as_handled()
		return

	if not dragging:
		return

	if event is InputEventMouseMotion:
		drag_ghost.position = event.position - drag_ghost.size / 2

	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_resolve_drop(event.position)
		get_viewport().set_input_as_handled()


func _resolve_drop(screen_pos: Vector2):
	dragging = false
	drag_ghost.visible = false

	var grid_pos := _screen_to_grid(screen_pos)

	if is_instance_valid(drag_source_character):
		drag_source_character.modulate.a = 1.0

		if grid_pos == drag_source_character.grid_pos:
			# Klik brez premika: samo prikaži podrobnosti figure.
			_show_character(drag_source_character)
		elif _is_free_placement_cell(grid_pos):
			move_placed_piece(drag_source_character, grid_pos)
		elif not placement_highlighter.is_placement_cell(grid_pos):
			# Spuščeno izven cone (ali na panel): figura nazaj na klop.
			remove_placed_piece(drag_source_character)
		# Zasedeno polje znotraj cone: figura ostane, kjer je bila.

		drag_source_character = null
	else:
		# Nova figura iz rosterja - place_piece sam zavrne neveljavna polja.
		place_piece(drag_piece_name, grid_pos)

	drag_piece_name = ""


func _screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return grid_manager.world_to_grid(world_pos)


# ===============================================
# ZNAČKE S TIPKO ZA IZBIRO (roster/aktivna vrstica + figura na plošči)
# ===============================================

# Trenutna tipka, ki izbere roster mesto `index` (0-based, torej piece_slot_1
# za index 0 ...) - ista bližnjica, ki jo uporablja _select_roster_slot().
func _slot_label_text(index: int) -> String:
	var action := "piece_slot_%d" % (index + 1)
	if not InputMap.has_action(action):
		return ""
	return KeybindManager.keycode_to_label(KeybindManager.get_current_keycode(action))


# Font je rasteriziran pri BADGE_RASTER_FONT_SIZE (bitmap glyph), nato pa ga
# transform (glej badge.scale spodaj) pomanjša do dejanske velikosti
# (BADGE_WORLD_FONT_HEIGHT, v "svet" enotah). Če bi rasterizirali neposredno
# pri majhni ciljni velikosti in jo NATO povečali (kompenzacija za inv_scale),
# bi raztegovali droben, že zamegljen bitmap - od tod pikslasto besedilo na
# plošči. Namesto tega rasteriziramo veliko večji izvorni bitmap in ga na
# koncu pomanjšamo za isti faktor (BADGE_RASTER_BOOST) - končna vidna
# velikost ostane enaka, izvor pa je veliko bolj podroben (manjšanje ostrega
# bitmapa je vizualno bistveno čistejše od raztezanja drobnega).
const BADGE_WORLD_FONT_HEIGHT := 6.0
const BADGE_RASTER_FONT_SIZE := 48
const BADGE_RASTER_BOOST := BADGE_RASTER_FONT_SIZE / BADGE_WORLD_FONT_HEIGHT


# Doda (ali osveži) majhno prosojno značko neposredno na figuro na plošči, da
# igralec vidi katera bližnjica (1-0) pripada kateri figuri tudi med potezo,
# ne le v roster/aktivni vrstici. Značka je otrok figure, zato se avtomatsko
# premika/izgine z njo - ustvarimo jo samo enkrat, nato le posodabljamo besedilo.
# node_name/offset ločita to značko od DRUGIH značk na isti figuri (glej
# _set_stun_badge spodaj) - brez tega bi si npr. slot številka in "STUN" delili
# isto vozlišče in se prepisovali.
func _set_named_badge(character: BaseCharacter, node_name: String, text: String,
		color: Color = Color(1, 1, 1, 0.65), badge_offset: Vector2 = Vector2(2, 2)):
	if not is_instance_valid(character):
		return
	var badge := character.get_node_or_null(node_name) as Label
	if badge == null:
		badge = Label.new()
		badge.name = node_name
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size", BADGE_RASTER_FONT_SIZE)
		badge.add_theme_color_override("font_color", color)
		badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
		badge.add_theme_constant_override("shadow_offset_x", 1)
		badge.add_theme_constant_override("shadow_offset_y", 1)
		badge.z_index = 5
		character.add_child(badge)

		# Koren posamezne figure ima RAZLIČEN scale na figuro (glej npr.
		# rook.tscn 0.05 proti pawn.tscn 0.08 - vsaka slika je tako
		# normalizirana na isto vizualno velikost). Značka je otrok korena,
		# zato bi podedovala ta scale in bila za vsako figuro drugače velika/
		# pomaknjena - kompenziramo z obratnim scale-om, da je značka enake
		# velikosti in na enakem mestu (v "svet" enotah) za vse figure.
		# Dodatno delimo z BADGE_RASTER_BOOST (glej opombo zgoraj) - size je
		# zato pomnožen z istim faktorjem navzgor, da se v lokalnem
		# (rasterskem) prostoru sklada z večjim font_size.
		var inv_scale := Vector2.ONE / character.scale
		badge.scale = inv_scale / BADGE_RASTER_BOOST
		badge.size = Vector2(10, 8) * BADGE_RASTER_BOOST
		badge.position = badge_offset * inv_scale

	badge.text = text
	badge.visible = text != ""


# Ohranjen obstoječi klicni vmesnik (slot številke, bounty/courier značke) -
# vsi ti si delijo "SlotBadge" vozlišče kot doslej.
func _set_board_badge(character: BaseCharacter, text: String):
	_set_named_badge(character, "SlotBadge", text)


# STUN/ROOT/FROZEN značke na figuri: IKONA (StatusIconBadge), ne besedilo -
# glej status_icon_badge.gd za razlog (BADGE_RASTER_* besedilni trik zgoraj
# se je pri "STUN"/"ROOT"/"FROZE" občasno popačil/obrezal, še posebej ob
# premikanju figure; podroben tekst je itak viden v detajlnem panelu). Isti
# vzorec kompenzacije scale-a kot _set_named_badge, a brez rasterize hacka.
func _set_status_icon(character: BaseCharacter, node_name: String, active: bool,
		color: Color, badge_offset: Vector2):
	if not is_instance_valid(character):
		return
	var badge := character.get_node_or_null(node_name) as StatusIconBadge
	if badge == null:
		badge = StatusIconBadge.new()
		badge.name = node_name
		badge.z_index = 5
		character.add_child(badge)

		var inv_scale := Vector2.ONE / character.scale
		badge.scale = inv_scale
		badge.position = badge_offset * inv_scale

	badge.set_active(active, color)


# Prekletstvo "stunning_gaze": ločena značka ("StunBadge", zamaknjena desno
# navzdol), da se ne prepisuje s slot številko/bounty/courier značko na isti
# figuri.
func _set_stun_badge(character: BaseCharacter, stunned: bool):
	_set_status_icon(character, "StunBadge", stunned, STATUS_STUNNED_COLOR, Vector2(2, 9))


# Prekletstvo "stunning_gaze": character je bil PRAVKAR omamljen (sproženo iz
# BattleController.piece_stunned, glej _ready). Takoj osveži značko na plošči
# in, če je ta figura trenutno prikazana v detail panelu, tudi njega.
func _on_piece_stunned(character):
	_set_stun_badge(character, true)
	if is_instance_valid(character) and character == _shown_character:
		_show_character(character)


# Prekletstvo "stunning_gaze": ob vsakem vstopu v igralčevo potezo preberemo
# dejansko stunned_turns stanje vsake žive zavezniške figure na plošči in
# postavimo/skrijemo njeno značko - zanesljivejše od zgolj poslušanja
# piece_stunned (ki se sproži samo ob NASTAVITVI, ne ob odštevanju na 0).
func _refresh_stun_badges():
	if not is_instance_valid(grid_manager):
		return
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter) or character.is_enemy or character.is_obstacle:
			continue
		_set_stun_badge(character, character.stunned_turns > 0)


# Prekletstvo "entangle": ločena značka ("RootBadge", zamaknjena POD
# StunBadge - Vector2(2, 9) - da se figura, ki bi bila hkrati omamljena IN
# ukoreninjena, ne bi izgubila ene od dveh značk).
func _set_root_badge(character: BaseCharacter, rooted: bool):
	_set_status_icon(character, "RootBadge", rooted, STATUS_ROOTED_COLOR, Vector2(2, 17))


# Prekletstvo "entangle": character je bil pravkar ukoreninjen (sproženo iz
# BattleController.piece_rooted, glej _ready). Takoj osveži značko na plošči
# in, če je ta figura trenutno prikazana v detail panelu, tudi njega.
func _on_piece_rooted(character):
	_set_root_badge(character, true)
	if is_instance_valid(character) and character == _shown_character:
		_show_character(character)


# Prekletstvo "entangle": enak razlog kot _refresh_stun_badges zgoraj -
# rooted_turns se odšteje v BattleController.end_player_turn, ne prek signala.
func _refresh_root_badges():
	if not is_instance_valid(grid_manager):
		return
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter) or character.is_enemy or character.is_obstacle:
			continue
		_set_root_badge(character, character.rooted_turns > 0)


# Snow rework: ločena značka ("FrozenBadge", zamaknjena POD RootBadge -
# Vector2(2, 17) - da se figura, ki je hkrati ROOTED IN FROZEN, ne izgubi
# nobene od značk (glej RootBadge komentar zgoraj za isti vzorec).
func _set_frozen_badge(character: BaseCharacter, frozen: bool):
	_set_status_icon(character, "FrozenBadge", frozen, STATUS_FROZEN_COLOR, Vector2(2, 25))


# Snow rework: character je bil pravkar zamrznjen (sproženo iz
# BattleController.piece_frozen, glej _ready). Takoj osveži značko na plošči
# in, če je ta figura trenutno prikazana v detail panelu, tudi njega.
func _on_piece_frozen(character):
	_set_frozen_badge(character, true)
	if is_instance_valid(character) and character == _shown_character:
		_show_character(character)


# Snow rework: enak razlog kot _refresh_stun_badges/_refresh_root_badges
# zgoraj, PLUS klic is_snow_frozen_now() namesto gole "snow_frozen" branja -
# to je hkrati mesto, ki odmrzne "postano" stanje (obroč snega se je vmes
# prekinil), preden se karkoli prikaže.
func _refresh_frozen_badges():
	if not is_instance_valid(grid_manager):
		return
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter) or character.is_obstacle:
			continue
		# Wave 2 items: effect_frozen_turns velja tudi za sovražnike (snow_frozen
		# ne - glej is_snow_frozen_now/_update_snow_freeze_states, ki ga
		# omejujeta na zaveznike), zato se je_enemy veja tu prvič pojavi.
		if character.is_enemy:
			_set_frozen_badge(character, character.effect_frozen_turns > 0)
		else:
			_set_frozen_badge(character, character.is_snow_frozen_now() or character.effect_frozen_turns > 0)


# Item "marked_man" (Phase 5b, Phase 0 §0.3's deferred marked-vision slot):
# separate icon offset (Vector2(2, 33), below FrozenBadge) so a marked enemy
# that's ALSO frozen/rooted/stunned doesn't lose any badge - same stacking
# pattern as Stun/Root/Frozen above. ENEMY-only (marked_by_vision_item is
# never set on an ally).
func _set_marked_badge(character: BaseCharacter, marked: bool):
	_set_status_icon(character, "MarkedBadge", marked, STATUS_MARKED_COLOR, Vector2(2, 33))


# Called on entering PLAYER_TURN (like the other _refresh_* badges) AND right
# after any consumable use (night_watch/seers_horn set the flag immediately
# on use, not on a turn boundary - see use_item()'s generic consumable path).
func _refresh_marked_badges():
	if not is_instance_valid(grid_manager):
		return
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter) or not character.is_enemy or character.is_obstacle:
			continue
		_set_marked_badge(character, character.marked_by_vision_item)


const STATUS_WAR_COUNCIL_COLOR := Color(1.0, 0.9, 0.4, 0.85)

# Item "war_council": prikaže vrstni red (1, 2, 3, ...), v katerem bo
# BattleController.start_enemy_turn() dejansko obravnaval sovražnike TA
# prihajajoča poteza - deli battle_controller.enemy_turn_order() z dejansko
# izvedbo (eno mesto resnice, glej tam), zato predogled ne more zaiti iz
# koraka. Osveži se samo ob vstopu v igralčevo potezo (glej
# _on_battle_state_changed) - znotraj poteze se vrstni red ne spreminja razen
# če igralec zajame sovražnika, kar samo izbriše njegovo značko (queue_free
# jo pobere skupaj s figuro), preostale številke ostanejo kot so bile
# izračunane (manjša kozmetična "luknja" v zaporedju, sprejemljivo - relativni
# vrstni red preostalih ostane pravilen).
func _refresh_war_council_badges():
	if not is_instance_valid(grid_manager) or not is_instance_valid(battle_controller):
		return
	var order: Array = battle_controller.enemy_turn_order() if player_manager.has_passive("war_council") else []
	var order_index: Dictionary = {}
	for i in range(order.size()):
		order_index[order[i]] = i + 1
	for character in grid_manager.get_all_characters():
		if not is_instance_valid(character):
			continue
		if not (character is BaseCharacter) or not character.is_enemy or character.is_obstacle:
			continue
		var n: int = order_index.get(character, 0)
		_set_named_badge(character, "OrderBadge", str(n) if n > 0 else "",
			STATUS_WAR_COUNCIL_COLOR, Vector2(2, 33))


# ===============================================
# VRSTICI Z IKONAMI (roster + aktivne)
# ===============================================

func _rebuild_rows():
	for child in roster_row.get_children():
		child.queue_free()
	for child in active_row.get_children():
		child.queue_free()

	# Žive zavezniške figure na plošči, razvrščene po tipu rosterja.
	var alive_by_type: Dictionary = {}
	for character in _placed_characters():
		var roster_name: String = "friendly_" + character.strName
		if not alive_by_type.has(roster_name):
			alive_by_type[roster_name] = []
		alive_by_type[roster_name].append(character)

	# _placed_characters() vrsti red izhaja iz grid_managerjevega "occupied"
	# slovarja (ključ = grid_pos) - premik figure jo vacate/occupy prestavi na
	# konec vrstnega reda vstavljanja, čeprav gre za isto figuro. Če je istega
	# tipa na plošči več figur, bi to zamenjalo njihove dodeljene bližnjice
	# (glej pop_front spodaj). Sortiramo po get_instance_id() (stabilen za
	# celo življenjsko dobo figure, se ne spremeni ob premiku) namesto po
	# trenutnem vrstnem redu v "occupied".
	for roster_name in alive_by_type.keys():
		alive_by_type[roster_name].sort_custom(
			func(a, b): return a.get_instance_id() < b.get_instance_id()
		)

	# Število mrtvih po tipu (za razločevanje mrtev/na klopi).
	var dead_counts: Dictionary = {}
	for dead_name in player_manager.dead_party:
		dead_counts[dead_name] = dead_counts.get(dead_name, 0) + 1

	# RDEČA VRSTICA: celoten roster. Vsakemu vnosu poskusimo dodeliti živo
	# figuro istega tipa - vnosi brez nje so mrtvi (sivi) ali na klopi.
	# Dodelitve si zapomnimo, da roza vrstico zgradimo iz istih podatkov
	# (ne iz otrok roster_row - tam so ob rebuildu še stari, queue_free
	# čakajoči otroci).
	var assignments: Array = []
	for i in player_manager.friendly_party.size():
		var roster_name: String = player_manager.friendly_party[i]
		var slot_text := _slot_label_text(i)
		var assigned: BaseCharacter = null
		if alive_by_type.has(roster_name) and not alive_by_type[roster_name].is_empty():
			assigned = alive_by_type[roster_name].pop_front()
		assignments.append([roster_name, assigned])

		var icon := PieceIcon.new()
		icon.setup(roster_name, assigned)
		icon.set_slot_label(slot_text)
		if assigned == null:
			if dead_counts.get(roster_name, 0) > 0:
				dead_counts[roster_name] -= 1
				icon.set_dead(true)
			elif not placement_active:
				# Živa, a ni bila postavljena v to bitko.
				icon.set_benched(true)
		else:
			# Že postavljena na ploščo - rahlo posivimo, da je jasno,
			# katera figura je bila že izbrana.
			icon.set_placed(true)
			# Ista značka (tipka za izbiro) se prikaže tudi na sami figuri
			# na plošči, da igralec vidi katera bližnjica pripada kateri figuri.
			_set_board_badge(assigned, slot_text)
		icon.icon_clicked.connect(_on_icon_clicked)
		roster_row.add_child(icon)

	# ROZA VRSTICA: aktivne figure (žive na plošči). Med placementom se polni
	# sproti, ko igralec postavlja figure.
	for i in assignments.size():
		var assignment = assignments[i]
		if is_instance_valid(assignment[1]):
			var icon := PieceIcon.new()
			icon.setup(assignment[0], assignment[1])
			icon.set_slot_label(_slot_label_text(i))
			icon.icon_clicked.connect(_on_icon_clicked)
			active_row.add_child(icon)

	_highlight_selected(map_behaviour.selected_character)


func _on_icon_clicked(icon: PieceIcon):
	if dragging:
		# Drag že teče (npr. druga ikona ali plošča) - prezri, dokler se ne
		# razreši z izpustom miške (_resolve_drop). Brez tega bi nov klik med
		# vlečenjem prepisal drag_source_character in prvo figuro pustil
		# napol prosojno (modulate.a=0.4) za vedno.
		return
	if placement_active:
		if is_instance_valid(icon.character):
			# Že postavljena: začni drag za premik/odstranitev.
			_begin_drag(icon.piece_name, icon.character)
		elif not icon.is_dead and _placed_characters().size() < _max_placeable():
			# Na klopi in še je prostor: začni drag za postavitev.
			_begin_drag(icon.piece_name, null)
		else:
			_show_piece_for_icon(icon)
		return

	if is_instance_valid(icon.character):
		# Živa figura: izberi jo na plošči (enaka pot kot klik na figuro).
		# Med sovražnikovo potezo izbira ni mogoča - pokažemo samo podrobnosti.
		map_behaviour.select_character_via_ui(icon.character)
		if not battle_controller.can_select():
			_show_piece_for_icon(icon)
	else:
		_show_piece_for_icon(icon)


func _show_piece_for_icon(icon: PieceIcon):
	if icon.is_dead:
		_show_dead_piece(icon.piece_name)
	elif is_instance_valid(icon.character):
		_show_character(icon.character)
	else:
		_show_benched_piece(icon.piece_name)
	_highlight_icon_only(icon)


# ===============================================
# DETAIL PANEL (izbrana figura)
# ===============================================

func _on_selection_changed(character):
	# Selekcija VEDNO zapre itemsko mrežo (glej
	# BATTLE_UI_CONTEXTUAL_PANEL_PLAN.md §3.3) - igralec jo mora po tem
	# eksplicitno spet odpreti.
	_item_view_open = false
	if is_instance_valid(character) and character is BaseCharacter:
		_show_character(character)
	else:
		_clear_detail_panel()
	_highlight_selected(character)


func _show_character(character: BaseCharacter):
	portrait.visible = true
	status_header.visible = true
	status_value.visible = true
	portrait.texture = load("res://Assets/Sprites/friendly_%s.png" % character.strName)
	# Prekletstvo "stunning_gaze"/"entangle" + snow rework "FROZEN": prizadeta
	# zavezniška figura kaže STUNNED/FROZEN/ROOTED namesto ALIVE (glej
	# stunned_turns/rooted_turns tick-down v BattleController.end_player_turn
	# in is_snow_frozen_now() za FROZEN). Prioriteta STUNNED > FROZEN > ROOTED -
	# FROZEN pomeni popolnoma onesposobljeno gibanje, "hujše" stanje od ROOTED
	# (ki še dovoli zajetja), a STUNNED onemogoča tudi sposobnosti.
	if character.stunned_turns > 0:
		status_value.text = "STUNNED"
		status_value.add_theme_color_override("font_color", STATUS_STUNNED_COLOR)
	elif character.is_snow_frozen_now() or character.effect_frozen_turns > 0:
		status_value.text = "FROZEN"
		status_value.add_theme_color_override("font_color", STATUS_FROZEN_COLOR)
	elif character.rooted_turns > 0:
		status_value.text = "ROOTED"
		status_value.add_theme_color_override("font_color", STATUS_ROOTED_COLOR)
	else:
		status_value.text = "ALIVE"
		status_value.add_theme_color_override("font_color", STATUS_ALIVE_COLOR)
	_hide_ability_bubble()
	_shown_character = character
	_show_abilities(character)


# Inšpekcija sovražnika (map_behaviour.enemy_inspected - klik na sovražnika,
# ko ni izbrana nobena zavezniška figura). Display-only: portret + status
# ("CURSED: <ime>" v barvi prekletstva, ali navaden "ENEMY") - prekletstvo se
# prikaže v ločenem, vedno vidnem CurseBlock (glej
# BATTLE_UI_CONTEXTUAL_PANEL_PLAN.md), ne v vrsticah sposobnosti (enemy figure
# nimajo pravih sposobnosti, get_ability_defs() je prazen).
func _show_enemy(character: BaseCharacter):
	if not is_instance_valid(character):
		return
	_item_view_open = false
	portrait.visible = true
	status_header.visible = true
	status_value.visible = true
	portrait.texture = load("res://Assets/Sprites/enemy_%s.png" % character.strName)
	_shown_character = character
	_clear_ability_rows()
	# Wave 2 items (frost_nova, stormcaller, ...): effect_frozen_turns lahko
	# zamrzne sovražnika - prednost pred prekletstvom, saj onemogoča gibanje
	# ne glede na to.
	if character.effect_frozen_turns > 0:
		status_value.text = "FROZEN"
		status_value.add_theme_color_override("font_color", STATUS_FROZEN_COLOR)
	elif character.curse:
		status_value.text = character.curse.status_text()
		status_value.add_theme_color_override("font_color", character.curse.color())
		curse_name_label.text = character.curse.display_name()
		curse_explanation_label.text = character.curse.description()
		curse_block.visible = true
	else:
		status_value.text = "ENEMY"
		status_value.add_theme_color_override("font_color", STATUS_DEAD_COLOR)
	# Item "marked_man"/night_watch/seers_horn: orthogonal to frozen/curse/plain
	# above (an enemy can be marked AND cursed at once, see the board's own
	# MarkedBadge which stacks independently) - append rather than branch.
	if character.marked_by_vision_item:
		status_value.text += " • MARKED"
	_refresh_shared_area()


func _show_dead_piece(piece_name: String):
	_item_view_open = false
	portrait.visible = true
	status_header.visible = true
	status_value.visible = true
	portrait.texture = load("res://Assets/Sprites/%s.png" % piece_name)
	status_value.text = "DEAD"
	status_value.add_theme_color_override("font_color", STATUS_DEAD_COLOR)
	_shown_character = null
	_clear_ability_rows()


func _show_benched_piece(piece_name: String):
	_item_view_open = false
	portrait.visible = true
	status_header.visible = true
	status_value.visible = true
	portrait.texture = load("res://Assets/Sprites/%s.png" % piece_name)
	status_value.text = "NOT PLACED"
	status_value.add_theme_color_override("font_color", STATUS_BENCHED_COLOR)
	_shown_character = null
	_clear_ability_rows()


func _clear_detail_panel():
	_item_view_open = false
	# Hover-inšpekcija sovražnika (map_behaviour.enemy_inspection_cleared) lahko
	# pokliče to funkcijo tudi, ko je zavezniška figura ŠE VEDNO izbrana (glej
	# map_behaviour._update_hover - hover sovražnika zdaj dovoljen tudi med
	# izbiro) - v tem primeru obnovimo njen panel namesto da ga počistimo na
	# "nič". Prava deselekcija (_on_selection_changed(null)) ima do te točke
	# selected_character že nastavljen na null (glej
	# map_behaviour._clear_selection), zato spodnji pogoj tam pravilno ne drži.
	if is_instance_valid(map_behaviour.selected_character):
		_show_character(map_behaviour.selected_character)
		return
	# Res nič izbrano/inšpicirano - skrijemo tudi portret/STATUS, ne le vrstice
	# sposobnosti/CurseBlock (glej _clear_ability_rows), da se panel res
	# povsem izprazni namesto da kaže prazen portret + "STATUS -".
	portrait.visible = false
	status_header.visible = false
	status_value.visible = false
	portrait.texture = null
	status_value.text = "-"
	status_value.remove_theme_color_override("font_color")
	_shown_character = null
	_clear_ability_rows()


func _clear_ability_rows():
	for w in _ability_slot_widgets().values():
		w.icon.modulate = ABILITY_ICON_LOCKED_TINT
		w.name.text = "-"
		w.level.text = ""
		w.uses.text = ""
		w.button.disabled = true
		w.button.text = ABILITY_BUTTON_TEXT_UNLOCKED
		w.button.mouse_filter = Control.MOUSE_FILTER_STOP
		w.row.visible = false
	hsep1.visible = false
	hsep2.visible = false
	hsep3.visible = false
	curse_block.visible = false
	for slot in [1, 2, 3]:
		_slot_bubble_state[slot] = ""
	_hide_ability_bubble()
	_refresh_shared_area()


# "LV n" ali "LV MAX", ko je figura na najvišji stopnji (glej
# BaseCharacter.get_ability_info - level/level_max).
func _level_text(info: Dictionary) -> String:
	var level: int = info.get("level", 1)
	var level_max: int = info.get("level_max", 1)
	return "LV MAX" if level >= level_max else "LV %d" % level


# Zbere node reference vseh treh vrstic sposobnosti v en slovar (slot -> par
# widgetov), da jih _show_abilities()/_clear_ability_rows() lahko obdelata v
# isti zanki namesto s podvojeno kodo na slot.
func _ability_slot_widgets() -> Dictionary:
	return {
		1: {"row": ability1_row, "icon": ability1_icon, "name": ability1_name,
			"level": ability1_level, "uses": ability1_uses, "button": ability1_button},
		2: {"row": ability2_row, "icon": ability2_icon, "name": ability2_name,
			"level": ability2_level, "uses": ability2_uses, "button": ability2_button},
		3: {"row": ability3_row, "icon": ability3_icon, "name": ability3_name,
			"level": ability3_level, "uses": ability3_uses, "button": ability3_button},
	}


# Ime slota v besedilu "locked" sporočila ("second"/"third" - slot 1 nikoli ni
# zaklenjen, glej is_slot_unlocked spodaj).
const _SLOT_ORDINAL := {2: "second", 3: "third"}


# Napolni vse tri vrstice sposobnosti iz character.get_ability_info(slot) in
# nastavi gumbe glede na to, ali jih igralec sme trenutno uporabiti. Slot 1 je
# strukturno vedno "unlocked" (is_slot_unlocked(1) je unconditionally true v
# base_character.gd), zato zanka spodaj brez posebnega primera pokrije vse 3
# slote - locked veja preprosto nikoli ne sproži za slot 1.
func _show_abilities(character: BaseCharacter):
	for w in _ability_slot_widgets().values():
		w.row.visible = true
	hsep1.visible = true
	hsep2.visible = true
	hsep3.visible = true
	curse_block.visible = false

	var can_use_now: bool = (
		not character.is_enemy
		and not character.is_obstacle
		and battle_controller.can_use_ability()
		and map_behaviour.pending_ability.is_empty()
	)

	var slot_widgets := _ability_slot_widgets()
	for slot in [1, 2, 3]:
		var w: Dictionary = slot_widgets[slot]
		if character.is_slot_unlocked(slot):
			var info := character.get_ability_info(slot)
			w.icon.modulate = ABILITY_ICON_UNLOCKED_TINT
			w.name.text = info.get("name", "-")
			w.level.text = _level_text(info)
			w.uses.text = "%d/%d" % [info.get("uses_remaining", 0), info.get("uses_max", 0)]
			w.button.disabled = not (can_use_now and info.get("uses_remaining", 0) > 0)
			w.button.text = ABILITY_BUTTON_TEXT_UNLOCKED
			_slot_bubble_state[slot] = info.get("desc", "")
		else:
			# Cena odklepa pride iz skill drevesa (aN_unlock vozlišče tega
			# tipa), ne iz get_ability_info - glej SKILL_TREE_PLAN.md §5.1.
			var unlock_def: Dictionary = skill_tree_data.get_node_def(character.strName, "a%d_unlock" % slot)
			var unlock_cost: int = unlock_def.get("cost", 1)
			w.icon.modulate = ABILITY_ICON_LOCKED_TINT
			w.name.text = "???"
			w.level.text = ""
			w.uses.text = ""
			w.button.disabled = true
			w.button.text = ABILITY_BUTTON_TEXT_LOCKED
			var locked_text := "Use %d upgrade item%s at a rest to unlock the %s ability." % [
				unlock_cost, "" if unlock_cost == 1 else "s", _SLOT_ORDINAL[slot]
			]
			# "requires" is empty for every a2_unlock node but names a passive
			# for every a3_unlock node - read dynamically instead of hardcoding
			# "only slot 3" so a future balance pass can't silently desync this.
			var passive_names: Array[String] = []
			for req_id in unlock_def.get("requires", []):
				passive_names.append(skill_tree_data.get_node_def(character.strName, req_id).get("name", req_id))
			if not passive_names.is_empty():
				locked_text += " Also requires the %s passive." % ", ".join(passive_names)
			_slot_bubble_state[slot] = locked_text
	_refresh_shared_area()


func _on_ability_pressed(slot: int):
	if not is_instance_valid(_shown_character):
		return
	# Lokalna referenca: begin_ability_targeting() spodaj interno pokliče
	# map_behaviour._clear_selection(), ki sproži selection_changed(null) in
	# SINHRONO počisti _shown_character (glej _on_selection_changed) - torej
	# ga po tej točki ne smemo več brati, samo character lokalno.
	var character := _shown_character
	var targets := character.get_ability_targets(slot)
	if targets.is_empty():
		var ok: bool = character.activate_ability(slot)
		if ok:
			# Sposobnost porabi 1 iz LOČENEGA proračuna sposobnosti (ne
			# premikov) - poteza se ne konča sama (glej
			# BattleController.consume_ability()).
			battle_controller.consume_ability()
			battle_controller.check_battle_end()
			_show_abilities(character)
	else:
		map_behaviour.begin_ability_targeting(character, slot)
		# Ponovno pokažemo detail panel za TO figuro, ker ga je klic zgoraj
		# ravnokar počistil (glej opombo pri "character" zgoraj) - med
		# ciljanjem naj panel še vedno kaže figuro/sposobnost, ki čaka na klik.
		_shown_character = character
		_show_abilities(character)


func _on_ability_activated(character: BaseCharacter):
	if character == _shown_character:
		_show_abilities(character)


# ===============================================
# ABILITY BUBBLE (hover/click opis, glej BATTLE_UI_ABILITY_PANEL_PLAN.md)
# ===============================================

# Prikaže bubble ob `anchor_row`, oblečen/pomaknjen tako, da nikoli ne pade
# izven vidnega področja. Odpira se prednostno levo+navzgor od vrstice, ker
# SidePanel zaseda desnih ~42% zaslona (anchor_left=0.58 zgoraj) - levo je
# torej praviloma več prostora proti plošči.
func _show_ability_bubble(anchor_row: Control, text: String) -> void:
	if text == "":
		_hide_ability_bubble()
		return

	ability_bubble_label.text = text
	ability_bubble.visible = true
	# Ročno pozicioniran PanelContainer (layout_mode=0) se ne re-sizea sam iz
	# frame v frame - brez tega klica bi obdržal velikost prejšnjega besedila.
	ability_bubble.reset_size()

	var row_rect := anchor_row.get_global_rect()
	var viewport_size := get_viewport().get_visible_rect().size
	var bubble_size := ability_bubble.size

	var desired := row_rect.position - bubble_size - Vector2(ABILITY_BUBBLE_MARGIN, ABILITY_BUBBLE_MARGIN)
	var clamped := Vector2(
		clampf(desired.x, ABILITY_BUBBLE_MARGIN, viewport_size.x - bubble_size.x - ABILITY_BUBBLE_MARGIN),
		clampf(desired.y, ABILITY_BUBBLE_MARGIN, viewport_size.y - bubble_size.y - ABILITY_BUBBLE_MARGIN)
	)
	ability_bubble.global_position = clamped


func _hide_ability_bubble() -> void:
	ability_bubble.visible = false


# Hover razkrije bubble za VSAK slot enako, ne glede na locked/unlocked -
# locked prikaže unlock-cost besedilo, unlocked prikaže opis sposobnosti.
func _on_ability_row_mouse_entered(slot: int, row: Control) -> void:
	var text: String = _slot_bubble_state.get(slot, "")
	if text != "":
		_show_ability_bubble(row, text)


# ===============================================
# POUDARJANJE IKON
# ===============================================

func _highlight_selected(character):
	for row in [roster_row, active_row]:
		for icon in row.get_children():
			if icon is PieceIcon:
				icon.set_highlighted(
					is_instance_valid(character) and icon.character == character
				)


# Poudari samo kliknjeno ikono (mrtva/na klopi - na plošči ni izbire).
func _highlight_icon_only(target: PieceIcon):
	for row in [roster_row, active_row]:
		for icon in row.get_children():
			if icon is PieceIcon:
				icon.set_highlighted(icon == target)


# ===============================================
# ITEMI IN OSVEŽEVANJE
# ===============================================

func _update_item_counts():
	upgrade_count_label.text = "x%d" % player_manager.upgrade_items
	revive_count_label.text = "x%d" % player_manager.revive_items


# ===============================================
# SKUPNO PODROČJE (DetailPanel <-> ItemGridPanel, glej
# BATTLE_UI_CONTEXTUAL_PANEL_PLAN.md §3.2)
# ===============================================

# EDINO mesto, ki odloča o vidnosti DetailPanel/ItemGridPanel - vrstice
# sposobnosti/CurseBlock znotraj DetailPanela so že odločene v
# _clear_ability_rows()/_show_abilities()/_show_enemy() PREDEN te pokličejo to
# funkcijo, zato tu ni treba podvajati tiste logike.
func _refresh_shared_area():
	item_grid_panel.visible = _item_view_open
	detail_panel.visible = not _item_view_open


func _on_item_toggle_pressed():
	_item_view_open = not _item_view_open
	_refresh_shared_area()
	if _item_view_open:
		_rebuild_item_grid()


func _rebuild_item_grid():
	# items_changed fires on every item pickup/use during battle regardless of
	# whether this grid is even visible - skip the rebuild while closed.
	# _on_item_toggle_pressed() already rebuilds explicitly on open (it sets
	# _item_view_open true before calling this), so state is never stale.
	if not _item_view_open:
		return

	for child in item_grid.get_children():
		child.queue_free()

	var ids: Array = player_manager.owned_items.keys()
	var any_shown := false
	for id in ids:
		var count: int = player_manager.owned_items[id]
		if count <= 0:
			continue
		item_grid.add_child(_build_item_icon(id, count))
		any_shown = true

	# Item "trail_rations": consumable-i porabljeni do 0 TO bitko ostanejo
	# vidni kot "0x" duh-ikona (ne vlečljiva) dokler bitka ne konča (glej
	# PlayerManager.used_up_this_battle).
	for id in player_manager.used_up_this_battle:
		item_grid.add_child(_build_item_icon(id, 0))
		any_shown = true

	if not any_shown:
		var empty := Label.new()
		empty.text = "NO ITEMS"
		item_grid.add_child(empty)


func _build_item_icon(id: String, count: int) -> PieceIcon:
	var is_passive: bool = ItemData.get_kind(id) == "passive"
	# Artefakt "frozen_rampart"/"drillmaster": enkratna uporaba na bitko, ki se
	# ne porabi iz inventarja (glej use_item() poseben primer spodaj) - ko je
	# že porabljena, ikona ni več vlečljiva do naslednje bitke.
	var frozen_rampart_used: bool = id == "frozen_rampart" and battle_controller.frozen_rampart_used_this_battle
	var drillmaster_used: bool = id == "drillmaster" and battle_controller.drillmaster_used_this_battle
	var winter_general_used: bool = id == "winter_general" and battle_controller.winter_general_used_this_battle
	var winters_bargain_used: bool = id == "winters_bargain" and battle_controller.winters_bargain_used_this_battle
	var throne_of_frost_used: bool = id == "throne_of_frost" and battle_controller.throne_of_frost_used_this_battle
	var once_per_battle_used: bool = frozen_rampart_used or drillmaster_used or winter_general_used or winters_bargain_used or throne_of_frost_used
	# Item "trail_rations": "0x" duh-ikona za consumable-e porabljene do 0 to
	# bitko (glej _rebuild_item_grid) - ni vlečljiva dokler je ne povrne
	# trail_rations ali se bitka konča.
	var is_used_up: bool = count <= 0 and ItemData.get_kind(id) == "consumable"
	var draggable: bool = not is_passive and not once_per_battle_used and not is_used_up

	var icon := PieceIcon.new()
	icon.setup("item_%s" % id, null)
	# Larger than the roster/active rows' 40x40 default - items need to read
	# clearly at a glance in the grid, matches the panel's existing 64x64
	# ability icons.
	icon.custom_minimum_size = Vector2(64, 64)
	icon.set_slot_label(str(count))
	icon.set_benched(not draggable)

	var status_suffix: String
	if is_passive:
		status_suffix = "Passive"
	elif once_per_battle_used or is_used_up:
		status_suffix = "Already used this battle"
	else:
		status_suffix = "x%d owned" % count
	var bubble_text := "%s\n%s\n%s" % [
		ItemData.get_item_name(id), ItemData.get_item_description(id), status_suffix
	]
	icon.mouse_entered.connect(_show_ability_bubble.bind(icon, bubble_text))
	icon.mouse_exited.connect(_hide_ability_bubble)

	if draggable:
		icon.icon_clicked.connect(_on_item_icon_clicked.bind(id))

	return icon


# Klik na ikono itema med igralčevo potezo začne drag (placement faza je
# izključena - gumb za itemsko mrežo je takrat itak onemogočen, glej
# _on_battle_state_changed). Samo draggable ikone (glej _build_item_icon) sploh
# povežejo icon_clicked na to funkcijo.
func _on_item_icon_clicked(_icon: PieceIcon, id: String):
	if dragging or dragging_item:
		return
	if battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return
	dragging_item = true
	drag_item_id = id
	drag_ghost.texture = load("res://Assets/Sprites/item_%s.png" % id)
	drag_ghost.position = get_viewport().get_mouse_position() - drag_ghost.size / 2
	drag_ghost.visible = true


# Wave 2 items: dokler vlečemo item nad ploščo, predogledamo njegova ciljna
# polja (glej BaseItem.get_aim_cells) pod kazalcem - izven plošče/brez veljavnega
# itema se predogled počisti.
func _update_item_aim(screen_pos: Vector2) -> void:
	if not is_instance_valid(move_highlighter):
		return
	if not board_area.get_global_rect().has_point(screen_pos):
		move_highlighter.clear_aim()
		return
	var item: BaseItem = ItemData.create_item(drag_item_id)
	if item == null:
		move_highlighter.clear_aim()
		return
	var grid_pos := _screen_to_grid(screen_pos)
	move_highlighter.show_aim(item.get_aim_cells(grid_pos))


# Spuščeno izven plošče (BoardArea) = no-op, item ostane v inventarju.
func _resolve_item_drop(screen_pos: Vector2):
	dragging_item = false
	drag_ghost.visible = false
	if is_instance_valid(move_highlighter):
		move_highlighter.clear_aim()

	if board_area.get_global_rect().has_point(screen_pos):
		var grid_pos := _screen_to_grid(screen_pos)
		use_item(drag_item_id, grid_pos)

	drag_item_id = ""


# Dejanska uporaba itema - ločena od _resolve_item_drop, da jo lahko smoke
# test pokliče neposredno (isti vzorec kot place_piece/move_placed_piece).
# Vrne true, če je bil item uporabljen in porabljen iz inventarja.
func use_item(id: String, grid_pos: Vector2i) -> bool:
	# Artefakt "frozen_rampart": edini artefakt, ki je trenutno vlečljiv na
	# ploščo - ne porabi se iz inventarja (kot navaden consumable), ampak je
	# omejen na 1x na bitko prek battle_controller.frozen_rampart_used_this_battle.
	if id == "frozen_rampart":
		if not player_manager.has_passive("frozen_rampart") or battle_controller.frozen_rampart_used_this_battle:
			return false
		var rampart: BaseItem = ItemData.create_item(id)
		if rampart == null or not (rampart.can_use(battle_controller, grid_pos) and rampart.apply(battle_controller, grid_pos)):
			return false
		battle_controller.frozen_rampart_used_this_battle = true
		_rebuild_item_grid() # ne sproži items_changed (ni bilo porabljeno iz inventarja)
		UiAudio.play_click()
		return true

	# Artefakt "drillmaster": enak "1x na bitko, ne porabi se iz inventarja"
	# vzorec kot frozen_rampart zgoraj. Swap potrebuje DVE tarči: figura A je
	# trenutno IZBRANA zavezniška figura (map_behaviour.selected_character -
	# normalna izbira na plošči, ista pot kot premik/zajetje), figura B je
	# tista, na katero je bil item spuščen (grid_pos). Logika je NAMERNO tu
	# inline (ne v drillmaster_item.gd.apply()) - BaseItem.apply() ne dobi
	# map_behaviour reference, glej drillmaster_item.gd opombo.
	if id == "drillmaster":
		if not player_manager.has_passive("drillmaster") or battle_controller.drillmaster_used_this_battle:
			return false
		var ally_a: BaseCharacter = map_behaviour.selected_character
		if not (is_instance_valid(ally_a) and not ally_a.is_enemy and not ally_a.is_obstacle):
			return false
		var ally_b = grid_manager.get_character_at(grid_pos)
		if not (ally_b is BaseCharacter and not ally_b.is_enemy and not ally_b.is_obstacle and ally_b != ally_a):
			return false
		grid_manager.swap_characters(ally_a, ally_b)
		battle_controller.drillmaster_used_this_battle = true
		_rebuild_item_grid()
		UiAudio.play_click()
		return true

	# Artefakt "winter_general": isti "1x na bitko, ne porabi se iz
	# inventarja" vzorec kot frozen_rampart/drillmaster zgoraj - a brez
	# ciljne figure/polja (učinek je vedno centriran na igralčevega kralja,
	# glej winter_general_item.gd), zato ni potrebe po inline logiki tu -
	# item skripta sama opravi vse (can_use/apply).
	if id == "winter_general":
		if not player_manager.has_passive("winter_general") or battle_controller.winter_general_used_this_battle:
			return false
		var winter_general: BaseItem = ItemData.create_item(id)
		if winter_general == null or not (winter_general.can_use(battle_controller, grid_pos) and winter_general.apply(battle_controller, grid_pos)):
			return false
		battle_controller.winter_general_used_this_battle = true
		_rebuild_item_grid()
		UiAudio.play_click()
		return true

	# Artefakt "winters_bargain": enak vzorec kot winter_general zgoraj - item
	# skripta sama opravi vse (can_use/apply, glej winters_bargain_item.gd).
	if id == "winters_bargain":
		if not player_manager.has_passive("winters_bargain") or battle_controller.winters_bargain_used_this_battle:
			return false
		var winters_bargain: BaseItem = ItemData.create_item(id)
		if winters_bargain == null or not (winters_bargain.can_use(battle_controller, grid_pos) and winters_bargain.apply(battle_controller, grid_pos)):
			return false
		battle_controller.winters_bargain_used_this_battle = true
		_rebuild_item_grid()
		UiAudio.play_click()
		return true

	# Artefakt "throne_of_frost": isti "1x na bitko, ne porabi se iz
	# inventarja" vzorec kot winter_general/winters_bargain zgoraj.
	if id == "throne_of_frost":
		if not player_manager.has_passive("throne_of_frost") or battle_controller.throne_of_frost_used_this_battle:
			return false
		var throne_of_frost: BaseItem = ItemData.create_item(id)
		if throne_of_frost == null or not (throne_of_frost.can_use(battle_controller, grid_pos) and throne_of_frost.apply(battle_controller, grid_pos)):
			return false
		battle_controller.throne_of_frost_used_this_battle = true
		_rebuild_item_grid()
		UiAudio.play_click()
		return true

	# Item "blink_step": consumable verzija drillmaster-jevega swapa (glej
	# drillmaster opombo zgoraj za razlog, zakaj je logika tu inline) - a
	# porabi se iz inventarja normalno (isti spodnji `remove_item()`), ne
	# "1x na bitko" poseben primer.
	if id == "blink_step":
		if player_manager.get_item_count(id) <= 0:
			return false
		var ally_a: BaseCharacter = map_behaviour.selected_character
		if not (is_instance_valid(ally_a) and not ally_a.is_enemy and not ally_a.is_obstacle):
			return false
		var ally_b = grid_manager.get_character_at(grid_pos)
		if not (ally_b is BaseCharacter and not ally_b.is_enemy and not ally_b.is_obstacle and ally_b != ally_a):
			return false
		grid_manager.swap_characters(ally_a, ally_b)
		player_manager.remove_item(id)
		UiAudio.play_click()
		return true

	if player_manager.get_item_count(id) <= 0:
		return false
	if ItemData.get_kind(id) != "consumable":
		return false # pasivni itemi niso vlečljivi/uporabni (belt and braces; create_item vrne null tudi)
	var item: BaseItem = ItemData.create_item(id)
	if item == null:
		return false
	if not (item.can_use(battle_controller, grid_pos) and item.apply(battle_controller, grid_pos)):
		return false

	player_manager.remove_item(id) # emits items_changed -> _rebuild_item_grid
	UiAudio.play_click()
	# Items "night_watch"/"seers_horn": mark an enemy immediately on use (not
	# on a turn boundary like the other _refresh_* badges) - harmless no-op
	# call for every other consumable.
	_refresh_marked_badges()
	return true


func _on_party_changed():
	# Figura je umrla (ali se je ekipa spremenila) - osvežimo vrstici.
	# call_deferred: die() sproži signal PREDEN queue_free() figuro
	# dejansko odstrani iz grid_managerja snapshot-a.
	_rebuild_rows.call_deferred()
	_update_item_counts()
