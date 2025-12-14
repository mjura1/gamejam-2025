# res://Scenes/UI/CharacterIcon.gd
extends VBoxContainer

signal clicked_character(character_node)

var character_ref: BaseCharacter

# Uporabljamo get_node("ImeVozlisca") namesto $ImeVozlisca za večjo robustnost pri dinamičnem inštanciranju.
@onready var texture_rect = get_node("TextureRect") 
@onready var status_label = get_node("Status") 

func set_character_data(character: BaseCharacter):
	character_ref = character
	
	#texture_rect.texture = character.icon_texture # Uporabite ikono figure (odkomentirajte, ko imate teksture)
	name = "Icon_" + character.name
	
	update_status_display() # Kličemo posodobitev

func update_status_display():
	# KRITIČNO: Vedno preverimo, ali vozlišče obstaja, preden ga uporabimo.
	if not is_instance_valid(status_label):
		push_error("Kritična napaka: Vozlišče 'Status' ni najdeno v sceni!")
		return 
		
	# Pisanje na label je sedaj varno
	if is_instance_valid(character_ref):
		# Prikaže ime figure, kar je vaš "Status"
		status_label.text = character_ref.name 
	else:
		status_label.text = "OK" 

# Obravnavanje klika miške na to ikono
func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("clicked_character", character_ref)
		get_viewport().set_input_as_handled()
