@tool
extends PanelContainer

# =================================================================
# 🔗 1. ربط عناصر الواجهة (UI Connections)
# =================================================================
# --- تبويب المهندس ---
@onready var prompt_input: TextEdit = %PromptInput
@onready var system_input: TextEdit = %SystemInput
@onready var api_key_input: LineEdit = %ApiKeyInput
@onready var status_label: Label = %StatusLabel
@onready var model_selector: OptionButton = %ModelSelector
@onready var lang_selector: OptionButton = %LangSelector # <-- الزر الجديد للغة

# الأزرار الرئيسية
@onready var generate_btn: Button = %GenerateBtn
@onready var read_script_btn: Button = %ReadScriptBtn
@onready var apply_edits_btn: Button = %ApplyEditsBtn
@onready var enhance_eng_btn: Button = %EnhanceEngBtn
@onready var fix_error_btn: Button = %FixErrorBtn

# أزرار الإعدادات
@onready var save_key_btn: Button = %SaveKeyBtn
@onready var refresh_models_btn: Button = %RefreshModelsBtn

# --- تبويب المخطط (Planner Tab / Kanban) ---
@onready var plan_input: TextEdit = %PlanInput
@onready var create_plan_btn: Button = %CreatePlanBtn
@onready var plan_status: Label = %PlanStatus
@onready var enhance_plan_btn: Button = %EnhancePlanBtn
@onready var add_manual_task_btn: Button = %AddManualTaskBtn

# أعمدة الكانبان
@onready var col_todo: BoxContainer = %Col_Todo
@onready var col_doing: BoxContainer = %Col_Doing
@onready var col_done: BoxContainer = %Col_Done

# =================================================================
# ⚙️ 2. المتغيرات والترجمة
# =================================================================
var http_request: HTTPRequest
var models_http: HTTPRequest
const SETTINGS_PATH = "user://ai_architect_settings.cfg"

# متغيرات الحالة
var last_generated_code: String = ""
var is_planning_mode: bool = false
var is_enhancing_mode: bool = false
var target_input_box: TextEdit = null
var pending_files: Array = []
var current_lang: String = "ar" # اللغة الافتراضية

# قاموس النصوص والشروحات
var TRANSLATIONS = {
	"en": {
		"gen_code": "Generate Code",
		"read_script": "Read File",
		"apply": "Apply Edits",
		"enhance": "✨ Improve",
		"fix_err": "🚑 Fix Error",
		"gen_plan": "Generate Plan",
		"add_manual": "+ Add Manual",
		"status_ready": "System Ready.",
		"tooltip_gen": "Generate GDScript code based on your prompt.",
		"tooltip_read": "Read current opened script context.",
		"tooltip_apply": "Review and write proposed changes to files.",
		"tooltip_enhance": "Rewrite your prompt to be more professional.",
		"tooltip_fix": "Paste error log to get a fix.",
		"tooltip_plan": "Create technical task list.",
		"tooltip_manual": "Add manual task to To-Do list."
	},
	"ar": {
		"gen_code": "توليد كود",
		"read_script": "قراءة ملف",
		"apply": "تطبيق التعديلات",
		"enhance": "✨ تحسين الطلب",
		"fix_err": "🚑 إصلاح خطأ",
		"gen_plan": "إنشاء خطة",
		"add_manual": "+ إضافة يدوية",
		"status_ready": "النظام جاهز.",
		"tooltip_gen": "إنشاء كود GDScript بناءً على وصفك.",
		"tooltip_read": "قراءة محتوى السكربت المفتوح حالياً.",
		"tooltip_apply": "مراجعة وتطبيق التغييرات المقترحة.",
		"tooltip_enhance": "إعادة صياغة طلبك ليكون أوضح للذكاء.",
		"tooltip_fix": "الصق الخطأ هنا ليتم إصلاحه.",
		"tooltip_plan": "تحويل الفكرة إلى مهام تقنية.",
		"tooltip_manual": "إضافة النص أعلاه كمهمة جديدة."
	}
}

