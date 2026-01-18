# scripts/core/WorldTemplate.gd
extends RefCounted
class_name WorldTemplate

var template_id: String
var template_name: String
var description: String
var version: String

var world_settings: Dictionary = {}
var attributes: Dictionary = {}
var action_keywords: Dictionary = {}
var constraint_rules: Array = []
var action_costs: Dictionary = {}
var action_effects: Dictionary = {}
var character_archetypes: Array = []
var event_types: Array = []
var designer_prompt_extra: String = ""
var narrator_style: String = ""

# 加载模板
static func load_from_file(path: String) -> WorldTemplate:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("❌ 无法打开模板文件: " + path)
		return null
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.parse_string(json_text)
	if json == null:
		push_error("❌ 模板JSON解析失败: " + path)
		return null
	
	return from_dict(json)

# 从字典创建
static func from_dict(data: Dictionary) -> WorldTemplate:
	var template = WorldTemplate.new()
	
	template.template_id = data.get("template_id", "unknown")
	template.template_name = data.get("template_name", "未命名")
	template.description = data.get("description", "")
	template.version = data.get("version", "1.0")
	
	template.world_settings = data.get("world_settings", {})
	template.attributes = data.get("attributes", {})
	template.action_keywords = data.get("action_keywords", {})
	template.constraint_rules = data.get("constraint_rules", [])
	template.action_costs = data.get("action_costs", {})
	template.action_effects = data.get("action_effects", {})
	template.character_archetypes = data.get("character_archetypes", [])
	template.event_types = data.get("event_types", [])
	template.designer_prompt_extra = data.get("designer_prompt_extra", "")
	template.narrator_style = data.get("narrator_style", "")
	
	print("✓ 加载模板: %s (%s)" % [template.template_name, template.template_id])
	return template

# 获取所有属性定义（扁平化）
func get_all_attribute_definitions() -> Array:
	var all_attrs = []
	for category in attributes.keys():
		for attr in attributes[category]:
			attr["category"] = category
			all_attrs.append(attr)
	return all_attrs

# 查找属性定义
func find_attribute(attr_id: String) -> Dictionary:
	for category in attributes.keys():
		for attr in attributes[category]:
			if attr.id == attr_id:
				return attr
	return {}

# 获取默认属性值
func get_default_attributes() -> Dictionary:
	var defaults = {}
	for attr in get_all_attribute_definitions():
		defaults[attr.id] = attr.get("default", 0)
	return defaults

# 检查约束规则
func check_constraints(character_state: Dictionary, action_text: String) -> Dictionary:
	var result = {"allowed": true, "violations": [], "messages": []}
	
	for rule in constraint_rules:
		# 检查条件是否满足
		if evaluate_condition(rule.condition, character_state):
			# 条件满足，检查行动是否被禁止
			var forbidden = rule.effects.get("forbidden_keywords", [])
			for keyword in forbidden:
				if keyword in action_text:
					result.allowed = false
					result.violations.append(rule.id)
					result.messages.append(rule.effects.get("message", "行动被禁止"))
					break
	
	return result

# 评估条件表达式
func evaluate_condition(condition: String, state: Dictionary) -> bool:
	# 简化的条件解析器
	# 支持: attr < value, attr > value, attr == value, attr != value
	# 支持: AND, OR
	
	# 处理 AND
	if " AND " in condition:
		var parts = condition.split(" AND ")
		for part in parts:
			if not evaluate_single_condition(part.strip_edges(), state):
				return false
		return true
	
	# 处理 OR
	if " OR " in condition:
		var parts = condition.split(" OR ")
		for part in parts:
			if evaluate_single_condition(part.strip_edges(), state):
				return true
		return false
	
	# 单个条件
	return evaluate_single_condition(condition, state)

func evaluate_single_condition(condition: String, state: Dictionary) -> bool:
	# 解析: "attr < value" 或 "attr == 'string'"
	var operators = ["!=", "==", "<=", ">=", "<", ">"]
	
	for op in operators:
		if op in condition:
			var parts = condition.split(op)
			if parts.size() == 2:
				var attr_name = parts[0].strip_edges()
				var value_str = parts[1].strip_edges().trim_prefix("'").trim_suffix("'")
				
				var attr_value = state.get(attr_name)
				if attr_value == null:
					return false
				
				# 尝试数值比较
				if value_str.is_valid_float():
					var num_value = float(value_str)
					var attr_num = float(attr_value) if attr_value is float or attr_value is int else 0.0
					match op:
						"<": return attr_num < num_value
						">": return attr_num > num_value
						"<=": return attr_num <= num_value
						">=": return attr_num >= num_value
						"==": return attr_num == num_value
						"!=": return attr_num != num_value
				else:
					# 字符串比较
					match op:
						"==": return str(attr_value) == value_str
						"!=": return str(attr_value) != value_str
	
	return false

# 获取行动成本
func get_action_cost(action_text: String) -> Dictionary:
	for action_name in action_costs.keys():
		if action_name in action_text:
			return action_costs[action_name]
	return {}

# 获取行动效果
func get_action_effect(action_text: String) -> Dictionary:
	for action_name in action_effects.keys():
		if action_name in action_text:
			return action_effects[action_name]
	return {}

# 检测行动类型
func detect_action_type(action_text: String) -> String:
	var text_lower = action_text.to_lower()
	for action_type in action_keywords.keys():
		for keyword in action_keywords[action_type]:
			if keyword in text_lower:
				return action_type
	return "other"

# 获取事件类型配置
func get_event_type_config(type_id: String) -> Dictionary:
	for et in event_types:
		if et.id == type_id:
			return et
	return {"id": "other", "name": "其他", "noise_level": 0.5}
