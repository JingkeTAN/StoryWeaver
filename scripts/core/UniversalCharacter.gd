# scripts/core/UniversalCharacter.gd
extends RefCounted
class_name UniversalCharacter

var character_name: String
var personality: String
var role_type: String  # 使用模板的archetype
var gender: String = "unknown"

# 通用属性存储
var attributes: Dictionary = {}

# 关系属性（每个角色独立）
var relationships: Dictionary = {}  # {角色名: {affection: 50, trust: 50, ...}}

# 记忆
var memory: Array = []

# 所属模板
var template: WorldTemplate

func _init(name: String, persona: String, role: String, tmpl: WorldTemplate):
	character_name = name
	personality = persona
	role_type = role
	template = tmpl
	
	# 初始化默认属性
	attributes = template.get_default_attributes()

# 获取属性值
func get_attr(attr_id: String):
	return attributes.get(attr_id)

# 设置属性值
func set_attr(attr_id: String, value):
	var attr_def = template.find_attribute(attr_id)
	if attr_def.is_empty():
		attributes[attr_id] = value
		return
	
	# 检查范围
	if attr_def.has("range"):
		var range_min = attr_def.range[0]
		var range_max = attr_def.range[1]
		if value is float or value is int:
			value = clamp(value, range_min, range_max)
	
	attributes[attr_id] = value

# 修改属性值（增减）
func modify_attr(attr_id: String, delta: float):
	var current = get_attr(attr_id)
	if current is float or current is int:
		set_attr(attr_id, current + delta)

# 获取对某角色的关系属性
func get_relationship(target_name: String, attr_id: String):
	if not relationships.has(target_name):
		return template.find_attribute(attr_id).get("default", 0)
	return relationships[target_name].get(attr_id, 0)

# 设置对某角色的关系属性
func set_relationship(target_name: String, attr_id: String, value):
	if not relationships.has(target_name):
		relationships[target_name] = {}
	
	var attr_def = template.find_attribute(attr_id)
	if attr_def.has("range"):
		value = clamp(value, attr_def.range[0], attr_def.range[1])
	
	relationships[target_name][attr_id] = value

# 生成状态摘要（用于Prompt）
func get_state_summary() -> String:
	var summary = "角色：%s\n" % character_name
	summary += "性格：%s\n" % personality
	summary += "\n【属性状态】\n"
	
	# 按类别组织
	for category in template.attributes.keys():
		var category_name = {
			"physical": "身体",
			"emotional": "情绪",
			"social": "社交",
			"relationship": "关系",
			"special": "特殊",
			"resources": "资源"
		}.get(category, category)
		
		var has_attrs = false
		var category_text = ""
		
		for attr_def in template.attributes[category]:
			if attr_def.get("per_character", false):
				continue  # 关系属性单独处理
			
			var value = attributes.get(attr_def.id, attr_def.get("default", 0))
			var unit = attr_def.get("unit", "")
			category_text += "- %s: %s%s\n" % [attr_def.name, value, unit]
			has_attrs = true
		
		if has_attrs:
			summary += "[%s]\n%s" % [category_name, category_text]
	
	# 关系信息
	if relationships.size() > 0:
		summary += "\n【关系】\n"
		for target in relationships.keys():
			var rel = relationships[target]
			var rel_text = ""
			for attr_id in rel.keys():
				var attr_def = template.find_attribute(attr_id)
				rel_text += "%s:%s " % [attr_def.get("name", attr_id), rel[attr_id]]
			summary += "- %s: %s\n" % [target, rel_text]
	
	return summary

# 获取最近记忆
func get_recent_memory(count: int = 5) -> String:
	var recent = memory.slice(-count) if memory.size() > count else memory
	return "\n".join(recent) if recent.size() > 0 else "（无）"

# 添加记忆
func add_memory(content: String, _event_id: String = ""):
	memory.append(content)
	if memory.size() > 30:
		memory.remove_at(0)

# 获取系统提示词
func get_system_prompt() -> String:
	var prompt = "你是 %s，%s。\n" % [character_name, personality]
	
	# 根据角色类型添加指导
	match role_type:
		"protagonist":
			prompt += "你是故事的主角，要主动推动剧情发展。"
		"love_interest":
			prompt += "你是可攻略的角色，根据好感度和剧情发展做出相应反应。"
		"friend":
			prompt += "你是主角的朋友，要提供帮助和建议。"
		"rival":
			prompt += "你是竞争对手，但不要过于敌对。"
		_:
			prompt += "根据你的性格自然地参与故事。"
	
	# 添加模板特定指导
	if template.narrator_style:
		prompt += "\n风格提示：%s" % template.narrator_style
	
	return prompt

# 检查约束
func check_action_allowed(action_text: String) -> Dictionary:
	return template.check_constraints(attributes, action_text)

# 应用行动成本
func apply_action_cost(action_text: String):
	var costs = template.get_action_cost(action_text)
	for attr_id in costs.keys():
		var cost = costs[attr_id]
		if cost > 0:
			modify_attr(attr_id, -cost)
		else:
			modify_attr(attr_id, -cost)  # 负数变正（如工作赚钱）

# 应用行动效果
func apply_action_effect(action_text: String, target_name: String = ""):
	var effects = template.get_action_effect(action_text)
	for attr_id in effects.keys():
		var effect = effects[attr_id]
		
		# 检查是否是关系属性
		var attr_def = template.find_attribute(attr_id)
		if attr_def.get("per_character", false) and target_name:
			var current = get_relationship(target_name, attr_id)
			set_relationship(target_name, attr_id, current + effect)
		elif effect is String:
			# 枚举类型直接设置
			set_attr(attr_id, effect)
		else:
			modify_attr(attr_id, effect)