# =================================================================
# 🚀 3. التهيئة والتشغيل
# =================================================================
func _ready() -> void:
	http_request = HTTPRequest.new()
	models_http = HTTPRequest.new()
	add_child(http_request)
	add_child(models_http)
	
	http_request.request_completed.connect(_on_request_completed)
	models_http.request_completed.connect(_on_models_fetched)
	
	# ربط الأزرار
	if generate_btn: generate_btn.pressed.connect(_on_generate_pressed)
	if read_script_btn: read_script_btn.pressed.connect(_on_read_script_pressed)
	if apply_edits_btn: apply_edits_btn.pressed.connect(_on_apply_edits_pressed)
	if save_key_btn: save_key_btn.pressed.connect(save_settings)
	if refresh_models_btn: refresh_models_btn.pressed.connect(fetch_available_models)
	if create_plan_btn: create_plan_btn.pressed.connect(_on_create_plan_pressed)
	if add_manual_task_btn: add_manual_task_btn.pressed.connect(_on_add_manual_task_pressed) # سيتم إضافتها في الجزء الثاني
	
	# ربط الأزرار الجديدة (التحسين والإصلاح)
	if enhance_eng_btn: enhance_eng_btn.pressed.connect(func(): _on_enhance_pressed(prompt_input))
	if enhance_plan_btn: enhance_plan_btn.pressed.connect(func(): _on_enhance_pressed(plan_input))
	if fix_error_btn: fix_error_btn.pressed.connect(_on_fix_error_pressed)
	
	# إعداد قائمة اللغة
	if lang_selector:
		lang_selector.clear()
		lang_selector.add_item("العربية", 0)
		lang_selector.add_item("English", 1)
		lang_selector.item_selected.connect(_on_language_changed)
	
	load_settings()
	_setup_model_selector()
	_update_ui_language()

func _setup_model_selector():
	if model_selector.item_count == 0:
		model_selector.add_item("gemini-2.0-flash-exp")
		model_selector.add_item("gemini-1.5-flash") 

# =================================================================
# 🌐 4. نظام اللغة (Localization)
# =================================================================
func _on_language_changed(index: int):
	current_lang = "ar" if index == 0 else "en"
	_update_ui_language()

func _update_ui_language():
	var t = TRANSLATIONS[current_lang]
	var is_rtl = (current_lang == "ar")
	
	# تحديث النصوص والشروحات (Tooltips)
	generate_btn.text = t["gen_code"]; generate_btn.tooltip_text = t["tooltip_gen"]
	read_script_btn.text = t["read_script"]; read_script_btn.tooltip_text = t["tooltip_read"]
	apply_edits_btn.text = t["apply"]; apply_edits_btn.tooltip_text = t["tooltip_apply"]
	enhance_eng_btn.text = t["enhance"]; enhance_eng_btn.tooltip_text = t["tooltip_enhance"]
	fix_error_btn.text = t["fix_err"]; fix_error_btn.tooltip_text = t["tooltip_fix"]
	create_plan_btn.text = t["gen_plan"]; create_plan_btn.tooltip_text = t["tooltip_plan"]
	enhance_plan_btn.text = t["enhance"]; enhance_plan_btn.tooltip_text = t["tooltip_enhance"]
	add_manual_task_btn.text = t["add_manual"]; add_manual_task_btn.tooltip_text = t["tooltip_manual"]
	
	# اتجاه الواجهة
	layout_direction = Control.LAYOUT_DIRECTION_RTL if is_rtl else Control.LAYOUT_DIRECTION_LTR
	status_label.text = t["status_ready"]

# =================================================================
# 💾 إدارة الإعدادات
# =================================================================
func save_settings() -> void:
	var key = api_key_input.text.strip_edges()
	var sys = system_input.text
	if key.is_empty():
		status_label.text = "Error: API Key is empty!"
		status_label.modulate = Color.RED
		return
	var config = ConfigFile.new()
	config.set_value("auth", "api_key", key)
	config.set_value("behavior", "system_prompt", sys)
	config.save(SETTINGS_PATH)
	status_label.text = "Settings Saved."
	status_label.modulate = Color.GREEN

