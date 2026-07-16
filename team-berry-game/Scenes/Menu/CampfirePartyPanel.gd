# res://Scenes/Menu/CampfirePartyPanel.gd
extends CanvasLayer # Koren CampfirePartyPanel je CanvasLayer

const CHARACTER_ICON_SCENE = preload("res://Scenes/Menu/character_icon.tscn") # Predpostavimo, da je pot pravilna
# Če želite prikazati gumb 'Revive', morda potrebujete tudi posebno sceno za padlo figuro!

# ===============================================
# 1. REFERENCE NA VOZLIŠČA
# ===============================================

@onready var player_manager = get_node("/root/PlayerManager")

# POPRAVLJENE POTI glede na vašo hierarhijo CampfirePartyPanel:
@onready var active_party_container = $CenterContainer/Panel/MainVBox/HLayout/ActiveParty
@onready var dead_party_container = $CenterContainer/Panel/MainVBox/HLayout/DeadParty
@onready var close_button = $CenterContainer/Panel/MainVBox/CloseButton
@onready var title_label = $CenterContainer/Panel/MainVBox/Title # Za naslov

# ===============================================
# 2. GODOT FUNKCIJE
# ===============================================

func _ready():
	if is_instance_valid(title_label):
		title_label.text = "PARTY MANAGEMENT & REVIVAL"
		
	# Inicialni izris ob zagonu
	update_all_displays()
	
	# Povezava za zapiranje
	close_button.pressed.connect(close_menu)

# Ta funkcija omogoča zapiranje menija z ESC tipko
func _input(event):
	if event.is_action_pressed("ui_cancel"): # "ui_cancel" je privzeta akcija za ESC
		close_menu()

func update_all_displays():
	update_active_party_display()
	update_dead_party_display()

# ===============================================
# 3. PRIKAZ AKTIVNE EKIPE (Za statistiko/opremo)
# ===============================================

func update_active_party_display():
	# Počistimo prejšnje ikone
	for child in active_party_container.get_children():
		child.queue_free()
		
	# Za vsako aktivno figuro ustvarimo ikono
	for character in player_manager.active_party:
		if is_instance_valid(character):
			var icon_panel = CHARACTER_ICON_SCENE.instantiate()
			icon_panel.set_character_data(character)
			
			# Odstranimo signal za klik iz bitke, saj tukaj ni potreben
			# icon_panel.disconnect("clicked_character", ...)
			
			active_party_container.add_child(icon_panel)

# ===============================================
# 4. PRIKAZ PADLIH (Za oživljanje)
# ===============================================

func update_dead_party_display():
	# Počistimo prejšnje elemente
	for child in dead_party_container.get_children():
		child.queue_free()
		
	# Prikažemo Label, če ni mrtvih
	if player_manager.dead_party.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No fallen comrades."
		dead_party_container.add_child(empty_label)
		return

	# Za vsakega padlega ustvarimo vmesnik za oživitev
	for char_name in player_manager.dead_party:
		var data = player_manager.dead_party[char_name]
		
		# Ustvarimo kontejner za ime in gumb
		var revive_container = HBoxContainer.new()
		
		var name_label = Label.new()
		name_label.text = "%s (Cost: %d Food)" % [data.name, data.revive_cost]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND
		revive_container.add_child(name_label)
		
		var revive_button = Button.new()
		revive_button.text = "Revive"
		revive_button.disabled = player_manager.food < data.revive_cost
		revive_container.add_child(revive_button)
		
		# Povezava: Ko je gumb pritisnjen, se sproži poskus oživitve
		revive_button.pressed.connect(func(): 
			try_revive_character(char_name, data.revive_cost))
			
		dead_party_container.add_child(revive_container)
		
# ===============================================
# 5. LOGIKA OŽIVLJANJA
# ===============================================

func try_revive_character(character_name: String, cost: int):
	
	if player_manager.food >= cost:
		# Poraba virov in klic funkcije za oživitev v PlayerManager
		player_manager.food -= cost
		var success = player_manager.revive_character(character_name)
		
		if success:
			print("Oživljen lik: %s. Preostala hrana: %d" % [character_name, player_manager.food])
			
			# POSODOBIMO UI ob uspehu
			update_all_displays()
			
			# TODO: Dodajte klic za posodobitev vseh Campfire UI elementov, 
			# ki prikazujejo vire (npr. label za Food na glavnem Campfire zaslonu).
		else:
			# PlayerManager je vrnil napako (npr. napačna pot do scene)
			print("Oživitev ni uspela zaradi napake v PlayerManagerju.")
			
	else:
		print("Ni dovolj virov (Food) za oživitev %s. Potrebnih: %d, Imate: %d" 
			  % [character_name, cost, player_manager.food])
		# TODO: Prikaži vizualno opozorilo igralcu
		
# ===============================================
# 6. ZAPIRANJE
# ===============================================

func close_menu():
	# 1. Poiščemo Campfire krmilnik (predpostavimo, da je Campfire root)
	var menu_controller = get_tree().root.find_child("MenuController", true, false)
	
	# 2. Če ga najdemo, mu omogočimo interakcijo z miško
	if is_instance_valid(menu_controller):
		# Ta MOUSE_FILTER_PASS omogoči, da se Campfire gumbi ponovno aktivirajo
		menu_controller.mouse_filter = Control.MOUSE_FILTER_PASS 
	
	queue_free() # Uniči Party Screen
