# res://Scripts/Curses/curse_marker.gd
# Vizualni marker prekletstva - otrok prečekane figure (base_character.
# apply_curse), zato se premika/umre z njo samodejno. Brez sprite-ov, vse
# code-drawn/CPUParticles2D. Dva načina, izbrana ENKRAT ob ustvarjanju glede
# na SettingsManager.reduced_motion (SettingsManager nima change signala -
# namenoma ga ne dodajamo samo za to; sprememba nastavitve med bitko torej
# učinkuje šele v naslednji bitki):
#   - normalno: animirani delci (CPUParticles2D) + pulzirajoč tint figure.
#   - reduced motion: samo statična oblika (diamant) + statičen tint - NIČ
#     se ne animira (dostopnost).
extends Node2D
class_name CurseMarker

var _character: Node2D
var _curse: BaseCurse
var _reduced_motion: bool = false
var _tween: Tween

const PULSE_DURATION := 0.8
const DIAMOND_SIZE := 3.0
const MARKER_OFFSET := Vector2(0, -14) # nad figuro, v "svet" enotah

func setup(character: Node2D, curse: BaseCurse) -> void:
	_character = character
	_curse = curse

	var settings_manager = get_node_or_null("/root/SettingsManager")
	_reduced_motion = is_instance_valid(settings_manager) and settings_manager.reduced_motion

	# Scale kompenzacija (enak vzorec kot battle_ui._set_board_badge): koren
	# figure ima svoj scale (rook 0.05 proti pawn 0.08 ipd.) - obrnemo ga, da
	# je marker enake velikosti/na enakem mestu za vse figure.
	if _character.scale.x != 0 and _character.scale.y != 0:
		scale = Vector2.ONE / _character.scale
	position = MARKER_OFFSET * scale

	if _reduced_motion:
		_character.modulate = curse.color().lerp(Color.WHITE, 0.6)
		queue_redraw()
	else:
		_spawn_particles()
		_start_pulse()
		# Diamant je lahko prisoten tudi v normalnem načinu (implementer's
		# call po planu) - bere se lepo skupaj z delci, zato ga narišemo v
		# obeh načinih.
		queue_redraw()

# _tween je bil ustvarjen na _character (glej _start_pulse), ne na tem
# vozlišču, zato ga Godot NE ubije samodejno, ko ta marker izgine
# (queue_free/remove_child) - brez tega bi ostal osirotel tween, ki naprej
# pulzira figuro (in se, če se prekletstvo takoj znova doda, prekriva z
# novim tweenom istega markerja -> utripanje/napačna barva "sometimes").
func _exit_tree() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	if is_instance_valid(_character):
		_character.modulate = Color.WHITE

func _spawn_particles() -> void:
	var particles := CPUParticles2D.new()
	particles.amount = 8
	particles.lifetime = 1.2
	particles.gravity = Vector2(0, -12)
	particles.spread = 25.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 6.0
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	particles.color = _curse.color()
	particles.emitting = true
	add_child(particles)

func _start_pulse() -> void:
	if not is_instance_valid(_character):
		return
	var tint := _curse.color().lerp(Color.WHITE, 0.5)
	_tween = _character.create_tween()
	_tween.set_loops()
	_tween.tween_property(_character, "modulate", tint, PULSE_DURATION).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_character, "modulate", Color.WHITE, PULSE_DURATION).set_trans(Tween.TRANS_SINE)

func _draw() -> void:
	if not is_instance_valid(_curse):
		return
	var outline := _curse.color().darkened(0.3)
	var points := PackedVector2Array([
		Vector2(0, -DIAMOND_SIZE),
		Vector2(DIAMOND_SIZE, 0),
		Vector2(0, DIAMOND_SIZE),
		Vector2(-DIAMOND_SIZE, 0),
	])
	draw_colored_polygon(points, _curse.color())
	draw_polyline(points + PackedVector2Array([points[0]]), outline, 0.6)
