# scripts/core/ConcurrentDecisionManager.gd
extends Node
class_name ConcurrentDecisionManager

signal all_decisions_completed

var pending_decisions: int = 0
var completed_results: Array[Dictionary] = []
var is_executing: bool = false  # 执行锁

# 并发执行多个角色决策
func execute_concurrent_decisions(
	characters: Array[AICharacter],
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
	character: AICharacter,
	event: StoryEvent,  
	api_client: APIClient
):
	# 在新的协程中执行
	var decision = await character.make_decision(event, api_client)
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
