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
# NOVO: True potem, ko je MapController._handle_event() enkrat obdelal to
# sobo (dodal figuro/sneg/item). Soba ostane "selected=false" po divine
# intervention bounce-backu (glej revert_current_room_selection), zato je
# znova klikljiva - brez tega flaga bi vsak ponovni poskus PONOVNO dodal
# figuro v enemy_party/friendly_party (glej bug: umri na 1. bitki, se vrni,
# poskusi znova -> vsak poskus doda še eno sovražno figuro).
@export var event_triggered: bool = false

# Definirajte enumerator RoomType, če ga še nimate (Godot 4.x)
enum RoomType {
	enemy_bishop,    # 0
	enemy_king,   # 1
	enemy_knight,       # 2
	enemy_rook,   # 3
	enemy_queen,       # 4
	enemy_pawn,
	friendly_pawn,
	friendly_knight,
	friendly_rook,
	friendly_bishop,
	friendly_queen,
	friendly_king,
	campfire,
	item,
	shop # DODAN NA KONEC - obstoječe sobe so serializirane kot int-i, prerazvrstitev bi jih pokvarila.
}

static var RoomTypeNames: Dictionary = {
	RoomType.enemy_bishop : "enemy_bishop",
	RoomType.enemy_king : "enemy_king",
	RoomType.enemy_knight : "enemy_knight",
	RoomType.enemy_rook : "enemy_rook",
	RoomType.enemy_queen : "enemy_queen",
	RoomType.enemy_pawn : "enemy_pawn",
	RoomType.friendly_pawn : "friendly_pawn",
	RoomType.friendly_knight : "friendly_knight",
	RoomType.friendly_rook : "friendly_rook",
	RoomType.friendly_bishop : "friendly_bishop",
	RoomType.friendly_queen : "friendly_queen",
	RoomType.friendly_king : "friendly_king",
	RoomType.campfire : "campfire",
	RoomType.item : "item",
	RoomType.shop : "shop"
}

## Kratek opis vsakega tipa sobe za hover tooltip na mapi (glej MapController /
## map_node_icon.gd) - en stavek, naj se prilega ~260px širokemu balonu.
static var RoomDescriptions: Dictionary = {
	RoomType.enemy_bishop : "Adds a Bishop to the enemy army",
	RoomType.enemy_king : "Adds a King to the enemy army",
	RoomType.enemy_knight : "Adds a Knight to the enemy army",
	RoomType.enemy_rook : "Adds a Rook to the enemy army",
	RoomType.enemy_queen : "Adds a Queen to the enemy army",
	RoomType.enemy_pawn : "Adds a Pawn to the enemy army",
	RoomType.friendly_pawn : "Recruits a Pawn to your army",
	RoomType.friendly_knight : "Recruits a Knight to your army",
	RoomType.friendly_rook : "Recruits a Rook to your army",
	RoomType.friendly_bishop : "Recruits a Bishop to your army",
	RoomType.friendly_queen : "Recruits a Queen to your army",
	RoomType.friendly_king : "Recruits a King to your army",
	RoomType.campfire : "Rest and upgrade your pieces",
	RoomType.item : "Grants a free upgrade item",
	RoomType.shop : "Opens the shop"
}
