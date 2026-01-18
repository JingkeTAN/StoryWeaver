# scripts/core/AICharacter.gd
extends Node
class_name AICharacter

var character_name: String
var personality: String
var role_type: String  # "protagonist", "companion", "narrator"
const MODEL_CHARACTER = "grok-4-fast" #一致性检查

# 数据库引用
var db_manager: DatabaseManager

# 简化的属性（MVP阶段）
var hp: int = 100
var max_hp: int = 100
var mana: int = 50
var max_mana: int = 50

# 记忆（简单数组）
var memory: Array[String] = []

func _init(character_name_arg: String = "", persona: String = "", role: String = "companion"):
	character_name = character_name_arg
	personality = persona
	role_type = role

func get_model() -> String:
	match role_type:
		"protagonist":
			return "grok-4-fast"
		"companion":
			return "grok-4-fast"
		_:
			return "grok-4-fast"

func get_system_prompt() -> String:
	var base = "你是 %s，%s。\n" % [character_name, personality]
	
	match role_type:
		"protagonist":
			base += "你是故事的主角，要主动推动剧情。"
		"companion":
			base += "你是主角的伙伴，要支持和协助主角。"
		"narrator":
			base += "你是旁白，客观描述场景和氛围，用第三人称。"
	
	return base

func get_state_summary() -> String:
	return """
角色：%s
状态：生命 %d/%d，魔力 %d/%d
最近记忆：
%s
""" % [character_name, hp, max_hp, mana, max_mana, get_recent_memory()]

func get_recent_memory(count: int = 3) -> String:
	var recent = memory.slice(-count) if memory.size() > count else memory
	return "\n".join(recent) if recent.size() > 0 else "（无）"

func add_memory(content: String, event_id: String = ""):
	memory.append(content)
	
	# 保存到数据库
	if db_manager:
		db_manager.save_character_memory(character_name, content, event_id)
		
	# 限制记忆数量（MVP阶段简单处理）
	if memory.size() > 20:
		memory.remove_at(0)

# 生成决策
func make_decision(event: StoryEvent, api_client: APIClient) -> Dictionary:
	var prompt = """
%s

当前情境：
%s

事件类型：%s
事件地点：%s

你会如何反应？请简短回答（100字内）：
- 你的想法
- 你的行动
""" % [
		get_state_summary(),
		event.description,
		event.event_type,
		event.location
	]
	
	var response = await api_client.call_chat_completion(
		get_system_prompt(),
		prompt,
		get_model(),
		200
	)
	
	# 确保返回格式正确（防御性编程）
	var result = {
		"character": character_name,
		"response": response if response.length() > 0 else "（沉默）",
		"timestamp": Time.get_unix_time_from_system()
	}
	
	return result
	
# 从数据库加载记忆
func load_memory_from_db(db: DatabaseManager):
	db_manager = db
	memory = db_manager.load_character_memories(character_name, 20)
	print("✓ %s 加载了 %d 条记忆" % [character_name, memory.size()])

# 带审查的决策
func make_decision_with_validation(
	event: StoryEvent,
	api_client: APIClient,
	critic: CriticAgent,
	max_retries: int = 3
) -> Dictionary:
	
	var feedback_history: Array = []
	
	for attempt in range(max_retries):
		print("  🎯 %s 第 %d 次决策尝试" % [character_name, attempt + 1])
		
		# 构建提示词（包含历史反馈）
		var prompt = _build_decision_prompt(event, feedback_history)
		
		# 调用API获取决策
		var response = await api_client.call_chat_completion(
			get_system_prompt(),
			prompt,
			MODEL_CHARACTER,
			200
		)
		
		var decision = {
			"character": character_name,
			"response": response if response.length() > 0 else "（沉默）",
			"attempt": attempt + 1,
			"timestamp": Time.get_unix_time_from_system()
		}
		
		# 如果响应为空，直接返回
		if response.is_empty():
			return decision
		
		# 审查决策
		var validation = await critic.validate_decision(self, decision, event)
		
		if validation.passed:
			print("  ✅ 决策通过审查")
			return decision
		else:
			print("  🔄 决策被拒绝，准备重试...")
			# 记录反馈
			feedback_history.append({
				"attempt": attempt + 1,
				"rejected_action": response,
				"reason": validation.feedback
			})
	
	# 达到最大重试次数，返回安全默认行动
	print("  ⚠️ 达到最大重试次数，使用安全默认行动")
	return {
		"character": character_name,
		"response": "保持警惕，观察周围情况。",
		"attempt": max_retries,
		"fallback": true,
		"timestamp": Time.get_unix_time_from_system()
	}

# 构建决策提示词（包含反馈历史）
func _build_decision_prompt(event: StoryEvent, feedback_history: Array) -> String:
	var prompt = """
%s

当前情境：
%s

事件类型：%s
事件地点：%s
""" % [
		get_state_summary(),
		event.description,
		event.event_type,
		event.location
	]
	
	# 添加历史反馈
	if feedback_history.size() > 0:
		prompt += "\n【重要提醒】你之前的尝试被拒绝了：\n"
		for feedback in feedback_history:
			prompt += "───────────────\n"
			prompt += "尝试 %d: %s\n" % [feedback.attempt, feedback.rejected_action.substr(0, 50)]
			prompt += "拒绝原因:\n%s\n" % feedback.reason
		prompt += "───────────────\n"
		prompt += "请认真考虑这些反馈，重新做出合理的决策。\n\n"
	
	prompt += """
你会如何反应？请简短回答（100字内）：
- 你的想法
- 你的行动
"""
	
	return prompt
