# res://Scripts/Map/map_node_ripple.gd
# Code-drawn ripple (expanding, fading ring) okoli trenutno izbirljivih
# (unlocked) vozlišč na mapi - glej map_node_icon.gd update_look().
extends Node2D

const RING_COUNT := 1
const MIN_RADIUS := 5.0
const MAX_RADIUS := 8.0
const RING_WIDTH := 0.8
const DURATION := 2
const RING_COLOR := Color(0.75, 0.75, 0.75, 0.55)

var _time: float = 0.0
var _active: bool = false
var _reduced_motion: bool = false

func _ready() -> void:
	set_process(false)
	var settings_manager = get_node_or_null("/root/SettingsManager")
	_reduced_motion = is_instance_valid(settings_manager) and settings_manager.reduced_motion

func set_active(is_active: bool) -> void:
	if _active == is_active:
		return
	_active = is_active
	_time = 0.0
	set_process(is_active and not _reduced_motion)
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	if not _active:
		return
	if _reduced_motion:
		# Dostopnost: brez animacije, samo statičen obroč (glej curse_marker.gd
		# za enak vzorec).
		draw_arc(Vector2.ZERO, MAX_RADIUS, 0.0, TAU, 48, RING_COLOR, RING_WIDTH, true)
		return
	for i in range(RING_COUNT):
		var phase: float = fmod(_time / DURATION + float(i) / float(RING_COUNT), 1.0)
		var radius: float = lerpf(MIN_RADIUS, MAX_RADIUS, phase)
		var color: Color = RING_COLOR
		color.a *= (1.0 - phase)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color, RING_WIDTH, true)
