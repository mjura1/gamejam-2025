# res://Scripts/Battle/status_icon_badge.gd
# Majhna barvna ikona na figuri za začasno stanje (STUN/ROOT/FROZEN) -
# NAMESTO besedila (glej battle_ui._set_status_icon). Podroben tekst je že
# viden v detajlnem panelu (battle_ui._show_character - "STUNNED"/"ROOTED"/
# "FROZEN"), zato na sami figuri zadostuje barva; besedilo tam se je pri
# majhni velikosti (BADGE_RASTER_* rasterize-pa-pomanjšaj trik v
# battle_ui._set_named_badge) občasno popačilo/obrezalo, še posebej ob
# premikanju figure.
extends Node2D
class_name StatusIconBadge

var _color: Color = Color.WHITE
var _active: bool = false

const RADIUS := 2.2

func set_active(active: bool, color: Color = Color.WHITE) -> void:
	if active:
		_color = color
	if _active == active:
		return
	_active = active
	visible = active
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var outline := _color.darkened(0.35)
	draw_circle(Vector2.ZERO, RADIUS, _color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 20, outline, 0.6)