func load_settings() -> void:
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		api_key_input.text = config.get_value("auth", "api_key", "")
		system_input.text = config.get_value("behavior", "system_prompt", "You are a Godot 4 expert.")
		status_label.text = "System Ready."

# =================================================================
# 👁️ الوعي بالسياق
# =================================================================
func _on_read_script_pressed() -> void:
	var script_editor = EditorInterface.get_script_editor()
	var current_script = script_editor.get_current_script()
	if current_script:
		var path = current_script.resource_path
		var code = current_script.source_code
		var context_msg = "\n\n--- FILE CONTEXT: %s ---\n%s\n--- END FILE ---\n" % [path, code]
		prompt_input.text += context_msg
		prompt_input.set_caret_line(prompt_input.get_line_count())
		status_label.text = "Read: " + path.get_file()
		status_label.modulate = Color.CYAN
	else:
		status_label.text = "No script is currently open."
		status_label.modulate = Color.RED

# =================================================================
# 🧠 المحرك الذكي (تم تحديثه)
# =================================================================
func _on_generate_pressed() -> void:
	is_planning_mode = false
	is_enhancing_mode = false
	var user_prompt = prompt_input.text
	var project_context = _get_project_structure()
	
	var strict_instruction = """
	CRITICAL INSTRUCTIONS (GODOT 4.x EXPERT):
	1. OUTPUT: strictly JSON Array [{"path": "res://...", "content": "..."}].
	2. SYNTAX: Godot 4.x ONLY (@tool, @export).
	3. CONTEXT: Use existing files from list below.
	%s
	""" % project_context
	
	if "--- FILE CONTEXT" in user_prompt:
		strict_instruction += "\nFOCUSED CONTEXT: User provided a specific file above."
	_send_request(user_prompt + strict_instruction)

func _on_create_plan_pressed() -> void:
	is_planning_mode = true
	is_enhancing_mode = false
	var user_idea = plan_input.text
	if user_idea.is_empty(): return
	status_label.text = "Architecting Plan..."
	var planner_instructions = """
	ROLE: Senior Godot 4 Project Lead.
	GOAL: Break down request into technical tasks.
	OUTPUT: JSON Array [{"task": "...", "type": "script"}] ONLY.
	""" 
	_send_request(planner_instructions + "\nUser Idea: " + user_idea)

# 🔥 دالة التحسين (المترجم التقني والمصحح)
func _on_enhance_pressed(target_box: TextEdit) -> void:
	var text = target_box.text
	if text.is_empty():
		status_label.text = "Write something to enhance!"
		return
	
	is_enhancing_mode = true
	target_input_box = target_box
	status_label.text = "Refining & Translating..."
	
	# هذا البرومبت مصمم خصيصاً لطلبك:
	# 1. يترجم أي لغة للإنجليزية.
	# 2. يستخدم مصطلحات جودوت.
	# 3. يمنع الإضافات غير المطلوبة.
	var prompt = """
	ROLE: Technical Translator & Godot 4 Refiner.
	INPUT: "%s"
	
	TASK:
	1. Translate the input to clean English (if it's in Arabic or mixed).
	2. Convert vague descriptions into specific Godot 4 technical terms (Nodes, Signals, Vector math).
	3. KEEP IT CONCISE. Do not add features I didn't ask for. Do not explain.
	4. Format: Just the refined technical prompt ready for code generation.
	
	EXAMPLE INPUT: "ابغى لاعب ينط ويمشي"
	EXAMPLE OUTPUT: "Create a CharacterBody2D with basic movement (speed, gravity) and jump logic using move_and_slide()."
	""" % text
	
	_send_request(prompt)

# 🔥 دالة إصلاح الأخطاء (الجديدة)
func _on_fix_error_pressed() -> void:
	var error_msg = prompt_input.text.strip_edges()
	if error_msg.is_empty():
		status_label.text = "⚠️ Paste error from Output first!"
		return

	var current_script = EditorInterface.get_script_editor().get_current_script()
	if not current_script:
		status_label.text = "⚠️ Open the broken script first!"
		return
		
	var code = current_script.source_code
	var path = current_script.resource_path
	status_label.text = "Analyzing Error..."
	
	var debug_prompt = """
	ROLE: Expert Godot 4 Debugger.
	TASK: Fix the code based on the error.
	BROKEN FILE: %s
	CODE:
	%s
	ERROR:
	%s
	OUTPUT: JSON Array with fixed code.
	""" % [path, code, error_msg]
	
	_send_request(debug_prompt)

