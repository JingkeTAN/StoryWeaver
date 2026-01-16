# scripts/core/StoryEngine.gd
extends Node
class_name StoryEngine

signal story_updated(text: String)
signal processing_started()
signal processing_finished()

var api_client: APIClient
var characters: Array[AICharacter] = []
var story_log: Array[String] = []

const MODEL_DESIGNER = "gpt-3.5-turbo"
const MODEL_NARRATOR = "claude-3-5-haiku-latest"

func _ready():
	print("=== StoryEngine 初始化 ===")
	api_client = APIClient.new()
	add_child(api_client)
	print("APIClient 已添加")
	#await api_client.client_ready  # 等待API配置加载
	
	# 初始化3个角色
	setup_default_characters()
	print("✓ StoryEngine 初始化完成")
	
func setup_default_characters():
	var protagonist = AICharacter.new(
		"艾伦",
		"一个勇敢但略显鲁莽的年轻剑士，正义感强",
        "protagonist"
	)
	
	var companion = AICharacter.new(
		"萨莉",
		"聪明机智的精灵法师，善于分析局势",
        "companion"
	)
	
	var narrator = AICharacter.new(
		"旁白",
		"客观的故事讲述者",
        "narrator"
	)
	
	characters = [protagonist, companion, narrator]
	var names := []
	for c in characters:
		names.append(c.character_name)
	print("✓ 角色初始化完成：", names)

# 主流程
func process_player_input(player_input: String):
	print("\n=== process_player_input 被调用 ===")
	emit_signal("processing_started")
	print("\n=== 处理玩家输入 ===")
	print("玩家: ", player_input)
	
	# Step 1: 设计师生成事件
	var event = await generate_event_from_designer(player_input)
	print("设计师生成事件: ", event)
	# 如果没有返回，提前结束
	if event.is_empty():
		print("❌ 设计师没有返回内容")
		emit_signal("processing_finished")
		return
	# Step 2: 让角色们响应（简化版：所有角色都知道）
	var responses = await gather_character_responses(event)
	
	# Step 3: 讲述者整合
	var narrative = await compose_narrative(event, responses)
	print("最终叙事: ", narrative)
	
	# 更新记忆
	for character in characters:
		character.add_memory(event)
	
	story_log.append(narrative)
	emit_signal("story_updated", narrative)
	emit_signal("processing_finished")

# 设计师层
func generate_event_from_designer(player_input: String) -> String:
	var context = get_story_context()
	
	var prompt = """
当前故事进展：
%s

玩家需求："%s"

请设计接下来发生的事件（100-150字）：
- 要符合玩家的需求
- 要有一定的冲突或转折
- 要给角色留下反应空间
""" % [context, player_input]
	
	var system = "你是一个TRPG游戏主持人（GM），擅长设计有趣的剧情事件。"
	
	var event = await api_client.call_chat_completion(
		system,
		prompt,
		MODEL_DESIGNER,
		300
	)
	
	return event

# 收集角色响应
func gather_character_responses(event: String) -> Array[Dictionary]:
	var responses: Array[Dictionary] = []
	
	# MVP阶段：顺序调用（后续可并发）
	for character in characters:
		if character.role_type == "narrator":
			continue  # 旁白暂不参与决策
		
		print("等待 %s 的决策..." % character.character_name)
		var decision = await character.make_decision(event, api_client)
		responses.append(decision)
	
	return responses

# 讲述者整合
func compose_narrative(event: String, responses: Array[Dictionary]) -> String:
	var responses_text = ""
	for r in responses:
		responses_text += "[%s]: %s\n" % [r.character, r.response]
	
	var prompt = """
事件：
%s

角色反应：
%s

请将这些素材整合成一段连贯、优美的叙事文本（200-300字）：
- 使用第三人称
- 保持文学性
- 自然融合角色的行动和对话
""" % [event, responses_text]
	
	var system = "你是一位专业的故事讲述者，擅长用优美的文字编织叙事。"
	
	var narrative = await api_client.call_chat_completion(
		system,
		prompt,
		MODEL_NARRATOR,  # 讲述者用最好的模型
		500
	)
	
	return narrative

# 获取故事上下文
func get_story_context() -> String:
	if story_log.size() == 0:
		return "故事刚刚开始，艾伦和萨莉正在一片森林中探险。"
	else:
		# 返回最近3条
		var recent = story_log.slice(-3) if story_log.size() > 3 else story_log
		return "\n".join(recent)
