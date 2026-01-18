# scripts/core/CriticAgent.gd
extends Node
class_name CriticAgent

var api_client: APIClient
var world_state: WorldState
var template: WorldTemplate

# 审查结果类
class ValidationResult:
	var passed: bool = true
	var level: String = ""  # "rule", "consistency", "logic"
	var severity: String = "none"  # "critical", "major", "minor", "none"
	var violations: Array = []
	var feedback: String = ""
	
	func _init():
		passed = true
		violations = []

func _init(api: APIClient, ws: WorldState, tmpl: WorldTemplate = null):
	api_client = api
	world_state = ws
	template = tmpl
	
func set_template(tmpl: WorldTemplate):
	template = tmpl
	print("✓ 审查系统已切换模板: %s" % tmpl.template_name)
# ══════════════════════════════════════════
# 主审查函数
# ══════════════════════════════════════════
func validate_decision(
	character,
	decision: Dictionary,
	event: StoryEvent
) -> ValidationResult:
	
	print("\n=== 审查 %s 的决策 ===" % character.character_name)
	
	var response_text = decision.get("response", "")
	
	# Level 1: 硬规则检查（即时，0成本）
	var rule_result = check_template_rules(character, response_text)
	if not rule_result.passed:
		print("  ❌ Level 1 失败: %s" % rule_result.feedback)
		return rule_result
	print("  ✓ Level 1 通过（硬规则）")
	
	# Level 2: 角色一致性检查（LLM，低成本）
	var consistency_result = await check_character_consistency(character, response_text, event)
	if not consistency_result.passed:
		print("  ❌ Level 2 失败: %s" % consistency_result.feedback)
		return consistency_result
	print("  ✓ Level 2 通过（角色一致性）")
	
	# Level 3: 世界逻辑检查（可选，跳过以节省成本）
	var logic_result = await check_world_logic(character, response_text, event)
	if not logic_result.passed:
		print("  ❌ Level 3 失败: %s" % logic_result.feedback)
		return logic_result
	print("  ✓ Level 3 通过（世界逻辑检查）")
	
	
	print("  ✅ 审查通过")
	var final_result = ValidationResult.new()
	final_result.passed = true
	return final_result

# Level 1: 模板规则检查
func check_template_rules(character, response_text: String) -> ValidationResult:
	var result = ValidationResult.new()
	result.level = "rule"
	
	# 如果有模板，使用模板规则
	if template:
		var state = {}
		
		# 获取角色状态
		if character is UniversalCharacter:
			state = character.attributes.duplicate()
		else:
			# 兼容旧版 AICharacter
			state = {
				"hp": character.hp,
				"mana": character.mana,
				"max_hp": character.max_hp,
				"max_mana": character.max_mana
			}
		
		# 使用模板检查约束
		var check = template.check_constraints(state, response_text)
		
		if not check.allowed:
			result.passed = false
			result.severity = "critical"
			result.violations = check.violations
			result.feedback = "\n".join(check.messages)
			result.feedback += "\n\n请选择其他行动。"
			return result
	else:
		# 没有模板，使用旧的硬编码逻辑
		result = _legacy_hard_rules_check(character, response_text)
		if not result.passed:
			return result
	
	result.passed = true
	return result


# 旧版硬编码检查（兼容）
func _legacy_hard_rules_check(character, response_text: String) -> ValidationResult:
	var result = ValidationResult.new()
	result.level = "rule"
	
	var text_lower = response_text.to_lower()
	
	# 魔法检查
	var magic_keywords = ["施法", "魔法", "咒语", "法术", "火球", "冰锥"]
	for keyword in magic_keywords:
		if keyword in text_lower:
			if character.mana < 10:
				result.passed = false
				result.severity = "critical"
				result.feedback = "魔力不足（当前%d），无法使用魔法。" % character.mana
				return result
	
	result.passed = true
	return result

