# res://Scripts/Map/map_point.gd
extends Resource
class_name Room

# Lastnosti, ki jih nastavi MapGenerator
@export var grid_position: Vector2i # Položaj v mreži (vrstica/nadstropje, stolpec)
@export var position: Vector2 # 2D pozicija v svetu
@export var type: int # Tip sobe (MONSTER, SHOP, BOSS, itd.)
@export var next_rooms: Array[Room] = [] # Povezave do sob v naslednjem nadstropju

# Stanje sobe (KLJUČNO ZA INTERAKTIVNOST)
@export var selected: bool = false
@export var is_unlocked: bool = false

# Definirajte enumerator RoomType, če ga še nimate (Godot 4.x)
enum RoomType {
	MONSTER,    # 0
	CAMPFIRE,   # 1
	SHOP,       # 2
	TREASURE,   # 3
	BOSS,       # 4
	UNKNOWN     # 5
}
