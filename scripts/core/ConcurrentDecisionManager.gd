# scripts/core/ConcurrentDecisionManager.gd
extends Node
class_name ConcurrentDecisionManager

signal all_decisions_completed

var pending_decisions: int = 0
var completed_results: Array[Dictionary] = []
var is_executing: bool = false  # 执行锁
const MODEL_CHARACTER = "grok-4-fast"
# 审查模式开关
var enable_validation: bool = true
var critic: CriticAgent

func set_critic(c: CriticAgent):
	critic = c



# 并发执行多个角色决策
func execute_concurrent_decisions(
	characters: Array,
	event: StoryEvent,  
	api_client: APIClient
) -> Array[Dictionary]:
	
	# 安全检查：防止并发调用
	if is_executing:
		push_warning("⚠️ ConcurrentDecisionManager正在执行中，忽略新请求")
		return []
		
	is_executing = true
	# 只重置数据，不碰锁
	_reset_data()
	
	pending_decisions = characters.size()
	completed_results.resize(pending_decisions)
	
	# 同时启动所有决策
	for i in range(characters.size()):
		var character = characters[i]
		completed_results[i] = {
			"character": character.character_name,
			"response": "",
			"error": ""
		}
		_start_decision(i, character, event, api_client)
	
	# 等待所有完成
	await all_decisions_completed
	
	# 释放锁
	is_executing = false
	
	return completed_results

# 启动单个决策（不阻塞）
func _start_decision(
	index: int,
	character,  # 支持 AICharacter 或 UniversalCharacter
	event: StoryEvent,  
	api_client: APIClient
):
	var decision: Dictionary
	# 根据是否启用审查选择不同的决策方法
	if enable_validation and critic != null:
		decision = await _make_decision_with_validation(character, event, api_client, 3)
	else:
		decision = await _make_decision(character, event, api_client)
	
	_on_decision_completed(index, decision)

# 决策完成回调
func _on_decision_completed(index: int, result: Dictionary):
	# 验证索引范围（防御性编程）
	if index < 0 or index >= completed_results.size():
		push_error("❌ 决策索引越界: %d" % index)
		return
		
	completed_results[index] = result
	pending_decisions -= 1
	
	print("  ✓ 决策 %d 完成，剩余 %d" % [index + 1, pending_decisions])
	
	if pending_decisions == 0:
		emit_signal("all_decisions_completed")

# 重置函数
func _reset_data():
	pending_decisions = 0
	completed_results.clear()
	
# 通用决策函数
func _make_decision(character, event: StoryEvent, api_client: APIClient) -> Dictionary:
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
		character.get_state_summary(),
		event.description,
		event.event_type,
		event.location
	]
	
	var response = await api_client.call_chat_completion(
		character.get_system_prompt(),
		prompt,
		MODEL_CHARACTER,
		200
	)
	
	return {
		"character": character.character_name,
		"response": response if response.length() > 0 else "（沉默）",
		"timestamp": Time.get_unix_time_from_system()
	}

# 带审查的决策
func _make_decision_with_validation(
	character,
	event: StoryEvent,
	api_client: APIClient,
	max_retries: int
) -> Dictionary:
	
	var feedback_history: Array = []
	
	for attempt in range(max_retries):
		print("  🎯 %s 第 %d 次决策尝试" % [character.character_name, attempt + 1])
		
		var prompt = _build_decision_prompt(character, event, feedback_history)
		
		var response = await api_client.call_chat_completion(
			character.get_system_prompt(),
			prompt,
			MODEL_CHARACTER,
			200
		)
		
		var decision = {
			"character": character.character_name,
			"response": response if response.length() > 0 else "（沉默）",
			"attempt": attempt + 1,
			"timestamp": Time.get_unix_time_from_system()
		}
		
		if response.is_empty():
			return decision
		
		var validation = await critic.validate_decision(character, decision, event)
		
		if validation.passed:
			print("  ✅ 决策通过审查")
			return decision
		else:
			print("  🔄 决策被拒绝，准备重试...")
			feedback_history.append({
				"attempt": attempt + 1,
				"rejected_action": response,
				"reason": validation.feedback
			})
	
	print("  ⚠️ 达到最大重试次数，使用安全默认行动")
	return {
		"character": character.character_name,
		"response": "保持警惕，观察周围情况。",
		"attempt": max_retries,
		"fallback": true,
		"timestamp": Time.get_unix_time_from_system()
	}

func _build_decision_prompt(character, event: StoryEvent, feedback_history: Array) -> String:
	var prompt = """
%s

当前情境：
%s

事件类型：%s
事件地点：%s
""" % [
		character.get_state_summary(),
		event.description,
		event.event_type,
		event.location
	]
	
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
