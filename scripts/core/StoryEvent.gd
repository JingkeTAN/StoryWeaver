# scripts/core/StoryEvent.gd
extends RefCounted
class_name StoryEvent

var id: String
var description: String= ""
var event_type: String = "other" # "combat", "discovery", "dialogue", "social"

# 知识分发属性
var participants: Array = []  # 直接参与的角色名
var location: String = "未知地点"  # 发生地点
var scope: String = "local"  # "local", "regional", "global"
var visibility: String = "public"  # "public", "private", "secret"
var noise_level: float = 0.5  # 0-1，事件的"响动"大小

# 时间戳
var timestamp: float

# ──────────────── 初始化 ────────────────
func _init():
	id = "event_" + str(Time.get_ticks_msec())+ "_" + str(randi() % 1000)
	timestamp = Time.get_unix_time_from_system()

# 从设计师的JSON输出构建
static func from_designer_output(data: Dictionary, default_participants: Array[String] = []) -> StoryEvent:
	var event = StoryEvent.new()
	event.description = data.get("description", "").strip_edges()
	if event.description.is_empty():
		event.description = "[事件描述缺失]"
	event.participants = data.get("participants", [])
	event.location = data.get("location", "未知地點")
	event.event_type = data.get("type", "other").to_lower()
	
	# 根据类型设置属性
	match event.event_type:
		"combat", "battle":
			event.noise_level = 0.85
		"discovery":
			event.noise_level = 0.35
		"dialogue":
			event.noise_level = 0.20
		_:
			event.noise_level = 0.50
	
	return event

func to_dict() -> Dictionary:
	return {
		"id": id,
		"description": description,
		"event_type": event_type,
		"participants": participants,
		"location": location,
		"scope": scope,
		"visibility": visibility,
		"timestamp": timestamp
	}
