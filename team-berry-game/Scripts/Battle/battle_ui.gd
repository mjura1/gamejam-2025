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
# cene ne živijo več v Data/abilities.json, ampak v Data/skill_trees.json.
@onready var skill_tree_data = get_node("/root/SkillTreeData")
@onready var grid_manager = get_node("../GridManager")
@onready var map_behaviour = get_node("../Map")
@onready var battle_controller = get_node("../BattleController")
@onready var placement_highlighter = get_node("../PlacementHighlighter")
# Koren battle scene - battle.gd nosi friendly_pieces slovar (ime -> scena).
@onready var battle_root = get_node("..")

@onready var roster_row: HFlowContainer = %RosterRow
@onready var active_row: HFlowContainer = %ActiveRow
@onready var upgrade_count_label: Label = %UpgradeCount
@onready var revive_count_label: Label = %ReviveCount
@onready var portrait: TextureRect = %Portrait
@onready var status_value: Label = %StatusValue
@onready var ability1_name: Label = %Ability1Name
@onready var ability1_level: Label = %Ability1Level
@onready var ability1_uses: Label = %Ability1Uses
@onready var ability1_desc: Label = %Ability1Desc
@onready var ability1_button: Button = %Ability1Button
@onready var ability2_name: Label = %Ability2Name
@onready var ability2_level: Label = %Ability2Level
@onready var ability2_uses: Label = %Ability2Uses
@onready var ability2_desc: Label = %Ability2Desc
@onready var ability2_button: Button = %Ability2Button
@onready var ability2_body: VBoxContainer = %Ability2Body
@onready var ability2_locked: Label = %Ability2Locked
@onready var ability3_name: Label = %Ability3Name
@onready var ability3_level: Label = %Ability3Level
@onready var ability3_uses: Label = %Ability3Uses
@onready var ability3_desc: Label = %Ability3Desc
@onready var ability3_button: Button = %Ability3Button
@onready var ability3_body: VBoxContainer = %Ability3Body
@onready var ability3_locked: Label = %Ability3Locked
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
@onready var item_drawer: HBoxContainer = %ItemDrawer
@onready var item_panel: PanelContainer = %ItemPanel
@onready var item_rows: VBoxContainer = %ItemRows
@onready var item_toggle_button: Button = %ToggleButton

const STATUS_ALIVE_COLOR := Color(0.5, 1.0, 0.5)
const STATUS_DEAD_COLOR := Color(1.0, 0.4, 0.4)
const STATUS_BENCHED_COLOR := Color(0.75, 0.75, 0.75)
const STATUS_STUNNED_COLOR := Color(0.8, 0.5, 1.0)
const STATUS_ROOTED_COLOR := Color(0.45, 0.65, 0.25)

var placement_active: bool = false

# Stanje drag & dropa med placement fazo. drag_source_character je nastavljen,
# ko premikamo že postavljeno figuro; sicer postavljamo novo iz rosterja.
var dragging: bool = false
var drag_piece_name: String = ""
var drag_source_character: BaseCharacter = null

# Stanje drag & dropa za itemsko predalo (ločeno od figur, da se drag-a ne
# moreta prepletati - glej _input()). item_drawer_open sledi </> gumbu.
var item_drawer_open: bool = false
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
	battle_controller.state_changed.connect(_on_battle_state_changed)
	battle_controller.moves_changed.connect(_on_moves_changed)
	battle_controller.abilities_changed.connect(_on_abilities_changed)
	battle_controller.bounty_marked.connect(func(character): _set_board_badge(character, "☠"))
	battle_controller.courier_marked.connect(func(character): _set_board_badge(character, "C"))
	battle_controller.piece_stunned.connect(_on_piece_stunned)
	battle_controller.piece_rooted.connect(_on_piece_rooted)
	board_area.gui_input.connect(_on_board_area_input)
	action_button.pressed.connect(_on_action_button_pressed)
	auto_fill_button.pressed.connect(_on_auto_fill_pressed)
	remove_all_button.pressed.connect(_on_remove_all_pressed)
	item_toggle_button.pressed.connect(_on_item_toggle_pressed)
	player_manager.items_changed.connect(_rebuild_item_drawer)
	ability1_button.pressed.connect(_on_ability_pressed.bind(1))
	ability2_button.pressed.connect(_on_ability_pressed.bind(2))
	ability3_button.pressed.connect(_on_ability_pressed.bind(3))
	# Preberi rebindane bližnjice v živo (npr. igralec spremeni bind med pavzo
	# sredi bitke) - značke slotov naj se takoj osvežijo.
	KeybindManager.rebinds_changed.connect(_rebuild_rows)

	_update_item_counts()
	_clear_detail_panel()
	_rebuild_item_drawer()

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
	if event.is_action_pressed("toggle_items") and item_drawer.visible:
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
	# Predala za iteme med placementom nima smisla (itemi se uporabljajo na
	# figurah/plošči med bitko) - skrijemo jo, dokler igralec ne potrdi postavitve.
	item_drawer.visible = new_state != battle_controller.BattleState.PLACEMENT

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


