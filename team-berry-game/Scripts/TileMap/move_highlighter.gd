# res://Scripts/TileMap/move_highlighter.gd
extends Node2D

# Referenci na GridManager in velikost celice
@onready var grid_manager = get_node("../GridManager")
var cell_size: Vector2 = Vector2.ZERO

# Array veljavnih mrežnih pozicij (Vector2i), ki jih moramo narisati
var valid_moves: Array[Vector2i] = []

const MOVE_COLOR = Color(0.1, 0.9, 0.1, 0.6) # Svetla Zelena
const CAPTURE_COLOR = Color(0.9, 0.1, 0.1, 0.6) # Svetla Rdeča

# ===============================================
# VIZUALIZACIJA SOVRAŽNIKOVIH POTEZ (NOVO)
# ===============================================
# Vsaka poteza sovražnika med potezo dodano v ta seznam (kopiči se, ne
# briše med posameznimi sovražniki), da igralec ob koncu poteze vidi
# CELOTNO dogajanje naenkrat. Ob začetku igralčeve poteze vse skupaj
# počasi izgine (glej start_fade_out).
var enemy_move_flashes: Array[Dictionary] = []
const PATH_COLOR = Color(0.5, 0.5, 0.5, 0.4) # Siva - pot/L-figura viteza

var is_fading: bool = false
var fade_alpha: float = 1.0
var fade_duration: float = 5.0
var fade_elapsed: float = 0.0

func _ready():
	if is_instance_valid(grid_manager):
		cell_size = grid_manager.cell_size
	else:
		push_error("MoveHighlighter: GridManager ni najden na poti ../GridManager.")

func _process(delta: float) -> void:
	if not is_fading:
		return

	fade_elapsed += delta
	fade_alpha = clampf(1.0 - (fade_elapsed / fade_duration), 0.0, 1.0)
	queue_redraw()

	if fade_elapsed >= fade_duration:
		clear_enemy_moves()

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
	queue_redraw()

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
	fade_alpha = 1.0
	queue_redraw()

func _draw():
	if not is_instance_valid(grid_manager):
		return

	if not valid_moves.is_empty():
		for grid_pos in valid_moves:
			var top_left = Vector2(grid_pos) * cell_size

			# 1. Privzeta barva: Zelena (premik)
			var draw_color = MOVE_COLOR

			# 2. Preverjanje za ZAJETJE
			var target_char = grid_manager.get_character_at(grid_pos)

			# Če je na polju figura:
			if target_char:
				draw_color = CAPTURE_COLOR # Rdeča

			# Risanje polnila (fill)
			draw_rect(
				Rect2(top_left, cell_size),
				draw_color,
				true
			)

	if enemy_move_flashes.is_empty():
		return

	var alpha_mult = fade_alpha if is_fading else 1.0

	for flash in enemy_move_flashes:
		# Pot / L-figura (siva)
		for path_pos in flash["path"]:
			var path_color = PATH_COLOR
			path_color.a *= alpha_mult
			draw_rect(
				Rect2(Vector2(path_pos) * cell_size, cell_size),
				path_color,
				true
			)

		# Ciljno polje (zelena = premik, rdeča = zajetje)
		var dest_color = CAPTURE_COLOR if flash["is_capture"] else MOVE_COLOR
		dest_color.a *= alpha_mult
		draw_rect(
			Rect2(Vector2(flash["to"]) * cell_size, cell_size),
			dest_color,
			true
		)

		# Izvorno polje (bel obris)
		var origin_color = Color(1, 1, 1, 0.9 * alpha_mult)
		draw_rect(
			Rect2(Vector2(flash["from"]) * cell_size, cell_size),
			origin_color,
			false,
			2.0
		)