# --- إرسال الطلب ---
func _send_request(prompt_text: String) -> void:
	var key = api_key_input.text.strip_edges()
	if key.is_empty():
		status_label.text = "API Key Missing!"
		return
	var model = model_selector.get_item_text(model_selector.selected)
	status_label.text = "Thinking..."
	status_label.modulate = Color.YELLOW
	generate_btn.disabled = true
	create_plan_btn.disabled = true
	
	var url = "https://generativelanguage.googleapis.com/v1beta/models/" + model + ":generateContent?key=" + key
	var final_prompt = "System: %s\nUser: %s" % [system_input.text, prompt_text]
	var headers = ["Content-Type: application/json"]
	var body = { "contents": [{ "parts": [{ "text": final_prompt }] }] }
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

# =================================================================
# 📩 7. استقبال وتحليل الرد (Response Handler)
# =================================================================
func _on_request_completed(result, code, headers, body):
	generate_btn.disabled = false
	create_plan_btn.disabled = false
	
	if code != 200:
		status_label.text = "API Error: " + str(code)
		return
		
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json or not "candidates" in json:
		status_label.text = "Invalid AI Response"
		return

	var content = json["candidates"][0]["content"]["parts"][0]["text"]
	
	# 1. وضع التحسين (تحديث مربع النص) - تم الإصلاح
	if is_enhancing_mode and target_input_box:
		target_input_box.text = content.strip_edges()
		status_label.text = "Text Enhanced! ✨"
		status_label.modulate = Color.GREEN
		
	# 2. وضع التخطيط (Kanban Board)
	elif is_planning_mode:
		plan_status.text = "Building Kanban Board..."
		_clear_cards_only(col_todo)
		_clear_cards_only(col_doing)
		_clear_cards_only(col_done)
		
		var json_start = content.find("[")
		var json_end = content.rfind("]")
		if json_start != -1 and json_end != -1:
			var clean_json = content.substr(json_start, json_end - json_start + 1)
			var plan_data = JSON.parse_string(clean_json)
			if plan_data is Array:
				for task in plan_data:
					var task_title = task.get("task", "Unnamed Task")
					_create_kanban_card(task_title, col_todo) # استدعاء الدالة من الجزء الثاني
				status_label.text = "✅ Kanban Board Ready!"
				plan_status.text = "Plan Generated."
			else:
				status_label.text = "Error: Invalid Plan Format."
		else:
			status_label.text = "Error: No JSON Array found."

	# 3. وضع المهندس والإصلاح
	else:
		status_label.text = "Code Generated (Check Output)"
		_process_generated_code(content)

func _process_generated_code(ai_text: String):
	var clean_text = ai_text.replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(clean_text)
	if parsed is Array:
		pending_files = parsed
		status_label.text = "Changes Proposed! Click 'Apply Edits'."
		status_label.modulate = Color.YELLOW
		
		# إذا كان الطلب من زر "Fix Error"، نفتح نافذة المراجعة تلقائياً
		_on_apply_edits_pressed() 
	else:
		print("AI Response (Not JSON):\n", clean_text)
		status_label.text = "Error: Invalid Response Format."

# =================================================================
# 🛡️ نظام إدارة الملفات الآمن
# =================================================================

func _get_formatted_datetime() -> String:
	var time = Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [time.year, time.month, time.day, time.hour, time.minute, time.second]