# ══════════════════════════════════════════
# Level 2: 角色一致性检查（LLM）
# ══════════════════════════════════════════
func check_character_consistency(
	character,
	response_text: String,
	event: StoryEvent
) -> ValidationResult:
	
	var result = ValidationResult.new()
	result.level = "consistency"
	
	var prompt = """
角色设定：
- 姓名：%s
- 性格：%s
- 类型：%s

当前情境：
%s

角色的决策：
%s

问题：这个决策是否严重违背角色的性格设定？

判断标准：
- 勇敢的角色不应该无故怯懦
- 谨慎的角色不应该无脑冲动
- 正义的角色不应该做邪恶的事
- 但允许角色有合理的成长和变化

只回答：PASS 或 FAIL
如果 FAIL，简短说明理由（15字内）

格式：PASS/FAIL | 理由
""" % [
		character.character_name,
		character.personality,
		character.role_type,
		event.description.substr(0, 200),
		response_text
	]
	
	var response = await api_client.call_chat_completion(
		"你是角色一致性审查员，严格但公正。",
		prompt,
		"grok-4-fast",  # 用便宜的模型
		30
	)
	
	if "FAIL" in response.to_upper():
		result.passed = false
		result.severity = "major"
		
		var reason = "角色行为不一致"
		if "|" in response:
			var parts = response.split("|")
			if parts.size() > 1:
				reason = parts[1].strip_edges()
		
		result.violations.append(reason)
		result.feedback = """
你的行动与角色性格不符：%s

记住你是「%s」——%s

请重新考虑符合你性格的行动。
""" % [reason, character.character_name, character.personality]
		return result
	
	result.passed = true
	return result

# ══════════════════════════════════════════
# Level 3: 世界逻辑检查（可选）
# ══════════════════════════════════════════
func check_world_logic(
	character,
	response_text: String,
	_event: StoryEvent #这个目前还没用上
) -> ValidationResult:
	
	var result = ValidationResult.new()
	result.level = "logic"
	
	# 获取相关的世界事实
	var known_facts = world_state.get_known_events(character.character_name)
	
	if known_facts.size() == 0:
		result.passed = true
		return result
	
	var facts_text = ""
	for fact in known_facts.slice(-5):  # 最近5条
		facts_text += "- %s\n" % fact.description.substr(0, 50)
	
	var prompt = """
已知世界事实：
%s

角色 %s 的行动：
%s

问题：这个行动是否与已知事实产生明显的逻辑冲突？

例如：
- 使用已经丢失的物品
- 去已经被摧毁的地方
- 认识从未见过的人

只回答：OK 或 CONFLICT
如果 CONFLICT，说明冲突原因（15字内）

格式：OK/CONFLICT | 理由
""" % [facts_text, character.character_name, response_text]
	
	var response = await api_client.call_chat_completion(
		"你是逻辑一致性检查员",
		prompt,
		"grok-4-fast",
		30
	)
	
	if "CONFLICT" in response.to_upper():
		result.passed = false
		result.severity = "major"
		
		var reason = "与世界事实冲突"
		if "|" in response:
			var parts = response.split("|")
			if parts.size() > 1:
				reason = parts[1].strip_edges()
		
		result.violations.append(reason)
		result.feedback = """
你的行动与已知事实冲突：%s

请基于你实际知道的信息重新决策。
""" % reason
		return result
	
	result.passed = true
	return result
	
# 审查设计师生成的事件
func validate_event(event: StoryEvent, characters: Array) -> ValidationResult:
	var result = ValidationResult.new()
	result.level = "event"
	
	var text_lower = event.description.to_lower()
	
	# 检查是否替角色使用了魔法
	var magic_actions = ["施放", "释放魔法", "凝聚魔力", "火球术", "冰霜箭"]
	
	for action in magic_actions:
		if action in text_lower:
			# 检查哪个角色被描述使用魔法
			for character in characters:
				if character.character_name in event.description:
					if character.mana < 10:
						result.passed = false
						result.severity = "critical"
						result.feedback = "事件描述中%s使用了魔法，但其魔力不足" % character.character_name
						return result
	
	result.passed = true
	return result
	
	
