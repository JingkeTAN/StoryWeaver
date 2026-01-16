# scripts/test/APITest.gd
extends Node

func _ready():
	print("=== 开始API测试 ===")
	test_api()

func test_api():
	print("1. 创建APIClient...")
	var client = APIClient.new()
	add_child(client)
	
	# 等待配置加载
	await get_tree().create_timer(0.5).timeout
	
	print("2. 调用Anthropic API...")
	var result = await client.call_anthropic(
		"你是一个测试助手",
		"请回复'连接成功'这4个字",
		"claude-3-5-sonnet-20241022",
		50
	)
	
	print("3. API返回结果: ", result)
	
	if result.length() > 0:
		print("✅ 测试成功！")
	else:
		print("❌ 测试失败，API没有返回内容")
