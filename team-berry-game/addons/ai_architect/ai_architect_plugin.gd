@tool
extends EditorPlugin

# المسار الصحيح لواجهتك (بناءً على كودك السابق)
const MAIN_PANEL_SCENE = preload("res://addons/ai_architect/_ui/ai_dock.tscn")

var main_panel_instance

func _enter_tree() -> void:
	# 1. إنشاء نسخة من المشهد
	main_panel_instance = MAIN_PANEL_SCENE.instantiate()
	
	# 2. إضافتها إلى الشاشة الرئيسية (بدلاً من الـ Dock الجانبي)
	# لتظهر بجانب (2D, 3D, Script, AssetLib)
	EditorInterface.get_editor_main_screen().add_child(main_panel_instance)
	
	# إخفاؤها في البداية حتى يتم الضغط على الزر
	_make_visible(false)
	
	print("AI Architect: Main Screen Plugin Loaded.")

func _exit_tree() -> void:
	if main_panel_instance:
		main_panel_instance.queue_free()
		print("AI Architect: System Shut Down.")

# =================================================================
# إعدادات الشاشة الرئيسية (Main Screen Integration)
# =================================================================

# إخبار المحرك أن هذه الإضافة لها شاشة رئيسية
func _has_main_screen() -> bool:
	return true

# التحكم في الظهور عند التبديل بين التبويبات
func _make_visible(visible: bool) -> void:
	if main_panel_instance:
		main_panel_instance.visible = visible

# الاسم الذي سيظهر في الشريط العلوي
func _get_plugin_name() -> String:
	return "AI Architect"

# الأيقونة (نستخدم أيقونة عامة مؤقتاً)
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Node", "EditorIcons")
