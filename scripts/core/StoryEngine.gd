# scripts/core/StoryEngine.gd
extends Node
class_name StoryEngine

signal story_updated(text: String)
signal processing_started()
signal processing_finished()

var api_client: APIClient
var characters: Array[AICharacter] = []
var story_log: Array[String] = []
# 世界状态和知识分发
var world_state: WorldState
var knowledge_distributor: KnowledgeDistributor
#并发管理
var concurrent_manager: ConcurrentDecisionManager

const MODEL_DESIGNER = "claude-haiku-4-5"
const MODEL_NARRATOR = "claude-haiku-4-5"

func _ready():
	print("=== StoryEngine 初始化 ===")
	api_client = APIClient.new()
	add_child(api_client)
	print("APIClient 已添加")
	# 初始化世界状态
	world_state = WorldState.new()
	knowledge_distributor = KnowledgeDistributor.new(world_state)
	print("✓ 世界状态系统初始化")
	# 初始化3个角色
	setup_default_characters()
	print("✓ StoryEngine 初始化完成")
	
	concurrent_manager = ConcurrentDecisionManager.new()
	add_child(concurrent_manager)
	print("✓ 并发管理器初始化")
	
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
	
	
	# Step 6: 记录到世界状态
	var known_by: Array[String] = []

	for c in aware_characters:
		known_by.append(c.character_name)
	world_state.record_event(event, known_by)
	
	# Step 7: 更新记忆（只给知道的角色）
	for character in aware_characters:
		character.add_memory(event.description, event.id)
	
	story_log.append(narrative)
	emit_signal("story_updated", narrative)
	
	return true 
# 设计师层
func generate_event_from_designer(player_input: String) -> Dictionary:
	var context = get_story_context()
	
	# 获取角色位置信息
	var locations = world_state.character_locations
	var location_info = ""
	for char_name in locations.keys():
		if char_name != "旁白":
			location_info += "- %s: %s\n" % [char_name, locations[char_name]]
	
	var prompt = """
当前故事进展：
%s

角色位置：
%s

玩家需求："%s"

请设计事件，以JSON格式返回：
{
  "description": "事件的详细描述（100-150字）",
  "participants": ["直接参与的角色名"],
  "location": "事件发生地点",
  "type": "combat/discovery/dialogue/social"
}

要求：
- participants只包含在场的角色
- 如果玩家说"小白独自"，就只有["小白"]
- 检查角色位置，不在同一地点的不能同时参与
- location必须是某个角色的当前位置
""" % [context, location_info, player_input]
	
	var system = "你是一个TRPG游戏主持人，擅长设计事件并输出JSON。"
	
	var response = await api_client.call_chat_completion(
		system,
		prompt,
		MODEL_DESIGNER,
		400
	)
	
	# 提取JSON（改进版）
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
			"location": "森林",
			"type": "other"
		}
	
	print("✓ JSON解析成功")
	return json

# 收集角色响应
func gather_character_responses(event: StoryEvent, aware_characters: Array[AICharacter]) -> Array[Dictionary]:
	var responses: Array[Dictionary] = []
	
	if aware_characters.size() == 0:
		print("⚠️ 没有角色知道这个事件")
		return responses
	
	# 过滤掉旁白
	var decision_characters: Array[AICharacter] = []
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
		
	var prompt = """
事件：
%s

角色反应：
%s

请将这些素材整合成一段连贯、优美的叙事文本（200-300字）：
- 使用第三人称
- 保持文学性
- 自然融合角色的行动和对话
- 直接输出故事内容，不要任何前缀或解释
""" % [event, responses_text]
	
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

# 获取故事上下文
func get_story_context() -> String:
	if story_log.size() == 0:
		return "故事刚刚开始，小白和木糖醇正在一片森林中探险。"
	else:
		# 返回最近3条
		var recent = story_log.slice(-3) if story_log.size() > 3 else story_log
		return "\n".join(recent)
		
# 辅助函数
func get_all_character_names() -> Array[String]:
	var names: Array[String] = []
	for character in characters:
		if character.role_type != "narrator":
			names.append(character.character_name)
	return names
	
func get_non_narrator_characters() -> Array[AICharacter]:
	var chars: Array[AICharacter] = []
	for character in characters:
		if character.role_type != "narrator":
			chars.append(character)
	return chars

# 保存游戏
func save_game(slot: int = 1, save_name: String = "自动存档"):
	world_state.db_manager.save_game(
		slot,
		save_name,
		world_state,
		characters,
		story_log
	)
	print("💾 游戏已保存")

# 加载游戏
func load_game(slot: int = 1):
	var save_data = world_state.db_manager.load_game(slot)
	
	if save_data.is_empty():
		print("❌ 找不到存档")
		return false
	
	# 恢复世界状态
	world_state.from_dict(save_data.world_state)
	
	# 恢复角色
	var chars_data = save_data.characters_data
	for i in range(chars_data.size()):
		if i < characters.size():
			var character = characters[i]
			var data = chars_data[i]
			character.character_name = data.name
			character.personality = data.personality
			character.hp = data.hp
			character.mana = data.mana
			character.memory = data.memory
	
	# 恢复故事日志
	story_log = save_data.story_log
	
	print("📂 游戏已加载")
	return true