func _create_files(files: Array) -> void:
	var history_dir = "res://_ai_history/"
	if not DirAccess.dir_exists_absolute(history_dir):
		DirAccess.make_dir_recursive_absolute(history_dir)

	for item in files:
		var path: String = item.get("path", "")
		var content: String = item.get("content", "")
		if not path.begins_with("res://"):
			path = "res://" + path.trim_prefix("/")
			print("🔧 Auto-fixed path to: ", path)
		if path.is_empty(): continue
		var target_dir = path.get_base_dir()
		if not DirAccess.dir_exists_absolute(target_dir):
			DirAccess.make_dir_recursive_absolute(target_dir)

		# النسخ الاحتياطي
		if FileAccess.file_exists(path):
			var file_name = path.get_file()
			var backup_name = "%s_%s.%s" % [file_name.get_basename(), _get_formatted_datetime(), path.get_extension()]
			DirAccess.copy_absolute(path, history_dir + backup_name)

		# الكتابة الذكية
		if ResourceLoader.exists(path) and path.ends_with(".gd"):
			var res = load(path)
			if res is Script:
				res.source_code = content
				ResourceSaver.save(res, path)
				res.reload()
				print("⚡ Hot Reloaded: ", path)
			else:
				var f = FileAccess.open(path, FileAccess.WRITE)
				if f: f.store_string(content); f.close()
		else:
			var f = FileAccess.open(path, FileAccess.WRITE)
			if f: f.store_string(content); f.close(); print("✅ Created New File: ", path)
	
	EditorInterface.get_resource_filesystem().scan()
	if status_label:
		status_label.text = "Files Processed Successfully."
		status_label.modulate = Color.GREEN

const DIFF_SCENE = preload("res://addons/ai_architect/_ui/diff_viewer.tscn")

func _on_apply_edits_pressed() -> void:
	if pending_files.is_empty():
		status_label.text = "No pending changes."
		return
	var file_data = pending_files[0]
	var path = file_data.get("path", "")
	var new_content = file_data.get("content", "")
	var old_content = ""
	if FileAccess.file_exists(path):
		old_content = FileAccess.get_file_as_string(path)
	
	var diff_window = DIFF_SCENE.instantiate()
	EditorInterface.get_editor_main_screen().add_child(diff_window)
	diff_window.setup_diff(old_content, new_content)
	
	diff_window.applied.connect(func():
		_create_files([file_data])
		pending_files.remove_at(0)
		if not pending_files.is_empty(): _on_apply_edits_pressed()
		else: status_label.text = "✅ All changes applied!"
	)
	diff_window.rejected.connect(func():
		pending_files.remove_at(0)
		status_label.text = "❌ Change rejected."
		if not pending_files.is_empty(): _on_apply_edits_pressed()
	)

# =================================================================
# 👁️ قارئ سياق المشروع (Scanner)
# =================================================================
func _get_project_structure() -> String:
	var structure_text = "CURRENT PROJECT FILE STRUCTURE:\n"
	var root_path = "res://"
	var files = _scan_dir_recursive(root_path)
	if files.size() > 60:
		files = files.slice(0, 60)
		files.append("... (List truncated)")
	for f in files: structure_text += "- " + f + "\n"
	return structure_text

func _scan_dir_recursive(path: String) -> Array:
	var file_list = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not file_name.begins_with(".") and not file_name.begins_with("_") and file_name != "addons":
				var full_path = path.path_join(file_name)
				if dir.current_is_dir(): file_list.append_array(_scan_dir_recursive(full_path))
				else:
					var ext = file_name.get_extension()
					if ext in ["gd", "tscn", "tres", "cfg"]: file_list.append(full_path)
			file_name = dir.get_next()
		dir.list_dir_end()
	return file_list

# =================================================================
# 🧩 8. وظائف إضافية (Helpers & Card Logic)
# =================================================================

# دالة تنفيذ المهمة من الكانبان
func _execute_kanban_task(task_text: String) -> void:
	# الانتقال لتبويب المهندس
	var tab_container = find_child("TabContainer", true, false)
	if tab_container and tab_container is TabContainer:
		tab_container.current_tab = 0
	
	# وضع الأمر في المربع وتشغيله
	prompt_input.text = "Implement this task: " + task_text
	_on_generate_pressed()

# دالة جلب الموديلات
func fetch_available_models() -> void:
	var key = api_key_input.text
	if key.is_empty(): return
	status_label.text = "Updating Models..."
	refresh_models_btn.disabled = true
	models_http.request("https://generativelanguage.googleapis.com/v1beta/models?key=" + key)

