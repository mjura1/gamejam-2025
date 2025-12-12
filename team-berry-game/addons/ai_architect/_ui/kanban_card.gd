@tool
extends PanelContainer

func _ready():
	# جعل البطاقة تسمح بمرور الماوس للعمود الخلفي
	mouse_filter = Control.MOUSE_FILTER_PASS

# هذه الدالة تعمل تلقائياً عندما يحاول المستخدم سحب البطاقة
func _get_drag_data(at_position: Vector2) -> Variant:
	# 1. إنشاء نسخة مرئية (Preview) تتبع الماوس
	var preview = PanelContainer.new()
	preview.modulate = Color(1, 1, 1, 0.8) # شفافية بسيطة
	
	# نسخ الستايل والحجم لجعلها تشبه البطاقة الأصلية
	preview.add_theme_stylebox_override("panel", get_theme_stylebox("panel"))
	preview.custom_minimum_size = size
	
	# إضافة نص بسيط للنسخة
	var lbl = Label.new()
	# نحاول جلب النص من البطاقة الأصلية
	var original_lbl = find_child("Label", true, false)
	if original_lbl: lbl.text = original_lbl.text
	preview.add_child(lbl)
	
	# ضبط النسخة لتتبع الماوس من المنتصف
	set_drag_preview(preview)
	
	# 2. إرجاع الكائن نفسه (عشان العمود يعرف مين اللي قاعد ينسحب)
	return self
