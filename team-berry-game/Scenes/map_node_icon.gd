extends Button
class_name MapNodeIcon # Omogoča tipizacijo

# =========================================================
# 1. EXPORT IN KONSTANTE
# =========================================================

# Referenca na vir podatkov Room (nastavi jo MapController ob instanciranju)
@export var room_resource: Room # Tipiziramo kot Room (vaš map_point.gd)

# Povezava do vozlišča, ki prikazuje ikono
@onready var icon_display: TextureRect = $IconDisplay 

# Slovar z vnaprej naloženimi ikonami (Grafiko morate uvoziti v Godot!)
const ICON_LOOKUP: Dictionary = {
	Room.RoomType.MONSTER: preload("res://Assets/Icons/sword.jpg"),
	Room.RoomType.TREASURE: preload("res://Assets/Icons/chest.png"),
	Room.RoomType.CAMPFIRE: preload("res://Scenes/campfire.tscn"),
	Room.RoomType.SHOP: preload("res://Assets/Icons/shop.jpg"),
	Room.RoomType.BOSS: preload("res://Assets/Icons/skull.png"),
}


# =========================================================
# 2. JAVNE METODE: Inicializacija podatkov
# =========================================================

## Kliče jo MapController takoj po ustvarjanju.
func initialize(room_data: Room):
	self.room_resource = room_data
	
	# Dinamično nastavi vizualizacijo
	_update_icon()
	_update_scale()
	
	# Poveži signal gumba za interaktivnost
	pressed.connect(_on_room_pressed)


# =========================================================
# 3. POMOŽNE METODE: Posodabljanje vizualizacije
# =========================================================

func _update_icon():
	if ICON_LOOKUP.has(room_resource.type):
		icon_display.texture = ICON_LOOKUP[room_resource.type]

func _update_scale():
	# Boss je večji in se lahko premika!
	if room_resource.type == Room.RoomType.BOSS:
		scale = Vector2(1.5, 1.5)
	
	# Dodajte logiko za status sobe (ali je odklenjena/obiskana)
	if room_resource.selected:
		modulate = Color.GRAY
	else:
		modulate = Color.WHITE

# =========================================================
# 4. SIGNAL KORISTNIKA
# =========================================================

func _on_room_pressed():
	# Tu pošljemo signal, da je igralec kliknil sobo.
	# To naj obravnava glavno vozlišče (npr. MapController ali RunManager).
	
	# Preden dovolimo klik, preverimo, ali je soba odklenjena
	if not room_resource.selected:
		# Namesto print, sprožite signal, ki bo preklopil sceno (Battle/Shop/Campfire)
		print("Kliknjena soba: %s pri %s. Trenutno še ne omogoča preklopa scene." % 
			[Room.RoomType.keys()[room_resource.type], room_resource.grid_position])
	else:
		print("Soba je že obiskana.")
