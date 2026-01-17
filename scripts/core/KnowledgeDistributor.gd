# scripts/core/KnowledgeDistributor.gd
extends Node
class_name KnowledgeDistributor

var world_state: WorldState

func _init(ws: WorldState):
	world_state = ws

# 主函数：判断哪些角色应该知道这个事件
func determine_aware_characters(event: StoryEvent, all_characters: Array[AICharacter]) -> Array[AICharacter]:
	var aware_chars: Array[AICharacter] = []
	
	print("\n=== 知识分发：%s ===" % event.description.substr(0, 30))
	print("事件类型: %s | 地点: %s | 作用域: %s" % [event.event_type, event.location, event.scope])
	
	for character in all_characters:
		if character.role_type == "narrator":
			continue  # 旁白不参与决策
		
		var should_know = evaluate_knowledge_access(character, event)
		
		if should_know.knows:
			aware_chars.append(character)
			print("✓ %s 知道此事（%s）" % [character.character_name, should_know.reason])
		else:
			print("✗ %s 不知道此事（%s）" % [character.character_name, should_know.reason])
	
	return aware_chars

# 判断单个角色是否应该知道
func evaluate_knowledge_access(character: AICharacter, event: StoryEvent) -> Dictionary:
	# 规则1：直接参与者必定知道
	if character.character_name in event.participants:
		return {"knows": true, "reason": "直接参与"}
	
	# 规则2：全局事件所有人知道
	if event.scope == "global":
		return {"knows": true, "reason": "全局事件"}
	
	# 规则3：私密事件只有参与者知道
	if event.visibility == "private" or event.visibility == "secret":
		return {"knows": false, "reason": "私密事件"}
	
	# 规则4：检查是否在同一地点
	var char_location = world_state.character_locations.get(character.character_name, "未知")
	if char_location == event.location:
		# 在场，根据事件响动判断
		if event.noise_level >= 0.3:
			return {"knows": true, "reason": "在场且事件明显(noise:%.1f)" % event.noise_level}
		else:
			# 小声事件，可能注意不到
			return {"knows": false, "reason": "在场但事件不明显"}
	
	# 规则5：不在同一地点，局部事件不知道
	if event.scope == "local":
		return {"knows": false,  "reason": "不在现场(%s vs %s)" % [char_location, event.location]}
	
	# 默认：区域事件，附近的人可能知道
	if event.scope == "regional":
		return {"knows": true, "reason": "区域事件传播"}
	
	return {"knows": false, "reason": "无规则匹配"}
