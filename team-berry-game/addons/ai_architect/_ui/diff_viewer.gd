@tool
extends Window

# إشارات (Signals) لنعرف قرار المستخدم
signal applied
signal rejected

@onready var old_edit: CodeEdit = %OldEdit
@onready var new_edit: CodeEdit = %NewEdit
@onready var apply_btn: Button = %ApplyBtn
@onready var reject_btn: Button = %RejectBtn

func _ready() -> void:
	# ربط إشارة الإغلاق ( زر X في النافذة)
	close_requested.connect(_on_reject_pressed)
	
	# ربط الأزرار إذا كانت موجودة
	if apply_btn: apply_btn.pressed.connect(_on_apply_pressed)
	if reject_btn: reject_btn.pressed.connect(_on_reject_pressed)

# دالة الاستدعاء الرئيسية: نرسل لها النص القديم والجديد
func setup_diff(old_text: String, new_text: String):
	old_edit.text = old_text
	new_edit.text = new_text
	
	_highlight_changes(old_text, new_text)
	
	# إظهار النافذة في المنتصف
	popup_centered()

func _on_apply_pressed():
	applied.emit() # نرسل إشارة الموافقة
	queue_free()   # نغلق النافذة

func _on_reject_pressed():
	rejected.emit() # نرسل إشارة الرفض
	queue_free()    # نغلق النافذة

# 🎨 خوارزمية تلوين الفروقات (بسيطة)
func _highlight_changes(t1: String, t2: String):
	var lines1 = t1.split("\n")
	var lines2 = t2.split("\n")
	var max_lines = max(lines1.size(), lines2.size())
	
	var color_added = Color(0, 1, 0, 0.15)   # أخضر فاتح للإضافة
	var color_removed = Color(1, 0, 0, 0.15) # أحمر فاتح للحذف
	var color_mod = Color(1, 1, 0, 0.15)     # أصفر للتعديل
	
	for i in range(max_lines):
		var l1 = lines1[i] if i < lines1.size() else ""
		var l2 = lines2[i] if i < lines2.size() else ""
		
		if l1 != l2:
			if l1 == "":
				# سطر جديد (أخضر في اليمين)
				new_edit.set_line_background_color(i, color_added)
			elif l2 == "":
				# سطر محذوف (أحمر في اليسار)
				old_edit.set_line_background_color(i, color_removed)
			else:
				# سطر معدل (أصفر في الاثنين)
				old_edit.set_line_background_color(i, color_mod)
				new_edit.set_line_background_color(i, color_mod)
