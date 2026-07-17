# res://Scripts/TileMap/move_highlighter.gd
extends Node2D
class_name MoveHighlighter

# Referenci na GridManager in velikost celice
@onready var grid_manager = get_node("../GridManager")
var cell_size: Vector2 = Vector2.ZERO

# Array veljavnih mrežnih pozicij (Vector2i), ki jih moramo narisati
var valid_moves: Array[Vector2i] = []

const MOVE_COLOR = Color(0.1, 0.9, 0.1, 0.6) # Svetla Zelena
const CAPTURE_COLOR = Color(0.9, 0.1, 0.1, 0.6) # Svetla Rdeča
const PATH_COLOR = Color(0.5, 0.5, 0.5, 0.4) # Siva - pot/L-figura viteza

# ===============================================
# VIZUALIZACIJA SOVRAŽNIKOVIH POTEZ (NOVO)
# ===============================================
# Vsaka poteza sovražnika med potezo dodano v ta seznam (kopiči se, ne
# briše med posameznimi sovražniki), da igralec ob koncu poteze vidi
# CELOTNO dogajanje naenkrat. Ob začetku igralčeve poteze vse skupaj
# počasi izgine (glej start_fade_out). Risanje samih poudarkov je v ločenem
# _flash_layer otroku (glej spodaj), da njegov queue_redraw() vsako sličico
# med pojemanjem ne sproži tudi ponovnega risanja valid_moves.
var enemy_move_flashes: Array[Dictionary] = []

var is_fading: bool = false
var fade_duration: float = 5.0
var fade_elapsed: float = 0.0

var _flash_layer: EnemyMoveFlashLayer

func _ready():
	if is_instance_valid(grid_manager):
		cell_size = grid_manager.cell_size
	else:
		push_error("MoveHighlighter: GridManager ni najden na poti ../GridManager.")

	_flash_layer = EnemyMoveFlashLayer.new()
	_flash_layer.highlighter = self
	add_child(_flash_layer)

func _process(delta: float) -> void:
	if not is_fading:
		return

	fade_elapsed += delta
	_flash_layer.queue_redraw()

	if fade_elapsed >= fade_duration:
		clear_enemy_moves()

# Trenutna prosojnost poudarkov glede na potek pojemanja - izračunano
# sproti namesto shranjeno kot ločeno stanje, da se ne more razsinhronizirati
# z fade_elapsed/fade_duration.
func current_fade_alpha() -> float:
	if not is_fading:
		return 1.0
	return clampf(1.0 - (fade_elapsed / fade_duration), 0.0, 1.0)

func show_moves(moves: Array[Vector2i]):
 #"""Sprejme seznam veljavnih pozicij in sproži ponovno risanje."""
	valid_moves = moves
	queue_redraw()

func clear_moves():
	#"""Počisti seznam in skrije poudarek."""
	valid_moves.clear()
	queue_redraw()

# Doda eno sovražnikovo potezo v kopičeni seznam (ne briše prejšnjih).
func flash_enemy_move(from: Vector2i, to: Vector2i, path: Array[Vector2i], is_capture: bool) -> void:
	enemy_move_flashes.append({
		"from": from,
		"to": to,
		"path": path,
		"is_capture": is_capture,
	})
	_flash_layer.queue_redraw()

# Sproži počasno pojemanje vseh kopičenih potez - kliče se ob začetku
# igralčeve poteze (glej BattleController.start_player_turn()).
func start_fade_out(duration: float = 5.0) -> void:
	if enemy_move_flashes.is_empty():
		return
	is_fading = true
	fade_duration = duration
	fade_elapsed = 0.0

func clear_enemy_moves() -> void:
	enemy_move_flashes.clear()
	is_fading = false
	_flash_layer.queue_redraw()

func _draw_cell(grid_pos: Vector2i, color: Color, filled: bool = true, width: float = -1.0) -> void:
	draw_rect(Rect2(Vector2(grid_pos) * cell_size, cell_size), color, filled, width)

func _draw():
	if not is_instance_valid(grid_manager):
		return

	for grid_pos in valid_moves:
		# Privzeta barva: Zelena (premik), Rdeča če je polje zasedeno (zajetje)
		var draw_color = CAPTURE_COLOR if grid_manager.get_character_at(grid_pos) else MOVE_COLOR
		_draw_cell(grid_pos, draw_color)
