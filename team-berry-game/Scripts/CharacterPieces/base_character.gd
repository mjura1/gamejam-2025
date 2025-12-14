extends Node2D
class_name BaseCharacter

var grid_pos: Vector2i

@onready var tile_map = get_node("/root/Node/Map/TileMapLayer") # Ohranimo to, če je pot res fiksna
@onready var player_manager = get_node("/root/PlayerManager")

@export var selected: bool = false
@export var move_range: int = 1
# Če GridManager ni nikoli ročno nastavljen v urejevalniku, naj bo to @onready:
@onready var grid_manager = get_node("/root/Node/GridManager") 


@export var is_enemy: bool = false 

func _ready():
	if is_instance_valid(grid_manager):
		grid_pos = grid_manager.world_to_grid(global_position)
		global_position = grid_manager.grid_to_world(grid_pos)
		grid_manager.occupy(grid_pos, self)
	else:
		print("POZOR: GridManager še ni pripravljen za %s" % self.name)
		pass 
		
func get_move_directions() -> Array[Vector2i]:
	return []

# KLJUČNI POPRAVEK: Standardizirano ime in celotna logika za izračun premika/napada
func calculate_valid_targets() -> Array[Vector2i]:
	var targets: Array[Vector2i] = []

	for dir in get_move_directions():
		for step in range(1, move_range + 1):
			var target_pos := grid_pos + dir * step

			# 1. Preverjanje mej
			if not grid_manager.is_inside_boundary(target_pos, tile_map.get_used_rect()):
				break

			# 2. Preverjanje zasedenosti
			if grid_manager.is_occupied(target_pos):
				var target_char = grid_manager.get_character_at(target_pos)
				
				# PREVERJANJE: Ali je tarča sovražnik?
				if target_char and target_char.is_enemy != is_enemy:
					# To je sovražnik -> Veljavna tarča za napad
					targets.append(target_pos)
				
				# Gibanje se vedno ustavi ob prvi zasedeni celici (lastni ali sovražni)
				break 

			# 3. Polje je prazno -> Veljavna tarča za premik
			targets.append(target_pos)

	return targets

# Premesti figuro na novo lokacijo (ne preverja veljavnosti, to naredi Input Controller)
func execute_move(target: Vector2i):
	grid_manager.vacate(grid_pos)
	grid_pos = target
	grid_manager.occupy(grid_pos, self)
	global_position = grid_manager.grid_to_world(grid_pos)
	
	# Nastavite has_moved = true, če ste to dodali za logiko piona
	# has_moved = true 

func try_move(target: Vector2i) -> bool:
	if target not in calculate_valid_targets():
		return false
	
	if grid_manager.is_occupied(target):
		return false

	execute_move(target)
	return true
	
# Odstranitev figure iz igre (umre)
func die():
	grid_manager.vacate(grid_pos) # Osvobodi polje
	
	if not is_enemy:
		# Če umre zaveznik, ga odstranimo iz seznama aktivnih figur igralca
		if player_manager.active_party.has(self):
			player_manager.active_party.erase(self)
			print("Zaveznik umrl. Preostali aktivni party size: %d" % player_manager.active_party.size())
			
			# TODO: Preverjanje pogojev za konec igre (Game Over)
			if player_manager.active_party.is_empty():
				print("GAME OVER")
		
	queue_free() # Uniči vozlišče
	print("Figura je bila uničena in odstranjena.")

# Logika zajetja tarče in premika napadalca na tarčino polje
func capture(target: BaseCharacter):
	print("Izvajam zajetje tarče...")
	
	# 1. Zajem/Smrt tarče (Sovražnikova figura je odstranjena)
	target.die()
	
	# 2. Premik napadalca na tarčino zdaj prosto polje
	execute_move(target.grid_pos)
