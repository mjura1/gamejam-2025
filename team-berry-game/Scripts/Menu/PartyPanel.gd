# res://Scripts/Menu/PartyPanel.gd
extends Control

const CHARACTER_ICON_SCENE = preload("res://Scenes/Menu/character_icon.tscn") 

@onready var hbox_container = $HBoxContainer
@onready var player_manager = get_node("/root/PlayerManager")

func _ready():
	# Kličemo posodobitev ob zagonu in predpostavimo, da je PlayerManager že napolnjen
	update_party_display()
	
func update_party_display():
	# Počistimo prejšnje ikone
	for child in hbox_container.get_children():
		child.queue_free()
		
	# Izrišemo ikone na podlagi aktivne ekipe
	for character in player_manager.active_party:
		if is_instance_valid(character):
			var icon_panel = CHARACTER_ICON_SCENE.instantiate()
			
			icon_panel.set_character_data(character) 
			hbox_container.add_child(icon_panel)
			
			# Povezava signala za klik na ikono
			icon_panel.connect("clicked_character", on_character_icon_clicked)

# Funkcija za obravnavo klika, ki preusmeri v map_behaviour za dejansko izbiro
func on_character_icon_clicked(character_node):
	print("Party Panel: Kliknjena figura: %s" % character_node.name)
	
	# Pridobimo referenco na krmilnik interakcij
	var map_behaviour = get_node("/root/Node/MapBehaviour") 
	
	if is_instance_valid(map_behaviour):
		# Kličemo novo funkcijo za izbiro figure preko UI
		map_behaviour.select_character_via_ui(character_node)
