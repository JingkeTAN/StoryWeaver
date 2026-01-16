# scripts/core/APIClient.gd
extends Node
class_name APIClient

var config: Dictionary = {}

signal client_ready

func _ready():
	load_config()
	emit_signal("client_ready")

func load_config():
	var file = FileAccess.open("res://config/api_config.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		config = JSON.parse_string(json_string)
		file.close()
		print("✓ API配置加载成功")
	else:
		push_error("❌ 找不到API配置文件")

func call_chat_completion(
	system_prompt: String,
	user_message: String,
	model: String = "gpt-4o",
	max_tokens: int = 500
) -> String:
	var http := HTTPRequest.new()
	add_child(http)

	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + config.openai.api_key
	]

	var body = {
		"model": model,
		"messages": [
			{ "role": "system", "content": system_prompt },
			{ "role": "user", "content": user_message }
		],
		"max_tokens": max_tokens
	}

	var url = config.openai.base_url + "/chat/completions"
	print("📡 请求:", url)
	print("📤 请求体:", JSON.stringify(body))

	var err = http.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if err != OK:
		push_error("❌ HTTPRequest.request 失败，错误码: %s" % err)
		return ""

	var result = await http.request_completed
	http.queue_free()

	var status = result[1]
	var raw = result[3].get_string_from_utf8()

	print("📥 状态码:", status)
	print("📥 原始响应:", raw)

	if status != 200:
		push_error("API 错误")
		return ""

	var json = JSON.parse_string(raw)
	if json == null:
		push_error("JSON 解析失败")
		return ""

	if json.has("choices") and json.choices.size() > 0:
		return json.choices[0].message.content

	push_error("没有返回 choices")
	return ""