func _on_abilities_changed(remaining: int, max_abilities: int):
	abilities_label.text = "ABILITIES: %d/%d" % [remaining, max_abilities]


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
		color: Color = Color(1, 1, 1, 0.65), offset: Vector2 = Vector2(2, 2)):
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
		badge.position = offset * inv_scale

	badge.text = text
	badge.visible = text != ""


# Ohranjen obstoječi klicni vmesnik (slot številke, bounty/courier značke) -
# vsi ti si delijo "SlotBadge" vozlišče kot doslej.
func _set_board_badge(character: BaseCharacter, text: String):
	_set_named_badge(character, "SlotBadge", text)


# Prekletstvo "stunning_gaze": ločena značka ("StunBadge", zamaknjena desno
# navzdol), da se ne prepisuje s slot številko/bounty/courier značko na isti
# figuri.
func _set_stun_badge(character: BaseCharacter, stunned: bool):
	_set_named_badge(character, "StunBadge", "STUN" if stunned else "", STATUS_STUNNED_COLOR, Vector2(2, 9))


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
	_set_named_badge(character, "RootBadge", "ROOT" if rooted else "", STATUS_ROOTED_COLOR, Vector2(2, 17))


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
	if is_instance_valid(character) and character is BaseCharacter:
		_show_character(character)
	else:
		_clear_detail_panel()
	_highlight_selected(character)


func _show_character(character: BaseCharacter):
	portrait.texture = load("res://Assets/Sprites/friendly_%s.png" % character.strName)
	# Prekletstvo "stunning_gaze"/"entangle": prizadeta zavezniška figura kaže
	# STUNNED/ROOTED namesto ALIVE (glej stunned_turns/rooted_turns tick-down v
	# BattleController.end_player_turn). STUNNED ima prednost, če je figura
	# hkrati oboje - popolnoma onesposobljena je "hujše" stanje od ROOTED.
	if character.stunned_turns > 0:
		status_value.text = "STUNNED"
		status_value.add_theme_color_override("font_color", STATUS_STUNNED_COLOR)
	elif character.rooted_turns > 0:
		status_value.text = "ROOTED"
		status_value.add_theme_color_override("font_color", STATUS_ROOTED_COLOR)
	else:
		status_value.text = "ALIVE"
		status_value.add_theme_color_override("font_color", STATUS_ALIVE_COLOR)
	_shown_character = character
	_show_abilities(character)


# Inšpekcija sovražnika (map_behaviour.enemy_inspected - klik na sovražnika,
# ko ni izbrana nobena zavezniška figura). Display-only: portret + status
# ("CURSED: <ime>" v barvi prekletstva, ali navaden "ENEMY") - PRVA vrstica
# sposobnosti se namesto ability podatkov uporabi za ime/opis prekletstva
# (enemy figure nimajo pravih sposobnosti, get_ability_defs() je prazen).
func _show_enemy(character: BaseCharacter):
	if not is_instance_valid(character):
		return
	portrait.texture = load("res://Assets/Sprites/enemy_%s.png" % character.strName)
	_shown_character = character
	_clear_ability_rows()
	if character.curse:
		status_value.text = character.curse.status_text()
		status_value.add_theme_color_override("font_color", character.curse.color())
		ability1_name.text = character.curse.display_name()
		ability1_desc.text = character.curse.description()
	else:
		status_value.text = "ENEMY"
		status_value.add_theme_color_override("font_color", STATUS_DEAD_COLOR)


