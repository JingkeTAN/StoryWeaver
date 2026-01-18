# scripts/core/TemplateManager.gd
extends Node
class_name TemplateManager

var templates: Dictionary = {}  # {template_id: WorldTemplate}
var current_template: WorldTemplate

const TEMPLATE_DIR = "res://world_templates/"
const USER_TEMPLATE_DIR = "user://custom_templates/"

func _init():
	load_all_templates()

func load_all_templates():
	# 加载内置模板
	_load_templates_from_dir(TEMPLATE_DIR)
	
	# 加载用户自定义模板
	if DirAccess.dir_exists_absolute(USER_TEMPLATE_DIR):
		_load_templates_from_dir(USER_TEMPLATE_DIR)
	
	print("✓ 共加载 %d 个世界观模板" % templates.size())

func _load_templates_from_dir(dir_path: String):
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".json"):
			var full_path = dir_path + file_name
			var template = WorldTemplate.load_from_file(full_path)
			if template:
				templates[template.template_id] = template
		file_name = dir.get_next()

func get_template(template_id: String) -> WorldTemplate:
	return templates.get(template_id)

func set_current_template(template_id: String) -> bool:
	if templates.has(template_id):
		current_template = templates[template_id]
		print("✓ 切换到模板: %s" % current_template.template_name)
		return true
	return false

func get_template_list() -> Array:
	var list = []
	for id in templates.keys():
		var tmpl = templates[id]
		list.append({
			"id": tmpl.template_id,
			"name": tmpl.template_name,
			"description": tmpl.description
		})
	return list

# 保存用户自定义模板
func save_custom_template(template_data: Dictionary) -> bool:
	# 确保目录存在
	if not DirAccess.dir_exists_absolute(USER_TEMPLATE_DIR):
		DirAccess.make_dir_absolute(USER_TEMPLATE_DIR)
	
	var file_path = USER_TEMPLATE_DIR + template_data.template_id + ".json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if not file:
		push_error("无法保存模板: " + file_path)
		return false
	
	file.store_string(JSON.stringify(template_data, "\t"))
	file.close()
	
	# 重新加载
	var template = WorldTemplate.from_dict(template_data)
	templates[template.template_id] = template
	
	print("✓ 保存自定义模板: %s" % template.template_name)
	return true
