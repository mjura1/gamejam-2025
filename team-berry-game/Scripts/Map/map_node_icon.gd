# res://Scripts/Map/MapNodeIcon.gd
extends Button
class_name MapNodeIcon

# =========================================================
# 1. EXPORT, SIGNALI IN ONREADY
# =========================================================

@export var room_resource: Room 

@onready var icon_display: TextureRect = $IconDisplay # PREVERI, DA JE IME VOZLIŠČA PRAVILNO!
@onready var hover_timer: Timer = $HoverTimer

# Signal, ki ga posluša MapController, ko je soba kliknjena
signal room_clicked(room_data)

# Signala za hover tooltip (glej MapController) - hover_bubble_requested se
# sproži šele po HoverTimer.timeout (~3s), ne takoj ob mouse_entered.
signal hover_bubble_requested(icon)
signal hover_bubble_dismissed

func _ready():
	_init_icon_lookup()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	hover_timer.timeout.connect(_on_hover_timer_timeout)

func _on_mouse_entered():
	hover_timer.start()

func _on_mouse_exited():
	hover_timer.stop()
	hover_bubble_dismissed.emit()

func _on_hover_timer_timeout():
	hover_bubble_requested.emit(self)

static var ICON_LOOKUP: Dictionary = {}

# Campfire dobi animirano (utripajočo) ikono namesto statičnega PNG-ja -
# glej Assets/Sprites/campfire_animated.tres (AnimatedTexture iz 2 sličic,
# izvorno wm_campfire.gif). AnimatedTexture je Texture2D, zato ga
# TextureRect.texture sprejme brez dodatnih sprememb.
const CAMPFIRE_ANIMATED_TEXTURE := "res://Assets/Sprites/campfire_animated.tres"

static func _init_icon_lookup():
	if not ICON_LOOKUP.is_empty():
		return
	for rtype in Room.RoomTypeNames.keys():
		var room_type_name = Room.RoomTypeNames[rtype]
		if room_type_name == "campfire":
			ICON_LOOKUP[rtype] = load(CAMPFIRE_ANIMATED_TEXTURE)
			continue
		var path = "res://Assets/Sprites/%s.png" % [room_type_name]
		ICON_LOOKUP[rtype] = load(path)


# =========================================================
# 2. INICIALIZACIJA IN VIZUALNO POSODABLJANJE
# =========================================================

func initialize(room_data: Room):
	self.room_resource = room_data
	
	_update_icon()
	_update_scale()
	
	# Priključitev signala na samo sebe
	pressed.connect(_on_room_pressed)
	
	# Prva posodobitev videza glede na začetno stanje (ki ga nastavi MapController)
	update_look(room_resource.is_unlocked, room_resource.selected)

func _update_icon():
	if ICON_LOOKUP.has(room_resource.type):
		icon_display.texture = ICON_LOOKUP[room_resource.type]

const ICON_SCALE := 6.0

func _update_scale():
	scale = Vector2(ICON_SCALE, ICON_SCALE)

## Kliče jo MapController, da vizualno posodobi ikono (barva, aktivnost)
func update_look(unlocked: bool, selected: bool):
	if selected:
		modulate = Color.GRAY * 0.5 # Obiskana
		self.disabled = true
	elif unlocked:
		modulate = Color.WHITE # Odklenjena (aktivna)
		self.disabled = false
	else:
		modulate =Color(0.25, 0.25, 0.25, 1.0) # Zaklenjena (skrita/neaktivna)
		self.disabled = true

# =========================================================
# 3. OBRNAVNA KLIKA
# =========================================================

func _on_room_pressed():
	# Preverimo, ali je soba odklenjena IN še ne obiskana
	if room_resource.is_unlocked and not room_resource.selected:
		# Oddaj signal, da je soba izbrana
		room_clicked.emit(room_resource)
	else:
		# Ne naredi nič
		pass
