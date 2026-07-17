# res://Scripts/Map/shop.gd
# Trgovina: cela soba na sredini mape (nivo 1 in 2, glej MapGenerator
# shop_floor), obiskana enkrat na mapo (kot tabor - RoomIcon jo označi kot
# selected takoj po prvem obisku). BUY/SELL odpreta CanvasLayer panel (glej
# CampfireUpgradePanel/CampfirePartyPanel za isti vzorec), LEAVE se vrne na mapo.
extends Control
class_name ShopController

const BUY_PANEL_SCENE := preload("res://Scenes/Menu/ShopBuyPanel.tscn")
const SELL_PANEL_SCENE := preload("res://Scenes/Menu/ShopSellPanel.tscn")


func _on_buy_pressed():
	UiAudio.play_click()
	if get_tree().root.find_child("ShopBuyPanelNode", true, false):
		return
	var instance = BUY_PANEL_SCENE.instantiate()
	instance.name = "ShopBuyPanelNode"
	get_tree().root.add_child(instance)


func _on_sell_pressed():
	UiAudio.play_click()
	if get_tree().root.find_child("ShopSellPanelNode", true, false):
		return
	var instance = SELL_PANEL_SCENE.instantiate()
	instance.name = "ShopSellPanelNode"
	get_tree().root.add_child(instance)


func _on_leave_pressed():
	UiAudio.play_click()
	GF.return_to_map()
