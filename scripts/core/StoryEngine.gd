# scripts/core/StoryEngine.gd
extends Node
class_name StoryEngine

signal story_updated(text: String)
signal processing_started()
signal processing_finished()
signal template_changed(template_name: String)

var api_client: APIClient
# 角色（支持两种类型）
var characters: Array = []  # 可以是 AICharacter 或 UniversalCharacter
var story_log: Array = []
# 世界状态和知识分发
var world_state: WorldState
var knowledge_distributor: KnowledgeDistributor
#并发管理和审查
var concurrent_manager: ConcurrentDecisionManager
var critic_agent: CriticAgent

# 模板系统
var template_manager: TemplateManager
var current_template: WorldTemplate

const MODEL_DESIGNER = "claude-haiku-4-5"
const MODEL_NARRATOR = "claude-haiku-4-5"

func _ready():
	print("=== StoryEngine 初始化 ===")
	api_client = APIClient.new()
	add_child(api_client)
	print("APIClient 已添加")
	
	# 初始化模板管理器
	template_manager = TemplateManager.new()
	print("✓ 模板管理器初始化，共 %d 个模板" % template_manager.templates.size())
	
	# 默认加载奇幻模板（兼容旧代码）
	if template_manager.templates.has("fantasy_adventure"):
		current_template = template_manager.get_template("fantasy_adventure")
	elif template_manager.templates.size() > 0:
		current_template = template_manager.templates.values()[0]
		
	# 初始化世界状态
	world_state = WorldState.new()
	knowledge_distributor = KnowledgeDistributor.new(world_state)
	print("✓ 世界状态系统初始化")
	# 初始化审查系统
	critic_agent = CriticAgent.new(api_client, world_state, current_template)
	print("✓ 审查系统初始化")
	# 初始化角色
	setup_default_characters()
	print("✓ StoryEngine 初始化完成")
	# 并发管理器
	concurrent_manager = ConcurrentDecisionManager.new()
	concurrent_manager.set_critic(critic_agent)  # 设置审查器
	concurrent_manager.enable_validation = true   # 启用审查
	add_child(concurrent_manager)
	print("✓ 并发管理器初始化")
	
# 切换模板
func switch_template(template_id: String) -> bool:
	var new_template = template_manager.get_template(template_id)
	if not new_template:
		push_error("找不到模板: " + template_id)
		return false
	
	current_template = new_template
	
	# 更新审查系统
	critic_agent.set_template(current_template)
	
	# 重新初始化角色
	setup_characters_for_template()
	
	# 更新世界状态的默认位置
	var default_location = current_template.world_settings.get("default_location", "未知")
	for char in characters:
		world_state.update_character_location(char.character_name, default_location)
	
	emit_signal("template_changed", current_template.template_name)
	print("✓ 已切换到模板: %s" % current_template.template_name)
	return true

# 根据模板设置角色
func setup_characters_for_template():
	characters.clear()
	
	if current_template == null:
		# 没有模板，使用旧版角色
		setup_default_characters()
		return
	
	# 根据模板类型创建角色
	match current_template.template_id:
		"romance_simulation":
			setup_romance_characters()
		"fantasy_adventure":
			setup_fantasy_characters()
		_:
			setup_generic_characters()
	
	# 更新世界状态中的角色位置
	var default_location = current_template.world_settings.get("default_location", "未知")
	world_state.character_locations.clear()
	for character in characters:
		world_state.character_locations[character.character_name] = default_location
	world_state.character_locations["旁白"] = "无处不在"
	
	var names = []
	for c in characters:
		names.append(c.character_name)
	print("✓ 角色初始化完成：", names)

# 恋爱模拟角色
func setup_romance_characters():
	var protagonist = UniversalCharacter.new(
		"小明",
		"普通但善良的大学生，有点内向但真诚",
		"protagonist",
		current_template
	)
	protagonist.gender = "male"
	protagonist.set_attr("energy", 80)
	protagonist.set_attr("mood", 60)
	protagonist.set_attr("loneliness", 40)
	protagonist.set_attr("money", 3000)
	
	var love_interest = UniversalCharacter.new(
		"小美",
		"温柔善良的女生，喜欢读书和音乐，有点害羞",
		"love_interest",
		current_template
	)
	love_interest.gender = "female"
	love_interest.set_attr("energy", 90)
	love_interest.set_attr("mood", 70)
	love_interest.set_attr("relationship_status", "单身")
	
	# 设置初始关系
	protagonist.set_relationship("小美", "affection", 30)
	protagonist.set_relationship("小美", "trust", 40)
	love_interest.set_relationship("小明", "affection", 25)
	love_interest.set_relationship("小明", "trust", 35)
	
	var narrator = UniversalCharacter.new(
		"旁白",
		"客观的故事讲述者",
		"narrator",
		current_template
	)
	
	characters = [protagonist, love_interest, narrator]

