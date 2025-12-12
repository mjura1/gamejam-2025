@tool
extends VBoxContainer


# هل يمكن الإفلات هنا؟
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# نقبل فقط إذا كان الشيء المسحوب هو "بطاقة" (PanelContainer)
	return data is PanelContainer

# ماذا يحدث عند الإفلات؟
func _drop_data(at_position: Vector2, data: Variant) -> void:
	var card = data
	var old_parent = card.get_parent()
	
	# نقل البطاقة من العمود القديم إلى هذا العمود
	if old_parent != self:
		old_parent.remove_child(card)
		add_child(card)
		
		# (اختياري) تشغيل صوت أو طباعة للتأكيد
		print("🔄 Task Moved to: ", name)
