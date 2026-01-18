# scripts/core/DatabaseManager.gd
extends Node
class_name DatabaseManager

var db: SQLite
var db_path: String = "user://storyweaver.db"
const DB_VERSION: int = 2  # 数据库版本号

func _init():
	db = SQLite.new()
	db.path = db_path
	db.open_db()
	# 检查并迁移数据库
	check_and_migrate()
	create_tables()
	print("✓ 数据库初始化完成: ", db_path)
	
# 数据库版本管理
func check_and_migrate():
	# 创建版本表（如果不存在）
	db.create_table("db_version", {
		"version": {"data_type": "int", "primary_key": true}
	})
	
	# 获取当前版本
	db.query("SELECT version FROM db_version")
	var current_version = 0
	if db.query_result.size() > 0:
		current_version = db.query_result[0]["version"]
	
	print("数据库当前版本: %d，目标版本: %d" % [current_version, DB_VERSION])
	
	# 执行迁移
	if current_version < DB_VERSION:
		migrate_database(current_version, DB_VERSION)

func migrate_database(from_version: int, to_version: int):
	print("⚙️ 开始数据库迁移...")
	
	# 从版本 0 到 1：初始版本
	if from_version < 1:
		print("  创建初始表结构...")
		# 初始表已在 create_tables 中创建
	
	# 从版本 1 到 2：添加 template_id
	if from_version < 2:
		print("  迁移到版本 2: 添加 template_id 字段...")
		
		# 检查 save_slots 表是否存在 template_id 字段
		db.query("PRAGMA table_info(save_slots)")
		var has_template_id = false
		for column in db.query_result:
			if column["name"] == "template_id":
				has_template_id = true
				break
		
		if not has_template_id:
			# 添加 template_id 字段
			db.query("ALTER TABLE save_slots ADD COLUMN template_id TEXT DEFAULT ''")
			print("    ✓ 已添加 template_id 字段")
	
	# 更新版本号
	db.query("DELETE FROM db_version")
	db.insert_row("db_version", {"version": to_version})
	print("✓ 数据库迁移完成，当前版本: %d" % to_version)

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
		"template_id": {"data_type": "text"},  # 记录使用的模板
		"world_state": {"data_type": "text"},
		"characters_data": {"data_type": "text"},
		"story_log": {"data_type": "text"}
	})

# 保存世界事实
func save_world_fact(event: StoryEvent, known_by: Array):
	var data = {
		"id": event.id,
		"description": event.description,
		"event_type": event.event_type,
		"location": event.location,
		"scope": event.scope,
		"timestamp": int(event.timestamp),
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
func save_game(slot: int, save_name: String, template_id: String, world_state: WorldState, characters: Array, story_log: Array):
	var data = {
		"slot_id": slot,
		"save_name": save_name,
		"save_time": Time.get_unix_time_from_system(),
		"template_id": template_id,
		"world_state": JSON.stringify(world_state.to_dict()),
		"characters_data": JSON.stringify(serialize_characters(characters)),
		"story_log": JSON.stringify(story_log)
	}
	
	# 检查是否已存在
	db.query_with_bindings("SELECT slot_id FROM save_slots WHERE slot_id = ?", [slot])
	if db.query_result.size() > 0:
		db.query_with_bindings(
			"UPDATE save_slots SET save_name=?, save_time=?, template_id=?, world_state=?, characters_data=?, story_log=? WHERE slot_id=?",
			[save_name, data.save_time, template_id, data.world_state, data.characters_data, data.story_log, slot]
		)
	else:
		db.insert_row("save_slots", data)
	
	print("💾 游戏已保存到槽位 %d (%s)" % [slot, save_name])

# 加载游戏
func load_game(slot: int) -> Dictionary:
	db.query_with_bindings("SELECT * FROM save_slots WHERE slot_id = ?", [slot])
	if db.query_result.size() == 0:
		return {}
	
	var row = db.query_result[0]
	return {
		"template_id": row.get("template_id", ""), 
		"world_state": JSON.parse_string(row["world_state"]),
		"characters_data": JSON.parse_string(row["characters_data"]),
		"story_log": JSON.parse_string(row["story_log"])
	}
	
# 获取存档列表
func get_save_list() -> Array:
	db.query("SELECT slot_id, save_name, save_time, template_id FROM save_slots ORDER BY save_time DESC")
	var saves = []
	for row in db.query_result:
		saves.append({
			"slot": row["slot_id"],
			"name": row["save_name"],
			"time": row["save_time"],
			"template": row.get("template_id", "unknown")
		})
	return saves
	
# 删除存档
func delete_save(slot: int):
	db.query_with_bindings("DELETE FROM save_slots WHERE slot_id = ?", [slot])
	print("🗑️ 已删除存档槽位 %d" % slot)
	
# 序列化角色数据
func serialize_characters(characters: Array) -> Array:
	var data = []
	for character in characters:
		var char_data = {
			"name": character.character_name,
			"personality": character.personality,
			"role_type": character.role_type
		}
		
		if character is UniversalCharacter:
			# 新版通用角色
			char_data["type"] = "universal"
			char_data["gender"] = character.gender
			char_data["attributes"] = character.attributes
			char_data["relationships"] = character.relationships
			char_data["memory"] = character.memory
		elif character is AICharacter:
			# 旧版角色
			char_data["type"] = "legacy"
			char_data["hp"] = character.hp
			char_data["max_hp"] = character.max_hp
			char_data["mana"] = character.mana
			char_data["max_mana"] = character.max_mana
			char_data["memory"] = character.memory
		else:
			# 未知类型，跳过
			continue
		
		data.append(char_data)
	
	return data
	
# 反序列化角色数据（需要模板）
func deserialize_characters(data: Array, template: WorldTemplate) -> Array:
	var characters = []
	
	for char_data in data:
		var char_type = char_data.get("type", "legacy")
		
		if char_type == "universal":
			# 创建通用角色
			var character = UniversalCharacter.new(
				char_data.name,
				char_data.personality,
				char_data.role_type,
				template
			)
			
			# 恢复属性
			character.gender = char_data.get("gender", "unknown")
			character.attributes = char_data.get("attributes", {})
			character.relationships = char_data.get("relationships", {})
			character.memory = char_data.get("memory", [])
			
			characters.append(character)
			
		elif char_type == "legacy":
			# 创建旧版角色
			var character = AICharacter.new(
				char_data.name,
				char_data.personality,
				char_data.role_type
			)
			
			character.hp = char_data.get("hp", 100)
			character.max_hp = char_data.get("max_hp", 100)
			character.mana = char_data.get("mana", 50)
			character.max_mana = char_data.get("max_mana", 50)
			character.memory = char_data.get("memory", [])
			
			characters.append(character)
	
	return characters
