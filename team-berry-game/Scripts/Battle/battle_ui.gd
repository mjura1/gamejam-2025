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
@onready var ability1_uses: Label = %Ability1Uses
@onready var ability1_desc: Label = %Ability1Desc
@onready var ability1_button: Button = %Ability1Button
@onready var ability2_name: Label = %Ability2Name
@onready var ability2_uses: Label = %Ability2Uses
@onready var ability2_desc: Label = %Ability2Desc
@onready var ability2_button: Button = %Ability2Button
@onready var ability2_body: VBoxContainer = %Ability2Body
@onready var ability2_locked: Label = %Ability2Locked
@onready var moves_label: Label = %MovesLabel
@onready var abilities_label: Label = %AbilitiesLabel
@onready var turn_label: Label = %TurnLabel
@onready var action_button: Button = %ActionButton
@onready var board_area: Control = %BoardArea
@onready var drag_ghost: TextureRect = %DragGhost

const STATUS_ALIVE_COLOR := Color(0.5, 1.0, 0.5)
const STATUS_DEAD_COLOR := Color(1.0, 0.4, 0.4)
const STATUS_BENCHED_COLOR := Color(0.75, 0.75, 0.75)

var placement_active: bool = false

# Stanje drag & dropa med placement fazo. drag_source_character je nastavljen,
# ko premikamo že postavljeno figuro; sicer postavljamo novo iz rosterja.
var dragging: bool = false
var drag_piece_name: String = ""
var drag_source_character: BaseCharacter = null

# Figura, ki je trenutno prikazana v detail panelu (null, če gre za mrtvo/
# klopno figuro brez žive instance - takrat gumbi ostanejo onemogočeni).
var _shown_character: BaseCharacter = null


func _ready():
	player_manager.party_changed.connect(_on_party_changed)
	map_behaviour.selection_changed.connect(_on_selection_changed)
	map_behaviour.ability_activated.connect(_on_ability_activated)
	battle_controller.state_changed.connect(_on_battle_state_changed)
	battle_controller.moves_changed.connect(_on_moves_changed)
	battle_controller.abilities_changed.connect(_on_abilities_changed)
	board_area.gui_input.connect(_on_board_area_input)
	action_button.pressed.connect(_on_action_button_pressed)
	ability1_button.pressed.connect(_on_ability_pressed.bind(1))
	ability2_button.pressed.connect(_on_ability_pressed.bind(2))

	_update_item_counts()
	_clear_detail_panel()

	# Figure (sovražniki/ovire) se spawnajo šele v battle.gd._ready() (starš
	# se inicializira ZA otroki), zato prvo gradnjo vrstic odložimo za en frame.
	_rebuild_rows.call_deferred()


# ===============================================
# STANJE BITKE (turn label + gumb + placement vklop)
# ===============================================

func _on_battle_state_changed(new_state):
	match new_state:
		battle_controller.BattleState.PLACEMENT:
			placement_active = true
			placement_highlighter.show_zone()
			board_area.mouse_filter = Control.MOUSE_FILTER_STOP
			moves_label.text = ""
			abilities_label.text = ""
			_update_placement_ui()
		battle_controller.BattleState.PLAYER_TURN:
			if placement_active:
				placement_active = false
				placement_highlighter.clear_zone()
				board_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
			turn_label.text = "PLAYER TURN"
			action_button.text = "END TURN"
			action_button.disabled = false
			# moves_remaining/abilities_remaining se posodobita malo kasneje v
			# isti klicni verigi (glej BattleController.start_player_turn()) -
			# moves_changed/abilities_changed ju takoj zatem osvežita tudi tukaj.
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

	if is_instance_valid(_shown_character):
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
	character.global_position = grid_manager.grid_to_world(grid_pos)
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
	for roster_name in player_manager.friendly_party:
		var assigned: BaseCharacter = null
		if alive_by_type.has(roster_name) and not alive_by_type[roster_name].is_empty():
			assigned = alive_by_type[roster_name].pop_front()
		assignments.append([roster_name, assigned])

		var icon := PieceIcon.new()
		icon.setup(roster_name, assigned)
		if assigned == null:
			if dead_counts.get(roster_name, 0) > 0:
				dead_counts[roster_name] -= 1
				icon.set_dead(true)
			elif not placement_active:
				# Živa, a ni bila postavljena v to bitko.
				icon.set_benched(true)
		icon.icon_clicked.connect(_on_icon_clicked)
		roster_row.add_child(icon)

	# ROZA VRSTICA: aktivne figure (žive na plošči). Med placementom se polni
	# sproti, ko igralec postavlja figure.
	for assignment in assignments:
		if is_instance_valid(assignment[1]):
			var icon := PieceIcon.new()
			icon.setup(assignment[0], assignment[1])
			icon.icon_clicked.connect(_on_icon_clicked)
			active_row.add_child(icon)

	_highlight_selected(map_behaviour.selected_character)


func _on_icon_clicked(icon: PieceIcon):
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
	status_value.text = "ALIVE"
	status_value.add_theme_color_override("font_color", STATUS_ALIVE_COLOR)
	_shown_character = character
	_show_abilities(character)


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
	ability1_uses.text = ""
	ability1_desc.text = ""
	ability1_button.disabled = true
	ability2_body.visible = false
	ability2_locked.visible = true
	ability2_locked.text = "Use 1 upgrade item at a rest to unlock the second ability."


# Napolni obe vrstici sposobnosti iz character.get_ability_info(slot) in
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
	ability1_uses.text = "%d/%d" % [info1.get("uses_remaining", 0), info1.get("uses_max", 0)]
	ability1_desc.text = info1.get("desc", "")
	ability1_button.disabled = not (can_use_now and info1.get("uses_remaining", 0) > 0)

	if character.has_ability_upgrade:
		var info2 := character.get_ability_info(2)
		ability2_body.visible = true
		ability2_locked.visible = false
		ability2_name.text = info2.get("name", "-")
		ability2_uses.text = "%d/%d" % [info2.get("uses_remaining", 0), info2.get("uses_max", 0)]
		ability2_desc.text = info2.get("desc", "")
		ability2_button.disabled = not (can_use_now and info2.get("uses_remaining", 0) > 0)
	else:
		ability2_body.visible = false
		ability2_locked.visible = true
		ability2_locked.text = "Use 1 upgrade item at a rest to unlock the second ability."


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


func _on_party_changed():
	# Figura je umrla (ali se je ekipa spremenila) - osvežimo vrstici.
	# call_deferred: die() sproži signal PREDEN queue_free() figuro
	# dejansko odstrani iz grid_managerja snapshot-a.
	_rebuild_rows.call_deferred()
	_update_item_counts()
