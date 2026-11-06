extends SceneTree
## ui/sts_targeting.gd 的 headless 测试
## 验证二次贝塞尔计算、控制点高度、状态切换与绘制

const StsTargeting = preload("res://ui/sts_targeting.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var stage := Control.new()
	stage.size = Vector2(1440, 900)
	root.add_child(stage)

	var arrow: Control = StsTargeting.new()
	stage.add_child(arrow)

	# 1. 基础状态检查
	_check(not arrow.get("active"), "initially inactive")
	_check(arrow.mouse_filter == Control.MOUSE_FILTER_IGNORE, "ignores mouse input")

	# 2. 贝塞尔公式静态验证
	var p0 := Vector2(200, 800)
	var p2 := Vector2(800, 300)
	var p1: Vector2 = StsTargeting.calculate_control_point(p0, p2)
	_check(p1.y < minf(p0.y, p2.y), "control point arches above start and end points")

	var mid: Vector2 = StsTargeting.evaluate_bezier(p0, p1, p2, 0.5)
	_check(mid.x > p0.x and mid.x < p2.x, "bezier mid x is between start and end")
	_check(mid.y < p0.y, "bezier mid y arches upward")

	# 3. 启停状态与锁定测试
	arrow.call("start", p0)
	_check(bool(arrow.get("active")), "active after start")
	_check(arrow.visible, "visible after start")

	arrow.call("update_target", Vector2(800, 300), true, Vector2(800, 300), "Enemy_0")
	_check(bool(arrow.get("locked")), "locked is true")
	_check(str(arrow.get("locked_target_name")) == "Enemy_0", "locked target name preserved")

	# 跑若干帧验证 _process 与 _draw
	for i in 5:
		await process_frame

	arrow.call("stop")
	_check(not bool(arrow.get("active")), "inactive after stop")
	_check(not arrow.visible, "hidden after stop")

	var report := {"checks": checks, "failures": failures}
	print("STS_TARGETING_RESULT=" + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