# 奇幻冒险角色
func setup_fantasy_characters():
	var protagonist = UniversalCharacter.new(
		"小白",
		"一个勇敢但略显鲁莽的年轻剑士，正义感强",
		"protagonist",
		current_template
	)
	protagonist.set_attr("hp", 100)
	protagonist.set_attr("max_hp", 100)
	protagonist.set_attr("mana", 50)
	protagonist.set_attr("max_mana", 50)
	
	var companion = UniversalCharacter.new(
		"木糖醇",
		"聪明机智的精灵法师，善于分析局势",
		"companion",
		current_template
	)
	companion.set_attr("hp", 80)
	companion.set_attr("max_hp", 80)
	companion.set_attr("mana", 100)
	companion.set_attr("max_mana", 100)
	
	var narrator = UniversalCharacter.new(
		"旁白",
		"客观的故事讲述者",
		"narrator",
		current_template
	)
	
	characters = [protagonist, companion, narrator]

# 通用角色（后备）
func setup_generic_characters():
	var protagonist = UniversalCharacter.new(
		"主角",
		"故事的主要人物",
		"protagonist",
		current_template
	)
	
	var companion = UniversalCharacter.new(
		"同伴",
		"主角的伙伴",
		"companion",
		current_template
	)
	
	var narrator = UniversalCharacter.new(
		"旁白",
		"客观的故事讲述者",
		"narrator",
		current_template
	)
	
	characters = [protagonist, companion, narrator]
	
# 完全没有模板时的后备方案
func setup_default_characters():
	var protagonist = AICharacter.new(
		"小白",
		"一个勇敢但略显鲁莽的年轻剑士，正义感强",
        "protagonist"
	)
	
	var companion = AICharacter.new(
		"木糖醇",
		"聪明机智的精灵法师，善于分析局势",
        "companion"
	)
	
	var narrator = AICharacter.new(
		"旁白",
		"客观的故事讲述者",
        "narrator"
	)
	
	characters = [protagonist, companion, narrator]
	var names := []
	for c in characters:
		names.append(c.character_name)
	print("✓ 角色初始化完成：", names)

# 主流程
func process_player_input(player_input: String):
	print("\n=== process_player_input 被调用 ===")
	emit_signal("processing_started")
	print("\n=== 处理玩家输入 ===")
	print("玩家: ", player_input)
	
	# 添加try-catch风格的错误处理
	var success = await _safe_process_input(player_input)
	
	if not success:
		emit_signal("story_updated", "[color=red]⚠️ 处理失败，请重试[/color]")
	
	emit_signal("processing_finished")
	
	# 安全处理包装
func _safe_process_input(player_input: String) -> bool:
	# Step 1: 设计师生成事件
	var event_data  = await generate_event_from_designer(player_input)
	# 验证设计师返回（添加这个检查！）
	if event_data.is_empty() or not event_data.has("description"):
		push_error("❌ 设计师返回数据无效")
		return false
		
	print("设计师生成事件: ", event_data.description)
	print("  参与者: ", event_data.get("participants", []))
		
	# Step 2: 将文本转为StoryEvent对象
	var event = StoryEvent.from_designer_output(event_data, get_all_character_names())
	var event_check = critic_agent.validate_event(event, characters)
	if not event_check.passed:
		print("⚠️ 事件预审查失败: %s" % event_check.feedback)
		# 可以选择：
		# 1. 重新生成事件
		# 2. 修改事件描述
		# 3. 继续但标记
		
	# Step 3: 知识分发 - 判断哪些角色知道这个事件
	var aware_characters = knowledge_distributor.determine_aware_characters(event, characters)
	
	if aware_characters.size() == 0:
	# ────────────────────────────────
	# 【设计决策 / Fallback Logic】
	# 当设计师（Designer GM）未能正确返回任何知情角色时（可能是 JSON 解析失败、prompt 不稳定等）
	# 我们故意让【所有非旁白角色】都知情并参与决策
	# 这是一个【安全兜底】策略，而非 bug
	# ────────────────────────────────
		print("⚠️ [KNOWLEDGE_FALLBACK]没有角色知道这个事件，让所有角色都知道（兜底）")
		aware_characters = get_non_narrator_characters()
		
	# Step 4: 只让知道的角色做出反应
	var responses = await gather_character_responses(event, aware_characters)
	# 验证响应
	if responses.size() == 0:
		push_warning("⚠️ 没有获取到任何角色响应")
		# 仍然继续，让讲述者描述事件

	# Step 5: 讲述者整合
	var narrative = await compose_narrative(event.description, responses)
	if narrative.is_empty():
		push_error("❌ 讲述者没有生成叙事")
		return false
	print("最终叙事: ", narrative)
	
	# Step 6: 应用行动效果（新增）
	apply_action_effects(responses)
	
	
	# Step 7: 记录到世界状态
	var known_by: Array[String] = []
	for c in aware_characters:
		known_by.append(c.character_name)
	world_state.record_event(event, known_by)
	
	# Step 8: 更新记忆（只给知道的角色）
	for character in aware_characters:
		character.add_memory(event.description, event.id)
	story_log.append(narrative)
	emit_signal("story_updated", narrative)
	return true 
