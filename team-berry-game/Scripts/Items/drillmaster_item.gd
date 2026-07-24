# res://Scripts/Items/drillmaster_item.gd
# "Passive" per brainstorm, a implementirano kot artefakt (glej items.json
# "kind": "artifact" + NEW_ITEMS_WAVE2_PLAN.md deviation opombo) - mora biti
# vlečljiv, da ga igralec sploh lahko SPROŽI (pravi pasivi v tem UI-ju nikoli
# niso vlečljivi, glej battle_ui._build_item_icon is_passive preverjanje).
# apply()/can_use() tu NISTA klicana - swap potrebuje trenutno IZBRANO
# zavezniško figuro (map_behaviour.selected_character), do katere
# BaseItem.apply(battle_controller, grid_pos) signature nima dostopa (samo
# battle_controller, ki map_behaviour ne pozna). Cela logika je zato v celoti
# v battle_ui.gd.use_item() poseben primer (isti "poseben primer, brez
# porabe iz inventarja" vzorec kot frozen_rampart) - ta razred obstaja samo
# za ITEM_SCRIPTS registracijo (drop brez null-a) in get_aim_cells predogled.
extends BaseItem

func _init():
	id = "drillmaster"

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
