# scripts/core/DatabaseManager.gd
extends Node
class_name DatabaseManager

var db: SQLite
var db_path: String = "user://storyweaver.db"

func _init():
	db = SQLite.new()
	db.path = db_path
	db.open_db()
	create_tables()
	print("✓ 数据库初始化完成: ", db_path)

func create_tables():
	# 世界事实表
	db.create_table("world_facts", {
		"id": {"data_type": "text", "primary_key": true},
		"description": {"data_type": "text", "not_null": true},
		"event_type": {"data_type": "text"},
		"location": {"data_type": "text"},
		"scope": {"data_type": "text"},
		"timestamp": {"data_type": "int"},
		"known_by": {"data_type": "text"}
	})
	
	# 角色记忆表
	db.create_table("character_memories", {
		"id": {"data_type": "int", "primary_key": true, "auto_increment": true},
		"character_name": {"data_type": "text", "not_null": true},
		"memory_content": {"data_type": "text", "not_null": true},
		"timestamp": {"data_type": "int"},
		"event_id": {"data_type": "text"}
	})
	
	# 存档表
	db.create_table("save_slots", {
		"slot_id": {"data_type": "int", "primary_key": true},
		"save_name": {"data_type": "text"},
		"save_time": {"data_type": "int"},
		"world_state": {"data_type": "text"},
		"characters_data": {"data_type": "text"},
		"story_log": {"data_type": "text"}
	})

# 保存世界事实
func save_world_fact(event: StoryEvent, known_by: Array[String]):
	var data = {
		"id": event.id,
		"description": event.description,
		"event_type": event.event_type,
		"location": event.location,
		"scope": event.scope,
		"timestamp": event.timestamp,
		"known_by": JSON.stringify(known_by)
	}
	db.insert_row("world_facts", data)

# 保存角色记忆
func save_character_memory(character_name: String, content: String, event_id: String = ""):
	var data = {
		"character_name": character_name,
		"memory_content": content,
		"timestamp": Time.get_unix_time_from_system(),
		"event_id": event_id
	}
	db.insert_row("character_memories", data)

# 加载角色记忆（最近N条）
func load_character_memories(character_name: String, limit: int = 10) -> Array:
	db.query_with_bindings("SELECT * FROM character_memories WHERE character_name = ? ORDER BY timestamp DESC LIMIT ?", [character_name, limit])
	var memories = []
	for row in db.query_result:
		memories.append(row["memory_content"])
	memories.reverse()  # 时间顺序
	return memories

# 加载所有世界事实
func load_world_facts() -> Array[Dictionary]:
	db.query("SELECT * FROM world_facts ORDER BY timestamp ASC")
	var facts: Array[Dictionary] = []
	for row in db.query_result:
		var fact = {
			"event_id": row["id"],
			"description": row["description"],
			"known_by": JSON.parse_string(row["known_by"]),
			"timestamp": row["timestamp"],
			"location": row["location"]
		}
		facts.append(fact)
	return facts

# 保存游戏
func save_game(slot: int, save_name: String, world_state: WorldState, characters: Array, story_log: Array):
	var data = {
		"slot_id": slot,
		"save_name": save_name,
		"save_time": Time.get_unix_time_from_system(),
		"world_state": JSON.stringify(world_state.to_dict()),
		"characters_data": JSON.stringify(serialize_characters(characters)),
		"story_log": JSON.stringify(story_log)
	}
	
	# 检查是否已存在
	db.query_with_bindings("SELECT slot_id FROM save_slots WHERE slot_id = ?", [slot])
	if db.query_result.size() > 0:
		db.update_rows("save_slots", "slot_id = " + str(slot), data)
	else:
		db.insert_row("save_slots", data)
	
	print("💾 游戏已保存到槽位 %d" % slot)

# 加载游戏
func load_game(slot: int) -> Dictionary:
	db.query_with_bindings("SELECT * FROM save_slots WHERE slot_id = ?", [slot])
	if db.query_result.size() == 0:
		return {}
	
	var row = db.query_result[0]
	return {
		"world_state": JSON.parse_string(row["world_state"]),
		"characters_data": JSON.parse_string(row["characters_data"]),
		"story_log": JSON.parse_string(row["story_log"])
	}

# 序列化角色数据
func serialize_characters(characters: Array) -> Array:
	var data = []
	for character in characters:
		if character is AICharacter:
			data.append({
				"name": character.character_name,
				"personality": character.personality,
				"role_type": character.role_type,
				"hp": character.hp,
				"mana": character.mana,
				"memory": character.memory
			})
	return data
