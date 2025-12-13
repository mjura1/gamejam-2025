extends Resource
class_name Room # Nastavi class_name za lažjo tipizacijo (npr. 'var my_room: Room')

# =========================================================
# ENUM: Tipi sob (Dogodkov)
# Definira, katera scena se bo naložila ob obisku sobe
# =========================================================

enum RoomType {
	NOT_ASSIGNED, # Začetna vrednost/neuporabljeno
	MONSTER,      # Običajna bitka
	TREASURE,     # Soba z zakladom/nagrado
	CAMPFIRE,     # Počitek/nadgradnja
	SHOP,         # Trgovina
	BOSS          # Šef bitka
}

# =========================================================
# EXPORT VARIAVE: Podatkovni model sobe
# Vidno in urejano v Godot Inspectorju
# =========================================================

## Tip sobe, določa vsebino dogodka
@export var type: RoomType = RoomType.NOT_ASSIGNED

## Položaj sobe v logični mreži (npr. (vrstica 5, stolpec 3))
@export var grid_position: Vector2i = Vector2i.ZERO

## Dejanske 2D koordinate v igralnem svetu (kam postavimo ikono)
@export var position: Vector2 = Vector2.ZERO

## Polje virov Room, ki določa, katere sobe so dosegljive s te točke
@export var next_rooms: Array[Resource] = []

## Zastava, ki določa interaktivnost:
## - TRUE: Soba je že obiskana
## - FALSE: Soba je odklenjena in na voljo
@export var selected: bool = false
