extends SceneTree
## ui/sts_ui.gd 的 headless 冒烟测试：只构造控件、量尺寸、验状态，不渲染截图。
## 输出 STS_UI_RESULT={"checks":N,"failures":[]}

const StsUI = preload("res://ui/sts_ui.gd")
const STATES := ["normal", "hover", "pressed", "disabled"]

var checks := 0
var failures: Array[String] = []
var stage: Control


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _settle(frames: int = 3) -> void:
	for ignored in frames:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1440, 900)
	stage = Control.new()
	stage.name = "StsUiStage"
	stage.size = Vector2(1440, 900)
	root.add_child(stage)
	_check_palette()
	_check_fonts()
	_check_styleboxes()
	_check_hp_bar()
	_check_energy_orb()
	_check_pile_counter()
	_check_intent_badge()
	_check_chip()
	_check_rule_line()
	_check_cut_panel()
	await _check_render_both_sizes()
	var report := {"checks": checks, "failures": failures}
	print("STS_UI_RESULT=" + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _check_palette() -> void:
	var palette := StsUI.palette()
	for key in ["night", "panel", "bone", "gold", "danger", "ally", "cold"]:
		_check(palette.has(key), "palette has " + key)
		_check(palette.get(key) is Color, "palette " + key + " is Color")
	_check(palette.size() == 7, "palette exposes exactly seven tones")
	_check(palette["night"] == Color("0e1311"), "night equals design #0E1311")
	_check(palette["gold"] == Color("c7a66a"), "gold equals design #C7A66A")
	_check(palette["danger"] == Color("ae5148"), "danger equals design #AE5148")


func _check_fonts() -> void:
	var body: Font = StsUI.label_font()
	var serif: Font = StsUI.serif_font()
	_check(body != null, "label_font returns a Font")
	_check(serif != null, "serif_font returns a Font")
	_check(body.get_height(17) > 10.0, "label_font measures text at 17px")
	var ladder: Array[int] = []
	for index in 7:
		ladder.append(StsUI.font_step(index))
	_check(ladder == [11, 13, 15, 17, 20, 26, 34], "font ladder is 11/13/15/17/20/26/34, got " + str(ladder))


func _check_styleboxes() -> void:
	var plate: StyleBoxFlat = StsUI.panel()
	_check(plate != null, "panel returns StyleBoxFlat")
	_check(plate.bg_color.a > 0.85, "panel fill is near opaque")
	_check(plate.border_width_top == 1 and plate.border_width_left == 1, "panel has 1px gold hairline")
	_check(plate.content_margin_left >= 6.0 and plate.content_margin_top >= 4.0, "panel keeps content off the cut corners")
	_check(plate.has_meta("cut"), "panel remembers its cut size")

	var signatures: Array[String] = []
	for state in STATES:
		var box: StyleBoxFlat = StsUI.button_style(state)
		_check(box != null, "button_style(" + state + ") returns StyleBoxFlat")
		_check(box.border_width_top >= 1, "button_style(" + state + ") keeps the top highlight line")
		signatures.append(str(box.bg_color) + "|" + str(box.border_color) + "|" + str(box.content_margin_top) + "|" + str(box.get_meta("lift")))
	_check(signatures[0] != signatures[1], "hover differs from normal")
	_check(signatures[1] != signatures[2], "pressed differs from hover")
	_check(signatures[2] != signatures[3], "disabled differs from pressed")
	_check(signatures[0] != signatures[3], "disabled differs from normal")
	var hover: StyleBoxFlat = StsUI.button_style("hover")
	_check(float(hover.get_meta("lift")) == 1.0, "hover asks the caller to lift by 1px")
	_check(hover.border_color.v > StsUI.button_style("normal").border_color.v, "hover edge is brighter")


func _check_hp_bar() -> void:
	var bar: Control = StsUI.hp_bar(5, 20, Color("ae5148"), 3)
	_check(bar != null, "hp_bar instantiates")
	_check(is_equal_approx(float(bar.get("ratio")), 0.25), "hp_bar ratio is 5/20 = 0.25")
	_check(int(bar.get("blocked")) == 3, "hp_bar keeps the block segment value")
	_check(bar.custom_minimum_size.y >= 8.0 and bar.custom_minimum_size.y <= 14.0, "hp_bar is a thin 8~10px strip")
	bar.call("set_values", 20, 20, 0)
	_check(is_equal_approx(float(bar.get("ratio")), 1.0), "hp_bar ratio is 1.0 at full health")
	bar.call("set_block", 4)
	_check(int(bar.get("blocked")) == 4, "hp_bar set_block updates the guard segment")
	bar.call("set_values", 0, 0, 0)
	_check(float(bar.get("ratio")) >= 0.0, "hp_bar clamps a zero maximum without dividing by zero")


func _check_energy_orb() -> void:
	var orb: Control = StsUI.energy_orb(3, 3)
	_check(orb != null, "energy_orb instantiates")
	_check(str(orb.get("value_text")) == "3", "energy_orb shows 3")
	_check(str(orb.get("sub_label")) == "能量", "energy_orb caption is 能量")
	orb.call("set_value", 2, 5)
	_check(str(orb.get("value_text")) == "2", "energy_orb text follows set_value")
	_check(int(orb.get("maximum")) == 5, "energy_orb keeps the maximum")
	_check(orb.custom_minimum_size.x >= 60.0, "energy_orb reserves room for the numeral")


func _check_pile_counter() -> void:
	var pile: Control = StsUI.pile_counter("抽牌", 7, "draw")
	_check(pile != null, "pile_counter instantiates")
	_check(str(pile.get("title")) == "抽牌" and int(pile.get("count")) == 7, "pile_counter keeps title and count")
	_check(str(pile.get("icon_kind")) == "draw", "pile_counter keeps the draw glyph")
	pile.call("setup", "弃牌", 3, "discard")
	_check(str(pile.get("icon_kind")) == "discard" and int(pile.get("count")) == 3, "pile_counter switches to the discard glyph")
	var draw_tone: Color = StsUI.pile_counter("抽牌", 1, "draw").get("tone")
	var discard_tone: Color = pile.get("tone")
	_check(draw_tone != discard_tone, "draw and discard use different tones")


func _check_intent_badge() -> void:
	var badge: Control = StsUI.intent_badge("attack", 6, false)
	_check(badge != null, "intent_badge instantiates")
	_check(str(badge.get("kind")) == "attack", "intent_badge starts as attack")
	var attack_tone: Color = badge.get("tone")
	_check(attack_tone == Color("ae5148"), "attack intent is danger red")
	badge.call("set_kind", "defend", true)
	_check(str(badge.get("kind")) == "defend", "intent_badge switches to defend")
	var defend_tone: Color = badge.get("tone")
	_check(defend_tone == Color("9fbfc4"), "defend intent is cold blue")
	_check(defend_tone != attack_tone, "kind switch changes the badge colour")
	badge.call("set_kind", "buff", true)
	_check(str(badge.get("kind")) == "buff" and badge.get("tone") == Color("c7a66a"), "buff intent is old gold")
	badge.call("set_value", 9, true)
	_check(int(badge.get("value")) == 9, "intent_badge set_value updates the number")
	_check(bool(badge.get("_pulse_active")), "value change starts the scale pulse")
	badge.call("set_vulnerable", true)
	_check(bool(badge.get("vulnerable")), "intent_badge records the vulnerable marker")


func _check_chip() -> void:
	var tag: Control = StsUI.chip("易伤", Color("ae5148"))
	_check(tag != null, "chip instantiates")
	_check(str(tag.get("text")) == "易伤", "chip keeps its text")
	_check(tag.custom_minimum_size.x >= 34.0, "chip asks for text-sized width")
	_check(tag.custom_minimum_size.y == 20.0, "chip is a 20px status tag")
	_check(tag.get("tone") == Color("ae5148"), "chip keeps its tone")


func _check_rule_line() -> void:
	var rule: Control = StsUI.rule_line(420.0)
	_check(rule != null, "rule_line instantiates")
	_check(is_equal_approx(float(rule.get("line_width")), 420.0), "rule_line keeps its width")
	_check(rule.custom_minimum_size.x == 420.0, "rule_line reserves its width")
	_check(rule.custom_minimum_size.y <= 16.0, "rule_line stays a thin divider")


func _check_cut_panel() -> void:
	var plate: Control = StsUI.cut_panel(Color("1a201c"), Color("c7a66a"), 14.0)
	_check(plate != null, "cut_panel instantiates")
	_check(is_equal_approx(float(plate.get("cut")), 14.0), "cut_panel keeps its cut size")
	plate.call("setup", Color("111311"), Color("7fa98c"), 8.0)
	_check(plate.get("edge") == Color("7fa98c"), "cut_panel setup repaints the edge")


func _check_render_both_sizes() -> void:
	for dimensions in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dimensions
		var hud := Control.new()
		hud.size = Vector2(dimensions)
		stage.add_child(hud)
		var plate: Control = StsUI.cut_panel()
		plate.custom_minimum_size = Vector2(240, 132)
		var widgets: Array[Control] = [
			StsUI.hp_bar(31, 40, Color("ae5148"), 6),
			StsUI.energy_orb(3, 3),
			StsUI.pile_counter("抽牌", 5, "draw"),
			StsUI.intent_badge("attack", 11, true),
			StsUI.chip("力量 +2", Color("7fa98c")),
			StsUI.rule_line(360.0),
			plate,
		]
		var cursor := Vector2(24, 24)
		for widget in widgets:
			widget.position = cursor
			widget.size = widget.custom_minimum_size
			hud.add_child(widget)
			cursor.x += widget.size.x + 16.0
			if cursor.x > float(dimensions.x) - 80.0:
				cursor = Vector2(24, cursor.y + 110.0)
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		for widget in widgets:
			var label := str(widget.get_script().resource_path) + "#" + str(widget.get_instance_id())
			_check(widget.size.x > 0.0 and widget.size.y > 0.0, "widget has a real size at " + str(dimensions) + " " + label)
			_check(bounds.encloses(widget.get_global_rect()), "widget stays inside " + str(dimensions) + " " + label)
			_check(widget.find_children("*", "Control", true, false).is_empty(), "widget is fully self-drawn " + label)
		_check(widgets[0].get_global_rect().end.y <= widgets[0].get_global_rect().position.y + 14.0, "hp bar stays a thin strip at " + str(dimensions))
		hud.queue_free()
		await _settle()
	root.size = Vector2i(1440, 900)
