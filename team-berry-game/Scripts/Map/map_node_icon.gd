# res://Scripts/Map/MapNodeIcon.gd
extends Button
class_name MapNodeIcon

# =========================================================
# 1. EXPORT, SIGNALI IN ONREADY
# =========================================================

@export var room_resource: Room 

@onready var icon_display: TextureRect = $IconDisplay # PREVERI, DA JE IME VOZLIŠČA PRAVILNO!

# Signal, ki ga posluša MapController, ko je soba kliknjena
signal room_clicked(room_data) 

func _ready():
	_init_icon_lookup()

static var ICON_LOOKUP: Dictionary = {}

static func _init_icon_lookup():
	if not ICON_LOOKUP.is_empty():
		return
	for rtype in Room.RoomTypeNames.keys():
		var room_type_name = Room.RoomTypeNames[rtype]
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

func _update_scale():
	scale = Vector2(3.0, 3.0)

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
