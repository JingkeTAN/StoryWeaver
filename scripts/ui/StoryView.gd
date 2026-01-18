# scripts/ui/StoryView.gd (附加到Main节点)
extends Control

@onready var story_text: RichTextLabel = $VBoxContainer/StoryDisplay/MarginContainer/StoryText
@onready var input_field: LineEdit = $VBoxContainer/InputArea/InputField
@onready var send_button: Button = $VBoxContainer/InputArea/SendButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
#@onready var story_engine: StoryEngine = $StoryEngine

var is_currently_processing: bool = false

func _ready():
	# 确认节点路径正确
	print("=== StoryView _ready 被调用 ===")
	print("send_button 路径: ", send_button.get_path())
	print("StoryEngineGlobal 路径: ", StoryEngineGlobal.get_path())
	# 连接信号
	send_button.pressed.connect(_on_send_pressed)
	input_field.text_submitted.connect(_on_input_submitted)
	# 验证连接
	print("=== 信号连接验证 ===")
	print("send_button 是否存在: ", send_button != null)
	print("input_field 是否存在: ", input_field != null)
	print("story_engine 是否存在: ", StoryEngineGlobal != null)
	
	
	
	StoryEngineGlobal.story_updated.connect(_on_story_updated)
	StoryEngineGlobal.processing_started.connect(_on_processing_started)
	StoryEngineGlobal.processing_finished.connect(_on_processing_finished)
	
	# 初始文本
	story_text.text = "[center][b]欢迎来到 StoryWeaver[/b][/center]\n\n输入你想要的剧情发展..."
	status_label.text = "就绪"

func _on_send_pressed():
	submit_input()

func _on_input_submitted(_text: String):
	submit_input()

func submit_input():
	print("\n=== submit_input 被调用 ===")
	print("is_currently_processing: ", is_currently_processing)
	if is_currently_processing:
		print("❌ 正在处理中，忽略")
		return
	
	var user_input = input_field.text.strip_edges()
	print("用户输入:", user_input)
	if user_input.is_empty():
		print("❌ 输入为空")
		return
	
	
	
		# 特殊指令：移动角色（/move 名字 位置）
	if user_input.begins_with("/move "): 
		var parts = user_input.split(" ")
		if parts.size() == 3:
			StoryEngineGlobal.world_state.update_character_location(parts[1], parts[2])
			append_to_story("\n[color=yellow]📍 %s 移动到 %s[/color]\n" % [parts[1], parts[2]])
		else:
			append_to_story("\n[color=red]用法: /move 角色名 地点[/color]\n")
		input_field.text = ""
		return
	
	# 特殊指令：查看位置
	if user_input == "/where":
		var locs = StoryEngineGlobal.world_state.character_locations
		var info = "\n[color=cyan]当前位置：\n"
		for char_name in locs.keys():
			info += "- %s: %s\n" % [char_name, locs[char_name]]
		info += "[/color]\n"
		append_to_story(info)
		input_field.text = ""
		return
		
	# 指令3：帮助
	if user_input == "/help":
		var help_text = """
[color=cyan]可用指令：

【模板系统】
- /template list        # 查看所有模板
- /template load <id>   # 加载模板
- /template info        # 当前模板信息

【角色控制】
- /move 角色名 地点     # 移动角色
- /where                # 查看所有角色位置
- /status               # 查看角色状态
- /set 角色 属性 值     # 设置角色属性

【存档管理】
- /save <槽位> [名称]   # 保存游戏
- /load <槽位>          # 加载游戏
- /saves                # 查看存档列表
- /delete <槽位>        # 删除存档
- /db info              # 查看数据库状态

【系统】
- /critic on/off        # 开启/关闭审查
- /help                 # 显示帮助
[/color]
"""
		append_to_story(help_text)
		input_field.text = ""
		return  
	
	# 指令4：设置角色属性
	if user_input.begins_with("/set "):
		var parts = user_input.split(" ")
		if parts.size() >= 4:
			var char_name = parts[1]
			var attr_id = parts[2]
			var value_str = parts[3]
			
			var character = StoryEngineGlobal.get_character(char_name)
			if character:
				if character is UniversalCharacter:
					# 尝试数值或字符串
					if value_str.is_valid_float():
						character.set_attr(attr_id, float(value_str))
					else:
						character.set_attr(attr_id, value_str)
					append_to_story("\n[color=yellow]✓ %s 的 %s 设为 %s[/color]\n" % [char_name, attr_id, value_str])
				else:
					# 旧版
					match attr_id:
						"hp":
							character.hp = int(value_str)
						"mana":
							character.mana = int(value_str)
					append_to_story("\n[color=yellow]✓ %s 的 %s 设为 %s[/color]\n" % [char_name, attr_id, value_str])
			else:
				append_to_story("\n[color=red]找不到角色: %s[/color]\n" % char_name)
		else:
			append_to_story("\n[color=red]用法: /set 角色名 属性 值[/color]\n")
		input_field.text = ""
		return

	
	# 指令5：切换审查模式
	if user_input == "/critic on":
		StoryEngineGlobal.concurrent_manager.enable_validation = true
		append_to_story("\n[color=green]🛡️ 审查系统已启用[/color]\n")
		input_field.text = ""
		return
	
	if user_input == "/critic off":
		StoryEngineGlobal.concurrent_manager.enable_validation = false
		append_to_story("\n[color=yellow]⚠️ 审查系统已禁用[/color]\n")
		input_field.text = ""
		return
	
	# 指令6：查看角色状态
	if user_input == "/status":
		var status_text = "\n[color=cyan]角色状态：\n"
		for character in StoryEngineGlobal.characters:
			if character.role_type == "narrator":
				continue
			
			if character is UniversalCharacter:
				status_text += "\n【%s】\n" % character.character_name
				status_text += character.get_state_summary()
			else:
				# 旧版 AICharacter
				status_text += "- %s: HP %d/%d, MP %d/%d\n" % [
					character.character_name,
					character.hp, character.max_hp,
					character.mana, character.max_mana
				]
		status_text += "[/color]\n"
		append_to_story(status_text)
		input_field.text = ""
		return
		
