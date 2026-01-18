# scripts/core/WorldState.gd
extends Node
class_name WorldState

# 世界事实记录
var world_facts: Array[Dictionary] = []

# 角色位置（简化版）
var character_locations: Dictionary = {}

# 当前场景
var current_scene: String = "森林"

# 数据库管理器
var db_manager: DatabaseManager

func _init():
	# 初始化默认位置
	character_locations = {
		"小白": "森林",
		"木糖醇": "森林",
		"旁白": "无处不在"
	}
	
	# 初始化数据库
	db_manager = DatabaseManager.new()
	
	# 加载已有的世界事实
	world_facts = db_manager.load_world_facts()
	print("✓ 加载了 %d 条历史事实" % world_facts.size())
	
# 记录事件（持久化）
func record_event(event: StoryEvent, known_by: Array[String]):
	var fact = {
		"event_id": event.id,
		"description": event.description,
		"known_by": known_by,  # 知道这个事件的角色
		"timestamp": event.timestamp,
		"location": event.location
	}
	world_facts.append(fact)
	# 保存到数据库
	db_manager.save_world_fact(event, known_by)
	print("📝 记录世界事实，知晓者：", known_by)

# 获取角色知道的事件
func get_known_events(character_name: String) -> Array[Dictionary]:
	var known: Array[Dictionary] = []
	for fact in world_facts:
		if character_name in fact.known_by:
			known.append(fact)
	return known

# 更新角色位置
func update_character_location(character_name: String, location: String):
	character_locations[character_name] = location
	print("📍 %s 移动到：%s" % [character_name, location])

# 检查两个角色是否在同一地点
func are_at_same_location(char_a: String, char_b: String) -> bool:
	return character_locations.get(char_a) == character_locations.get(char_b)

# 获取某地点的所有角色
func get_characters_at_location(location: String) -> Array[String]:
	var chars: Array[String] = []
	for char_name in character_locations.keys():
		if character_locations[char_name] == location:
			chars.append(char_name)
	return chars
	
	
# 序列化为字典（用于存档）
func to_dict() -> Dictionary:
	return {
		"character_locations": character_locations,
		"current_scene": current_scene
	}

# 从字典恢复
func from_dict(data: Dictionary):
	character_locations = data.get("character_locations", {})
	current_scene = data.get("current_scene", "森林")