# 设计师层
func generate_event_from_designer(player_input: String) -> Dictionary:
	var context = get_story_context()
	var location_info = get_location_info()
	var status_info = get_character_status_info()
	# 模板特定提示
	var template_hint = ""
	if current_template:
		template_hint = current_template.designer_prompt_extra
	
	
	var prompt = """
当前故事进展：
%s

角色位置：
%s

角色状态：
%s

%s

玩家需求："%s"

请设计事件，以JSON格式返回：
{
  "description": "事件的详细描述（100-150字）",
  "participants": ["直接参与的角色名"],
  "location": "事件发生地点",
  "type": "事件类型"
}

⚠️ 重要规则：
- description只描述【情境和环境】，不要描述角色的具体行动
- 不要替角色做决定，让角色自己决定如何反应
- 检查角色状态，尊重当前的属性限制
""" % [context, location_info, status_info, template_hint, player_input]
	
	var system = "你是一个TRPG游戏主持人，擅长设计事件并输出JSON。"
	
	var response = await api_client.call_chat_completion(
		system,
		prompt,
		MODEL_DESIGNER,
		400
	)
	
	# 提取JSON
	var json_text = response.strip_edges()
	
	# 情况1：被```json包裹
	if "```json" in json_text:
		var start = json_text.find("```json") + 7
		var end = json_text.find("```", start)
		if end > start:
			json_text = json_text.substr(start, end - start).strip_edges()
	# 情况2：被```包裹（没有json标记）
	elif json_text.begins_with("```") and json_text.ends_with("```"):
		json_text = json_text.trim_prefix("```").trim_suffix("```").strip_edges()
	
	print("提取的JSON文本: ", json_text.substr(0, 100) + "...")
	
	var json = JSON.parse_string(json_text)
	
	if json == null or not json is Dictionary:
		push_error("⚠️ JSON解析失败")
		print("原始响应: ", response)
		# 尝试从文本推断
		return {
			"description": response,
			"participants": [],
			"location": current_template.world_settings.get("default_location", "未知") if current_template else "未知",
			"type": "other"
		}
	
	print("✓ JSON解析成功")
	return json

# 收集角色响应
func gather_character_responses(event: StoryEvent, aware_characters: Array) -> Array[Dictionary]:
	var responses: Array[Dictionary] = []
	
	if aware_characters.size() == 0:
		print("⚠️ 没有角色知道这个事件")
		return responses
	
	# 过滤掉旁白
	var decision_characters: Array = []
	for character in aware_characters:
		if character.role_type != "narrator":
			decision_characters.append(character)
			
	if decision_characters.size() == 0:
		return responses
		
	print("⚡ 并发执行 %d 个角色决策..." % decision_characters.size())
	var start_time = Time.get_ticks_msec()
	
	# 使用并发管理器
	responses = await concurrent_manager.execute_concurrent_decisions(
		decision_characters,
		event,
		api_client
	)
	
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	print("⚡ 并发完成，耗时 %.2f 秒" % elapsed)
	
	return responses
	
