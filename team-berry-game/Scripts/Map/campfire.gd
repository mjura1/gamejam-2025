extends Control
class_name MenuController # Dajmo kontrolniku specifično ime

# ===============================================
# 1. UPRAVLJANJE STANJA GUMBA REST/BACK
# ===============================================

# Definicija stanj za gumb REST/BACK
enum RestMenuState {
	STATE_REST,    # Počitek in oživitev
	STATE_RETURN   # Vrnitev na mapo
}

var current_rest_state = RestMenuState.STATE_REST

# Reference na gumbe (PREDPOGOJI: Vozlišča v sceni so poimenovana: Upgrade, Party, RestAndBack)
@onready var upgrade_button = $HBoxContainer/Ugrade
@onready var party_button = $HBoxContainer/Party
@onready var rest_and_back_button = $HBoxContainer/RestAndBack

# ===============================================
# 2. GODOT FUNKCIJE
# ===============================================

func _ready() -> void:
	# 1. Priključi signale za robustnost (Če tega nisi že ročno storil v editorju)
	# (Priporočilo: Poveži gumbe ročno v Godotu ali preveri veljavnost vozlišča pred povezavo)
	
	# 2. Nastavi začetno stanje gumba REST/BACK
	update_rest_button_ui()

# ===============================================
# 3. GLAVNA LOGIKA (FUNKCIJE DEJSTVA)
# ===============================================

# Funkcija, ki se sproži, ko je gumb REST/BACK pritisnjen
func _on_rest_and_back_pressed() -> void:
	
	match current_rest_state:
		RestMenuState.STATE_REST:
			# IZVEDI POČITEK
			print("Izvajam počitek: Zdravljenje in oživitev likov.")
			perform_rest_action()
			
			# PREKLOP NA ZAKLJUČNO STANJE
			current_rest_state = RestMenuState.STATE_RETURN
			
		RestMenuState.STATE_RETURN:
			# IZVEDI VRNITEV
			print("Vračam se na mapo.")
			return_to_map_action()
			
			# Ne preklapljamo stanja, ker zapuščamo ta meni (sceno)
			# Če bi se meni ponovno uporabil, bi ga ponastavili: current_rest_state = RestMenuState.STATE_REST
			
	# Posodobi besedilo gumba
	update_rest_button_ui()


# Funkcija za gumb 'UPGRADE'
func _on_ugrade_pressed() -> void:
	print("Odpiram meni za nadgradnje.")


# Funkcija za gumb 'PARTY'
func _on_party_pressed() -> void:
	print("Odpiram meni za pregled in menjavo partyja.")
	# Tukaj vstavite kodo za odpiranje/prikaz Party menija.


# ===============================================
# 4. POMOŽNE FUNKCIJE (Helpsers)
# ===============================================

# Logika, ki se zgodi, ko se izvaja počitek (npr. poraba virov)
func perform_rest_action():
	# TODO: Dodajte logiko za porabo RESORSCE, oživitev in zdravljenje
	pass

# Logika, ki se zgodi, ko zapuščamo meni in se vračamo na mapo
func return_to_map_action():
	# TODO: Tukaj vstavite kodo za preklop scene nazaj na Rogue-like mapo:
	# get_tree().change_scene_to_file("res://scenes/roguelike_map.tscn") 
	# Začasno samo izpustimo to sceno, če je bila naložena kot otrok
	GF.return_to_map()


# Posodobitev besedila in stanja gumba REST/BACK
func update_rest_button_ui():
	if not is_instance_valid(rest_and_back_button):
		return

	match current_rest_state:
		RestMenuState.STATE_REST:
			rest_and_back_button.text = "  REST  "
			rest_and_back_button.disabled = false
			
		RestMenuState.STATE_RETURN:
			rest_and_back_button.text = "  BACK  " # BUG: popravi da se gumb premika narobe
			rest_and_back_button.disabled = false
			
	# === PRISILNA POSODOBITEV GUMBA ===
	rest_and_back_button.minimum_size_changed.emit()
	rest_and_back_button.queue_redraw()
	
	# === KRITIČNI KORAK: PRISILNA POSODOBITEV STARŠA (HBoxContainer) ===
	# Pridobimo starša (HBoxContainer) in mu povemo, naj se posodobi,
	# saj se je velikost enega od otrok spremenila.
	var parent_container = rest_and_back_button.get_parent()
	if is_instance_valid(parent_container) and parent_container is HBoxContainer:
		parent_container.queue_redraw()
		# Ta klic v Godot 4 je ključen za nekatere vsebnikov:
		parent_container.notification(Control.NOTIFICATION_RESIZED)