func _show_dead_piece(piece_name: String):
	portrait.texture = load("res://Assets/Sprites/%s.png" % piece_name)
	status_value.text = "DEAD"
	status_value.add_theme_color_override("font_color", STATUS_DEAD_COLOR)
	_shown_character = null
	_clear_ability_rows()


func _show_benched_piece(piece_name: String):
	portrait.texture = load("res://Assets/Sprites/%s.png" % piece_name)
	status_value.text = "NOT PLACED"
	status_value.add_theme_color_override("font_color", STATUS_BENCHED_COLOR)
	_shown_character = null
	_clear_ability_rows()


func _clear_detail_panel():
	portrait.texture = null
	status_value.text = "-"
	status_value.remove_theme_color_override("font_color")
	_shown_character = null
	_clear_ability_rows()


func _clear_ability_rows():
	ability1_name.text = "-"
	ability1_level.text = ""
	ability1_uses.text = ""
	ability1_desc.text = ""
	ability1_button.disabled = true
	ability2_body.visible = false
	ability2_locked.visible = true
	ability2_locked.text = "Use 1 upgrade item at a rest to unlock the second ability."
	ability3_body.visible = false
	ability3_locked.visible = true
	ability3_locked.text = "Unlock the third ability in this piece's skill tree at a rest."


# "LV n" ali "LV MAX", ko je figura na najvišji stopnji (glej
# BaseCharacter.get_ability_info - level/level_max).
func _level_text(info: Dictionary) -> String:
	var level: int = info.get("level", 1)
	var level_max: int = info.get("level_max", 1)
	return "LV MAX" if level >= level_max else "LV %d" % level


# Napolni vse tri vrstice sposobnosti iz character.get_ability_info(slot) in
# nastavi gumbe glede na to, ali jih igralec sme trenutno uporabiti.
func _show_abilities(character: BaseCharacter):
	var can_use_now: bool = (
		not character.is_enemy
		and not character.is_obstacle
		and battle_controller.can_use_ability()
		and map_behaviour.pending_ability.is_empty()
	)

	var info1 := character.get_ability_info(1)
	ability1_name.text = info1.get("name", "-")
	ability1_level.text = _level_text(info1)
	ability1_uses.text = "%d/%d" % [info1.get("uses_remaining", 0), info1.get("uses_max", 0)]
	ability1_desc.text = info1.get("desc", "")
	ability1_button.disabled = not (can_use_now and info1.get("uses_remaining", 0) > 0)

	# Slota 2 in 3 delita isto "body/locked" strukturo (za razliko od slota 1,
	# ki nima zaklenjenega stanja) - zberemo njune node reference v par
	# slovarjev in ju obdelamo v isti zanki (isti vzorec kot unlocked_slots v
	# base_character.gd _load_persistent_upgrades()).
	var slot_widgets := {
		2: {"name": ability2_name, "level": ability2_level, "uses": ability2_uses,
			"desc": ability2_desc, "button": ability2_button, "body": ability2_body, "locked": ability2_locked},
		3: {"name": ability3_name, "level": ability3_level, "uses": ability3_uses,
			"desc": ability3_desc, "button": ability3_button, "body": ability3_body, "locked": ability3_locked},
	}
	for slot in [2, 3]:
		var w: Dictionary = slot_widgets[slot]
		if character.is_slot_unlocked(slot):
			var info := character.get_ability_info(slot)
			w.body.visible = true
			w.locked.visible = false
			w.name.text = info.get("name", "-")
			w.level.text = _level_text(info)
			w.uses.text = "%d/%d" % [info.get("uses_remaining", 0), info.get("uses_max", 0)]
			w.desc.text = info.get("desc", "")
			w.button.disabled = not (can_use_now and info.get("uses_remaining", 0) > 0)
		else:
			w.body.visible = false
			w.locked.visible = true
			if slot == 2:
				# Cena odklepa pride iz skill drevesa (a2_unlock vozlišče tega
				# tipa), ne več iz get_ability_info - glej SKILL_TREE_PLAN.md §5.1.
				var unlock_cost: int = skill_tree_data.get_node_def(character.strName, "a2_unlock").get("cost", 1)
				w.locked.text = "Use %d upgrade item%s at a rest to unlock the second ability." % [
					unlock_cost, "" if unlock_cost == 1 else "s"
				]
			else:
				w.locked.text = "Unlock the third ability in this piece's skill tree at a rest."


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
# ITEM PREDALA (</> in drag-to-use na plošči)
# ===============================================