func _on_models_fetched(result, code, headers, body):
	refresh_models_btn.disabled = false
	if code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		model_selector.clear()
		for m in json["models"]:
			if "generateContent" in m["supportedGenerationMethods"]:
				model_selector.add_item(m["name"].replace("models/", ""))
		status_label.text = "Models Updated."
		status_label.modulate = Color.GREEN
	else:
		status_label.text = "Fetch Error."

# دالة مساعدة لحذف البطاقات وترك العنوان
func _clear_cards_only(column: BoxContainer):
	while column.get_child_count() > 1:
		var child = column.get_child(1)
		column.remove_child(child)
		child.queue_free()

# دالة الزر اليدوي (مع إصلاح مشكلة نص Refine)
func _on_add_manual_task_pressed() -> void:
	var text = plan_input.text.strip_edges()
	
	if text.is_empty():
		status_label.text = "Write a task first!"
		return
	
	# 🔥 الإصلاح هنا: إزالة عبارة "Refine/Fix..." إذا كانت موجودة في البداية
	# عشان المهمة تطلع نظيفة في البطاقة
	var prefix = "Refine/Fix this task: "
	if text.begins_with(prefix):
		text = text.replace(prefix, "")
	
	_create_kanban_card(text, col_todo)
	
	plan_input.text = "" 
	status_label.text = "Manual Task Added."

# دالة إنشاء البطاقة (مع التعريب والشروحات)
func _create_kanban_card(task_text: String, target_column: BoxContainer) -> void:
	var card = PanelContainer.new()
	# التأكد من المسار الصحيح للسكربت
	card.set_script(load("res://addons/ai_architect/_ui/kanban_card.gd"))
	card.mouse_filter = Control.MOUSE_FILTER_PASS 
	
	# الستايل
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.20, 0.22)
	style.border_width_left = 4
	style.border_color = Color(0.2, 0.6, 1.0) # أزرق
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	card.add_theme_stylebox_override("panel", style)
	
	var box = VBoxContainer.new()
	card.add_child(box)
	
	# --- الهيدر (العنوان + حذف) ---
	var header_hbox = HBoxContainer.new()
	box.add_child(header_hbox)
	
	var lbl = Label.new()
	lbl.text = task_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(lbl)
	
	# زر الحذف
	var del_btn = Button.new()
	del_btn.text = "×"
	del_btn.flat = true
	del_btn.add_theme_color_override("font_color", Color.RED)
	# شرح الزر حسب اللغة
	del_btn.tooltip_text = "Delete Task" if current_lang == "en" else "حذف المهمة"
	del_btn.pressed.connect(func(): 
		card.queue_free()
	)
	header_hbox.add_child(del_btn)
	
	# --- الأزرار السفلية (Actions) ---
	var actions_hbox = HBoxContainer.new()
	box.add_child(actions_hbox)

	# زر التنفيذ
	var exec_btn = Button.new()
	# تعريب النص
	exec_btn.text = "▶ Execute" if current_lang == "en" else "▶ تنفيذ"
	exec_btn.tooltip_text = "Generate code for this task" if current_lang == "en" else "توليد كود لهذه المهمة"
	exec_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exec_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	exec_btn.pressed.connect(func(): _execute_kanban_task(task_text))
	actions_hbox.add_child(exec_btn)

	# زر التحسين/التعديل
	var edit_btn = Button.new()
	edit_btn.text = "✨ Refine" if current_lang == "en" else "✨ تعديل"
	edit_btn.tooltip_text = "Send back to input to edit/ask AI" if current_lang == "en" else "إرسال لمربع النص للتعديل أو سؤال الذكاء"
	edit_btn.pressed.connect(func():
		# عند الضغط، نرسل النص للمربع ونضيف البادئة ليعرف المستخدم أنه وضع تعديل
		plan_input.text = "Refine/Fix this task: " + task_text
		status_label.text = "Ready to refine..." if current_lang == "en" else "جاهز للتعديل..."
	)
	actions_hbox.add_child(edit_btn)
	
	target_column.add_child(card)
	
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 8
	target_column.add_child(spacer)
