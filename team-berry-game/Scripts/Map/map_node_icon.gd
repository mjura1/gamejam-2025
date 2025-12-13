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

# Naložite teksture (GRAFIKO)
const ICON_LOOKUP: Dictionary = {
	Room.RoomType.MONSTER: preload("res://Assets/Icons/sword.jpg"),
	Room.RoomType.TREASURE: preload("res://Assets/Icons/chest.png"),
	Room.RoomType.CAMPFIRE: preload("res://Assets/Icons/tent.jpg"),
	Room.RoomType.SHOP: preload("res://Assets/Icons/shop.jpg"),
	Room.RoomType.BOSS: preload("res://Assets/Icons/skull.png"),
}


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
	if room_resource.type == Room.RoomType.BOSS:
		scale = Vector2(3.5, 3.5)
	else:
		# Nastavi standarno velikost ikon
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