func _on_item_toggle_pressed():
	item_drawer_open = not item_drawer_open
	item_panel.visible = item_drawer_open
	item_toggle_button.text = ">" if item_drawer_open else "<"


func _rebuild_item_drawer():
	for child in item_rows.get_children():
		child.queue_free()

	var ids: Array = player_manager.owned_items.keys()
	var any_shown := false
	for id in ids:
		var count: int = player_manager.owned_items[id]
		if count <= 0:
			continue
		item_rows.add_child(_build_item_row(id, count))
		any_shown = true

	if not any_shown:
		var empty := Label.new()
		empty.text = "NO ITEMS"
		item_rows.add_child(empty)


func _build_item_row(id: String, count: int) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 40)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var is_passive: bool = ItemData.get_kind(id) == "passive"
	if not is_passive:
		row.gui_input.connect(_on_item_row_input.bind(id))

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var icon := TextureRect.new()
	icon.texture = load("res://Assets/Sprites/item_%s.png" % id)
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	var label := Label.new()
	label.text = "x%d" % count
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(label)

	if is_passive:
		var passive_label := Label.new()
		passive_label.text = "PASSIVE"
		passive_label.add_theme_font_size_override("font_size", 10)
		passive_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(passive_label)

	return row


# Klik/pritisk na vrstico itema med igralčevo potezo začne drag (placement
# faza je izključena - drawer je takrat itak skrit, glej _on_battle_state_changed).
func _on_item_row_input(event: InputEvent, id: String):
	if dragging or dragging_item:
		return
	if battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dragging_item = true
		drag_item_id = id
		drag_ghost.texture = load("res://Assets/Sprites/item_%s.png" % id)
		drag_ghost.position = get_viewport().get_mouse_position() - drag_ghost.size / 2
		drag_ghost.visible = true


# Spuščeno izven plošče (BoardArea) = no-op, item ostane v inventarju.
func _resolve_item_drop(screen_pos: Vector2):
	dragging_item = false
	drag_ghost.visible = false

	if board_area.get_global_rect().has_point(screen_pos):
		var grid_pos := _screen_to_grid(screen_pos)
		use_item(drag_item_id, grid_pos)

	drag_item_id = ""


# Dejanska uporaba itema - ločena od _resolve_item_drop, da jo lahko smoke
# test pokliče neposredno (isti vzorec kot place_piece/move_placed_piece).
# Vrne true, če je bil item uporabljen in porabljen iz inventarja.
func use_item(id: String, grid_pos: Vector2i) -> bool:
	if player_manager.get_item_count(id) <= 0:
		return false
	if ItemData.get_kind(id) != "consumable":
		return false # pasivni itemi niso vlečljivi/uporabni (belt and braces; create_item vrne null tudi)
	var item: BaseItem = ItemData.create_item(id)
	if item == null:
		return false
	if not (item.can_use(battle_controller, grid_pos) and item.apply(battle_controller, grid_pos)):
		return false

	player_manager.remove_item(id) # emits items_changed -> _rebuild_item_drawer
	UiAudio.play_click()
	return true


func _on_party_changed():
	# Figura je umrla (ali se je ekipa spremenila) - osvežimo vrstici.
	# call_deferred: die() sproži signal PREDEN queue_free() figuro
	# dejansko odstrani iz grid_managerja snapshot-a.
	_rebuild_rows.call_deferred()
	_update_item_counts()