# 指令：模板列表
	if user_input == "/template list":
		var templates = StoryEngineGlobal.template_manager.get_template_list()
		var info = "\n[color=cyan]可用模板：\n"
		for tmpl in templates:
			var current = " [当前]" if StoryEngineGlobal.current_template and StoryEngineGlobal.current_template.template_id == tmpl.id else ""
			info += "- %s (%s)%s\n  %s\n" % [tmpl.name, tmpl.id, current, tmpl.description]
		info += "\n使用 /template load <id> 加载模板[/color]\n"
		append_to_story(info)
		input_field.text = ""
		return
	
	# 指令：加载模板
	if user_input.begins_with("/template load "):
		var template_id = user_input.replace("/template load ", "").strip_edges()
		if StoryEngineGlobal.switch_template(template_id):
			append_to_story("\n[color=green]✓ 已切换到模板: %s[/color]\n" % StoryEngineGlobal.current_template.template_name)
			append_to_story("[color=yellow]⚠️ 角色已重置为模板默认角色[/color]\n")
			# 清空故事日志
			StoryEngineGlobal.story_log.clear()
			story_text.text = ""
			append_to_story("[color=cyan]新故事开始...[/color]\n")
		else:
			append_to_story("\n[color=red]❌ 找不到模板: %s[/color]\n" % template_id)
		input_field.text = ""
		return
	
	# 指令：查看当前模板
	if user_input == "/template info":
		if StoryEngineGlobal.current_template:
			var tmpl = StoryEngineGlobal.current_template
			var info = "\n[color=cyan]当前模板：%s\n" % tmpl.template_name
			info += "ID: %s\n" % tmpl.template_id
			info += "描述: %s\n" % tmpl.description
			info += "世界设定:\n"
			for key in tmpl.world_settings.keys():
				info += "  - %s: %s\n" % [key, tmpl.world_settings[key]]
			info += "[/color]\n"
			append_to_story(info)
		else:
			append_to_story("\n[color=yellow]未加载模板[/color]\n")
		input_field.text = ""
		return
		
