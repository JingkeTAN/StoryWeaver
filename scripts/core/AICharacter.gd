# scripts/core/AICharacter.gd
extends Node
class_name AICharacter

var character_name: String
var personality: String
var role_type: String  # "protagonist", "companion", "narrator"

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
			return "gpt-3.5-turbo"

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

func add_memory(content: String):
	memory.append(content)
	# 限制记忆数量（MVP阶段简单处理）
	if memory.size() > 20:
		memory.remove_at(0)

# 生成决策
func make_decision(event_description: String, api_client: APIClient) -> Dictionary:
	var prompt = """
%s

当前情境：
%s

你会如何反应？请简短回答（100字内）：
- 你的想法
- 你的行动
""" % [get_state_summary(), event_description]
	
	var response = await api_client.call_chat_completion(
		get_system_prompt(),
		prompt,
		get_model(),
		200
	)
	
	return {
		"character": character_name,
		"response": response
	}