# 讲述者整合
func compose_narrative(event: String, responses: Array[Dictionary]) -> String:
	var responses_text = ""
	for r in responses:
		# 安全获取字段，提供默认值
		var char_name = r.get("character", "未知角色")
		var char_response = r.get("response", "（无反应）")
		# 跳过空响应
		if char_response.is_empty() or char_response == "（沉默）":
			continue
		responses_text += "[%s]: %s\n" % [char_name, char_response]
	
	# 如果没有任何响应，使用备用方案
	if responses_text.is_empty():
		responses_text = "（角色们陷入了沉默）\n"
		
	# 模板风格
	var style_hint = ""
	if current_template and current_template.narrator_style:
		style_hint = "风格要求：%s\n" % current_template.narrator_style
	var prompt = """
事件：
%s

角色反应：
%s

%s

请将这些素材整合成一段连贯、优美的叙事文本（200-300字）：
- 使用第三人称
- 保持文学性
- 自然融合角色的行动和对话
- 直接输出故事内容，不要任何前缀或解释
""" % [event, responses_text, style_hint]
	
	var system = "你是一位专业的故事讲述者，擅长用优美的文字编织叙事。"
	
	var narrative = await api_client.call_chat_completion(
		system,
		prompt,
		MODEL_NARRATOR,  # 讲述者用最好的模型
		500
	)
	
	# 检查叙述者返回
	if narrative.is_empty():
		push_warning("⚠️ 讲述者没有返回内容，使用备用方案")
		return "故事继续着..." + event
		
	return narrative

# 应用行动效果（新增）
func apply_action_effects(responses: Array[Dictionary]):
	if not current_template:
		return
	
	for response in responses:
		var char_name = response.get("character", "")
		var action_text = response.get("response", "")
		
		# 找到角色
		var character = null
		for c in characters:
			if c.character_name == char_name:
				character = c
				break
		
		if character and character is UniversalCharacter:
			# 检测行动类型并应用效果
			var action_type = current_template.detect_action_type(action_text)
			
			# 应用成本
			character.apply_action_cost(action_text)
			
			# 应用效果（如果有目标角色）
			# TODO: 更智能的目标检测
			character.apply_action_effect(action_text)


# 获取故事上下文
func get_story_context() -> String:
	if story_log.size() == 0:
		var default_context = "故事刚刚开始。"
		if current_template:
			var location = current_template.world_settings.get("default_location", "")
			if location:
				default_context = "故事刚刚开始，在%s..." % location
		return default_context
	else:
		var recent = story_log.slice(-3) if story_log.size() > 3 else story_log
		return "\n".join(recent)

		
# 辅助函数
func get_location_info() -> String:
	var info = ""
	for char_name in world_state.character_locations.keys():
		if char_name != "旁白":
			info += "- %s: %s\n" % [char_name, world_state.character_locations[char_name]]
	return info
	
func get_character_status_info() -> String:
	var info = ""
	for character in characters:
		if character.role_type == "narrator":
			continue
		
		if character is UniversalCharacter:
			# 显示关键属性
			var status_parts = []
			for attr_def in current_template.get_all_attribute_definitions():
				if attr_def.get("per_character", false):
					continue
				var value = character.get_attr(attr_def.id)
				if value != null:
					var range_info = attr_def.get("range", [0, 100])
					status_parts.append("%s %s/%s" % [attr_def.name, value, range_info[1]])
			info += "- %s: %s\n" % [character.character_name, ", ".join(status_parts)]
		else:
			# 旧版 AICharacter
			info += "- %s: HP %d/%d, MP %d/%d\n" % [
				character.character_name,
				character.hp, character.max_hp,
				character.mana, character.max_mana
			]
	return info

func get_all_character_names() -> Array[String]:
	var names: Array[String] = []
	for character in characters:
		if character.role_type != "narrator":
			names.append(character.character_name)
	return names
	
func get_non_narrator_characters() -> Array:
	var chars: Array = []
	for character in characters:
		if character.role_type != "narrator":
			chars.append(character)
	return chars
	
# 获取角色
func get_character(char_name: String):
	for c in characters:
		if c.character_name == char_name:
			return c
	return null

# 保存游戏
func save_game(slot: int = 1, save_name: String = "自动存档"):
	var template_id = current_template.template_id if current_template else ""
	world_state.db_manager.save_game(
		slot,
		save_name,
		template_id,
		world_state,
		characters,
		story_log
	)
	print("💾 游戏已保存")

# 加载游戏
func load_game(slot: int = 1) -> bool:
	var save_data = world_state.db_manager.load_game(slot)
	
	if save_data.is_empty():
		print("❌ 找不到存档")
		return false
		
	# 先切换到存档的模板
	var saved_template_id = save_data.get("template_id", "")
	if saved_template_id and saved_template_id != "":
		if not switch_template(saved_template_id):
			push_warning("⚠️ 存档使用的模板 %s 不存在，使用当前模板" % saved_template_id)
			
	# 恢复世界状态
	world_state.from_dict(save_data.world_state)
	
	# 恢复角色（使用反序列化函数）
	characters = world_state.db_manager.deserialize_characters(
		save_data.characters_data,
		current_template
	)
	
	# 恢复故事日志
	story_log = save_data.story_log
	
	print("📂 游戏已加载")
	return true
