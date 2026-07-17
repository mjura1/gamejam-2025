extends SceneTree

# Drives the real Shop buy/sell panels headlessly: buys extra_move via the
# BUY row button, sells it back via the SELL row button, sells a reserve
# piece, then forces a single-piece active roster and checks the last-active
# -piece SELL button is disabled and refuses to sell (never leave active
# party empty - same guard as move_active_to_reserve).
# Panels queue_free() their old rows on refresh, and any add_child() called
# mid-_process() is deferred (same reason GameFlow._change_scene_instance
# uses call_deferred) - so this polls for readiness each step instead of
# assuming a fixed frame count, unlike smoke_upgrade_panel.gd's panel (which
# is only ever added once, from _initialize()).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_shop.gd --quit-after 8

var player_manager
var buy_panel
var sell_panel
var fails := 0

var bought := false
var sold_item := false
var sold_reserve := false
var checked_last_active := false

func _initialize():
	print(">>> SMOKE TEST: shop buy/sell flow <<<")

	player_manager = root.get_node("PlayerManager")
	player_manager.setStarting() # roster: 3x friendly_pawn
	var reserve: Array[String] = ["friendly_rook"]
	player_manager.reserve_party = reserve

	_check("buying with 0 upgrade items is refused", not player_manager.try_buy_item("extra_move"))
	player_manager.add_upgrade_items(2)

	var buy_scene: PackedScene = load("res://Scenes/Menu/ShopBuyPanel.tscn")
	buy_panel = buy_scene.instantiate()
	buy_panel.name = "ShopBuyPanelNode"
	root.add_child(buy_panel)

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _buy_row_button() -> Button:
	if not is_instance_valid(buy_panel) or buy_panel.item_list.get_child_count() == 0:
		return null
	return buy_panel.item_list.get_child(0).get_child(2) # icon, info, button

func _sell_item_row_button() -> Button:
	if not is_instance_valid(sell_panel) or sell_panel.item_list.get_child_count() == 0:
		return null
	return sell_panel.item_list.get_child(0).get_child(2) # icon, label, button

func _process(_delta: float) -> bool:
	if not bought:
		var b := _buy_row_button()
		if b == null:
			return false # still waiting for the buy panel's first _refresh()
		if b.text != "BUY (1)":
			return false # rebuild in flight, check again next frame
		_check("BUY row offers extra_move at cost 1", not b.disabled)
		b.pressed.emit()
		_check("buying spent upgrade items", player_manager.upgrade_items == 1)
		_check("buying granted 1x extra_move", player_manager.get_item_count("extra_move") == 1)
		bought = true
		buy_panel.close_menu()
		var sell_scene: PackedScene = load("res://Scenes/Menu/ShopSellPanel.tscn")
		sell_panel = sell_scene.instantiate()
		sell_panel.name = "ShopSellPanelNode"
		root.call_deferred("add_child", sell_panel)
		return false

	if not sold_item:
		var b := _sell_item_row_button()
		if b == null:
			return false # still waiting for the sell panel to enter the tree / refresh
		_check("SELL item row shows the bought extra_move", b.text == "SELL (1)")
		_check("PIECE list shows 3 active + 1 reserve rows", sell_panel.piece_list.get_child_count() == 4)
		b.pressed.emit()
		_check("selling the item refunded upgrade items", player_manager.upgrade_items == 2)
		_check("selling the item removed it from inventory", player_manager.get_item_count("extra_move") == 0)
		sold_item = true
		return false

	if not sold_reserve:
		if sell_panel.piece_list.get_child_count() < 4:
			return false # rebuild in flight
		# Zadnja vrstica (index 3) je RESERVE (friendly_rook) - glej _rebuild_piece_list.
		var reserve_row: Node = sell_panel.piece_list.get_child(3)
		var reserve_button: Button = reserve_row.get_child(2)
		_check("reserve piece SELL button is enabled", not reserve_button.disabled)
		reserve_button.pressed.emit()
		_check("selling the reserve piece refunded upgrade items", player_manager.upgrade_items == 3)
		_check("reserve_party is now empty", player_manager.reserve_party.is_empty())
		sold_reserve = true
		# Prisilimo scenarij "zadnja aktivna figura" in preverimo zaščito.
		var single: Array[String] = ["friendly_pawn"]
		player_manager.friendly_party = single
		player_manager.party_changed.emit()
		return false

	if not checked_last_active:
		if sell_panel.piece_list.get_child_count() != 1:
			return false # rebuild in flight
		var active_row: Node = sell_panel.piece_list.get_child(0)
		var active_button: Button = active_row.get_child(2)
		_check("last active piece SELL button is disabled", active_button.disabled)
		var before_size: int = player_manager.friendly_party.size()
		active_button.pressed.emit()
		_check("selling the last active piece is refused", player_manager.friendly_party.size() == before_size)
		checked_last_active = true
		sell_panel.close_menu()

		if fails == 0:
			print(">>> SMOKE TEST: shop buy/sell flow completed cleanly <<<")
		else:
			print("SMOKE TEST FAIL: %d shop checks failed" % fails)
		return false

	return false