# 指令：保存游戏
	if user_input.begins_with("/save "):
		var parts = user_input.split(" ", true, 2)
		if parts.size() >= 2:
			var slot = int(parts[1]) if parts[1].is_valid_int() else 1
			var save_name = parts[2] if parts.size() > 2 else "手动存档"
			StoryEngineGlobal.save_game(slot, save_name)
			append_to_story("\n[color=green]💾 游戏已保存到槽位 %d: %s[/color]\n" % [slot, save_name])
		else:
			append_to_story("\n[color=red]用法: /save <槽位号> [存档名][/color]\n")
		input_field.text = ""
		return
	
	# 指令：加载游戏
	if user_input.begins_with("/load "):
		var slot = int(user_input.replace("/load ", "").strip_edges())
		if StoryEngineGlobal.load_game(slot):
			append_to_story("\n[color=green]📂 游戏已加载[/color]\n")
			# 清空显示并重新展示故事
			story_text.text = ""
			for storyLog in StoryEngineGlobal.story_log:
				append_to_story(storyLog + "\n---\n")
		else:
			append_to_story("\n[color=red]❌ 加载失败[/color]\n")
		input_field.text = ""
		return
	
	# 指令：存档列表
	if user_input == "/saves":
		var saves = StoryEngineGlobal.world_state.db_manager.get_save_list()
		if saves.size() == 0:
			append_to_story("\n[color=yellow]没有存档[/color]\n")
		else:
			var info = "\n[color=cyan]存档列表：\n"
			for save in saves:
				var time_str = Time.get_datetime_string_from_unix_time(save.time)
				info += "槽位 %d: %s\n  模板: %s | 时间: %s\n" % [
					save.slot,
					save.name,
					save.template,
					time_str
				]
			info += "\n使用 /load <槽位> 加载存档[/color]\n"
			append_to_story(info)
		input_field.text = ""
		return
	
	# 指令：删除存档
	if user_input.begins_with("/delete "):
		var slot = int(user_input.replace("/delete ", "").strip_edges())
		StoryEngineGlobal.world_state.db_manager.delete_save(slot)
		append_to_story("\n[color=yellow]🗑️ 已删除存档槽位 %d[/color]\n" % slot)
		input_field.text = ""
		return
		
	# 指令：重置数据库
	if user_input == "/db reset":
		DirAccess.remove_absolute("user://storyweaver.db")
		append_to_story("\n[color=yellow]🔄 数据库已删除，请重启游戏[/color]\n")
		input_field.text = ""
		return
	
	# 指令：数据库信息
	if user_input == "/db info":
		StoryEngineGlobal.world_state.db_manager.db.query("SELECT version FROM db_version")
		var version = "未知"
		if StoryEngineGlobal.world_state.db_manager.db.query_result.size() > 0:
			version = str(StoryEngineGlobal.world_state.db_manager.db.query_result[0]["version"])
		
		var info = "\n[color=cyan]数据库信息：\n"
		info += "路径: %s\n" % StoryEngineGlobal.world_state.db_manager.db_path
		info += "版本: %s\n" % version
		
		# 统计数据
		StoryEngineGlobal.world_state.db_manager.db.query("SELECT COUNT(*) as count FROM world_facts")
		var facts_count = StoryEngineGlobal.world_state.db_manager.db.query_result[0]["count"]
		info += "世界事实: %d 条\n" % facts_count
		
		StoryEngineGlobal.world_state.db_manager.db.query("SELECT COUNT(*) as count FROM save_slots")
		var saves_count = StoryEngineGlobal.world_state.db_manager.db.query_result[0]["count"]
		info += "存档: %d 个\n" % saves_count
		
		info += "[/color]\n"
		append_to_story(info)
		input_field.text = ""
		return
		
	print("用户输入: ", user_input)
	if user_input.is_empty():
		print("❌ 输入为空")
		return
	
	# 显示用户输入
	append_to_story("\n[color=cyan][b]你：[/b]%s[/color]\n" % user_input)
	
	# 清空输入框
	input_field.text = ""
	
	print("开始调用 StoryEngine.process_player_input...")
	# 处理
	StoryEngineGlobal.process_player_input(user_input)
	
	
	

func _on_story_updated(narrative: String):
	append_to_story("\n" + narrative + "\n")
	# 滚动到底部
	story_text.scroll_to_line(story_text.get_line_count())

func _on_processing_started():
	is_currently_processing = true
	send_button.disabled = true
	status_label.text = "AI思考中..."

func _on_processing_finished():
	is_currently_processing = false
	send_button.disabled = false
	status_label.text = "就绪"

func append_to_story(text: String):
	story_text.text += text
