extends SceneTree

const Rules := preload("res://core/game_engine.gd")
const StsUI := preload("res://ui/sts_ui.gd")
const CardVisual := preload("res://ui/card_visual.gd")
const OUT_DIR := "res://docs/evidence/ui-rebuild-20261104"


class Backdrop extends Control:
	var tint := Color("0e1311")

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), tint)
		for i in 22:
			var t := float(i) / 21.0
			draw_rect(Rect2(0.0, s.y * t, s.x, s.y / 21.0 + 1.0),
				Color(0.075 + 0.02 * t, 0.09 + 0.022 * t, 0.082 + 0.02 * t, 0.85))
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261104
		for i in 620:
			var p := Vector2(rng.randf() * s.x, rng.randf() * s.y)
			draw_rect(Rect2(p, Vector2(1, 1)), Color(0.85, 0.82, 0.72, 0.015 + rng.randf() * 0.025))
		var rings := 7
		for i in rings:
			var pad := 12.0 * (rings - i)
			var rect := Rect2(pad, pad, s.x - pad * 2.0, s.y - pad * 2.0)
			draw_rect(rect, Color(0.0, 0.0, 0.0, 0.05), false, 24.0)
		draw_line(Vector2(0, 92), Vector2(s.x, 92), Color(0.78, 0.65, 0.42, 0.10), 1.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# project.godot 设了 canvas_items + expand（基准视口 1440×900），窗口缩小后逻辑画布仍是
	# 1440×900；截图必须 1:1，否则 1280×800 只会在逻辑画布左上角画一块、别处是黑边。
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i(0, 0)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var rules := Rules.new("")
	for dims in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dims
		await process_frame
		var page := _build(dims, rules)
		page.position = Vector2.ZERO
		root.add_child(page)
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "%s/sts-ui-overview-%dx%d.png" % [OUT_DIR, dims.x, dims.y]
		var err := image.save_png(path)
		print("CAPTURE ", path, " err=", err, " image=", image.get_size(), " root=", root.size)
		page.queue_free()
		await process_frame
	quit()


func _build(dims: Vector2i, rules) -> Control:
	var page := Control.new()
	page.name = "StsOverview"
	page.size = Vector2(dims)
	var pal: Dictionary = StsUI.palette()
	var night: Color = pal.night
	var panel_color: Color = pal.panel
	var bone: Color = pal.bone
	var gold: Color = pal.gold
	var danger: Color = pal.danger
	var ally: Color = pal.ally
	var cold: Color = pal.cold
	var muted: Color = Color("8a8b7d")
	var body_font: Font = StsUI.label_font()
	var serif: Font = StsUI.serif_font()

	var bg := Backdrop.new()
	bg.size = page.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)

	_label(page, 48, 20, "灰誓 · STS 控件库", serif, 34, bone)
	_label(page, 50, 70, "全自绘 _draw() · 无外部贴图 · 1440×900 / 1280×800 · UI 重构 2026-11-04", body_font, 13, muted)
	var header_rule = StsUI.rule_line(dims.x - 96)
	header_rule.position = Vector2(48, 96)
	page.add_child(header_rule)

	var hud_x := 48.0
	var hud_w := 336.0
	var hud = StsUI.cut_panel(panel_color, gold)
	hud.position = Vector2(hud_x, 122)
	hud.size = Vector2(hud_w, dims.y - 236)
	page.add_child(hud)

	_label(page, hud_x + 18, 132, "ENERGY", body_font, 11, muted)
	var orb = StsUI.energy_orb(3, 3)
	orb.position = Vector2(hud_x + 20, 150)
	page.add_child(orb)
	_label(page, hud_x + 120, 132, "HP · hp_bar(28, 42)", body_font, 11, muted)
	var hp = StsUI.hp_bar(28, 42, danger, 0)
	hp.size = Vector2(198, 10)
	hp.position = Vector2(hud_x + 120, 156)
	page.add_child(hp)
	_label(page, hud_x + 120, 172, "BLOCK · hp_bar(28, 42, blocked=7)", body_font, 11, muted)
	var hp_block = StsUI.hp_bar(28, 42, danger, 7)
	hp_block.size = Vector2(198, 10)
	hp_block.position = Vector2(hud_x + 120, 196)
	page.add_child(hp_block)

	_label(page, hud_x + 18, 252, "PILES · pile_counter(title, count, kind)", body_font, 11, muted)
	var pile_specs := [["抽牌", 12, "draw"], ["弃牌", 7, "discard"], ["消耗", 3, "exhaust"]]
	var px := hud_x + 24.0
	for spec in pile_specs:
		var pile = StsUI.pile_counter(str(spec[0]), int(spec[1]), str(spec[2]))
		pile.position = Vector2(px, 272)
		page.add_child(pile)
		px += 98.0

	_label(page, hud_x + 18, 380, "INTENT · intent_badge(kind, value, vulnerable)", body_font, 11, muted)
	var intent_specs := [["attack", 12, false], ["defend", 8, false], ["buff", 3, false], ["debuff", 2, true]]
	var bx := hud_x + 20.0
	for spec in intent_specs:
		var badge = StsUI.intent_badge(str(spec[0]), int(spec[1]), bool(spec[2]))
		badge.position = Vector2(bx, 400)
		page.add_child(badge)
		bx += 74.0

	_label(page, hud_x + 18, 478, "STATUS · chip(text, tone)", body_font, 11, muted)
	var chip_specs := [["易伤 2", danger], ["虚弱 1", cold], ["中毒 4", ally], ["力量 3", gold], ["格挡 12", cold], ["再生 4", ally]]
	var cx := hud_x + 20.0
	var cy := 498.0
	for spec in chip_specs:
		var chip = StsUI.chip(str(spec[0]), spec[1])
		page.add_child(chip)
		var chip_w: float = chip.custom_minimum_size.x
		if cx + chip_w > hud_x + hud_w - 18.0:
			cx = hud_x + 20.0
			cy += 28.0
		chip.position = Vector2(cx, cy)
		cx += chip_w + 8.0

	_label(page, hud_x + 18, cy + 46, "BUTTON · button_style(state)", body_font, 11, muted)
	var button_labels := ["结束回合", "悬停 hover", "按下 pressed", "禁用 disabled"]
	var button_states := ["normal", "hover", "pressed", "disabled"]
	for i in 4:
		var button = StsUI.pedestal_button(str(button_labels[i]))
		button.custom_minimum_size = Vector2(144, 40)
		button.size = Vector2(144, 40)
		button.add_theme_stylebox_override("normal", StsUI.button_style(str(button_states[i])))
		button.add_theme_font_size_override("font_size", 14)
		if i == 3:
			button.disabled = true
			button.add_theme_stylebox_override("disabled", StsUI.button_style("disabled"))
		button.position = Vector2(hud_x + 22 + (i % 2) * 150, cy + 66 + int(i / 2) * 48)
		page.add_child(button)

	var rx := 420.0
	var rw := float(dims.x) - 48.0 - rx
	_label(page, rx, 116, "BROWSE / REWARD / PREVIEW · 230×290", serif, 17, gold)
	var preview_y := 146.0 if dims.y >= 900 else 138.0
	var pw := 230.0
	var ph := 290.0
	var gap := 24.0
	var preview_ids := ["neutral_16", "neutral_09", "warden_29"]
	var preview_ctx := ["preview", "reward", "browse"]
	var preview_up := [false, true, false]
	var total := pw * 3.0 + gap * 2.0
	var px0 := rx + (rw - total) * 0.5
	for i in 3:
		var card: Dictionary = rules.card_view({"id": str(preview_ids[i]), "upgraded": bool(preview_up[i])})
		_card(page, Vector2(px0 + i * (pw + gap), preview_y), Vector2(pw, ph), card, str(preview_ctx[i]), serif)

	var hand_label_y := preview_y + 306.0
	_label(page, rx, hand_label_y, "HAND · 188×232 · 四种上下文只换角标文案", serif, 17, gold)
	var hw := 188.0
	var hh := 232.0
	var hgap := 14.0
	var hand_y := hand_label_y + 30.0
	var hand_ids := ["neutral_01", "neutral_03", "neutral_06", "neutral_11"]
	var hand_ctx := ["hand", "hand", "reward", "preview"]
	var htotal := hw * 4.0 + hgap * 3.0
	var hx0 := rx + (rw - htotal) * 0.5
	for i in 4:
		var card: Dictionary = rules.card_view({"id": str(hand_ids[i]), "upgraded": false})
		_card(page, Vector2(hx0 + i * (hw + hgap), hand_y), Vector2(hw, hh), card, str(hand_ctx[i]), serif)

	_label(page, 50, float(dims.y) - 54.0, "所有控件均可 new() 构造、可设 size、不依赖贴图；色板取自 docs/DESIGN.md（夜底/面板/骨白/旧金/危险/盟友/冷光）。", body_font, 12, muted)
	var foot_rule = StsUI.rule_line(dims.x - 96)
	foot_rule.position = Vector2(48, float(dims.y) - 26.0)
	page.add_child(foot_rule)
	return page


func _label(parent: Control, x: float, y: float, text: String, font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = Vector2(x, y)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _card(parent: Control, pos: Vector2, dims: Vector2, definition: Dictionary, display: String, title_font: Font) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.position = pos
	button.size = dims
	button.custom_minimum_size = dims
	parent.add_child(button)
	var visual := CardVisual.new()
	button.add_child(visual)
	visual.configure(button, definition, dims, title_font, display)
	if display == "reward":
		visual.set_availability("星辰不足")
	return button
