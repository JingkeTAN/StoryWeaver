# scripts/ui/StoryView.gd (附加到Main节点)
extends Control

@onready var story_text: RichTextLabel = $VBoxContainer/StoryDisplay/MarginContainer/StoryText
@onready var input_field: LineEdit = $VBoxContainer/InputArea/InputField
@onready var send_button: Button = $VBoxContainer/InputArea/SendButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
#@onready var story_engine: StoryEngine = $StoryEngine

var is_processing: bool = false

func _ready():
	# 确认节点路径正确
	print("=== StoryView _ready 被调用 ===")
	print("send_button 路径: ", send_button.get_path())
	print("StoryEngineGlobal 路径: ", StoryEngineGlobal.get_path())
	# 连接信号
	send_button.pressed.connect(_on_send_pressed)
	input_field.text_submitted.connect(_on_input_submitted)
	# 验证连接
	print("=== 信号连接验证 ===")
	print("send_button 是否存在: ", send_button != null)
	print("input_field 是否存在: ", input_field != null)
	print("story_engine 是否存在: ", StoryEngineGlobal != null)
	
	
	
	StoryEngineGlobal.story_updated.connect(_on_story_updated)
	StoryEngineGlobal.processing_started.connect(_on_processing_started)
	StoryEngineGlobal.processing_finished.connect(_on_processing_finished)
	
	# 初始文本
	story_text.text = "[center][b]欢迎来到 StoryWeaver[/b][/center]\n\n输入你想要的剧情发展..."
	status_label.text = "就绪"

func _on_send_pressed():
	submit_input()

func _on_input_submitted(_text: String):
	submit_input()

func submit_input():
	print("\n=== submit_input 被调用 ===")
	print("is_processing: ", is_processing)
	if is_processing:
		print("❌ 正在处理中，忽略")
		return
	
	var user_input = input_field.text.strip_edges()
	print("用户输入: ", user_input)
	if user_input.is_empty():
		print("❌ 输入为空")
		return
	
	# 显示用户输入
	append_to_story("\n[color=cyan][b]你：[/b]%s[/color]\n" % user_input)
	
	# 清空输入框
	input_field.text = ""
	
	print("开始调用 StoryEngine.process_player_input...")
	# 处理
	StoryEngineGlobal.process_player_input(user_input)

func _on_story_updated(narrative: String):
	append_to_story("\n" + narrative + "\n")
	# 滚动到底部
	story_text.scroll_to_line(story_text.get_line_count())

func _on_processing_started():
	is_processing = true
	send_button.disabled = true
	status_label.text = "AI思考中..."

func _on_processing_finished():
	is_processing = false
	send_button.disabled = false
	status_label.text = "就绪"

func append_to_story(text: String):
	story_text.text += text
