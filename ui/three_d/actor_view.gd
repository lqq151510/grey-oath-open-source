class_name ActorView
extends Control
## 灰誓 · 3D 角色视图（rig3d）
##
## 与 ui/combat_actor.gd 的公开 API 完全兼容：main.gd 只要 load 这个脚本就能
## 把 2D 沙盘换成 SubViewport 里的分面低模。
## headless 下只建 CPU 骨架（不建 SubViewport / 相机 / 灯 / 贴图），所有 API 仍可调用。

const ActorRig := preload("res://ui/three_d/actor_rig.gd")
const ActorLibrary := preload("res://ui/three_d/actor_library.gd")

const VIEW_SIZE := 512
const CAMERA_FOV := 32.0
const ATTACK_TIME := 0.48
const HIT_TIME := 0.42
const GUARD_TIME := 0.36
const DEATH_TIME := 0.65
const PLAYER_YAW := 22.0
const ENEMY_YAW := -22.0
## 连击窗口：窗口内再次攻击跳过蓄力段，动作更连贯。
const COMBO_WINDOW := 0.45
## 各攻击风格从起手到命中的设计时长（秒）；运行时按 animation_speed 缩放。
const ATTACK_WINDUP := {"slash": 0.16, "cast": 0.14, "thrust": 0.16, "pounce": 0.14, "dive": 0.12}

class StatusFxOverlay extends Control:
	var statuses: Dictionary = {}
	var flashes: Dictionary = {"weak": 0.0, "vulnerable": 0.0, "regen": 0.0}
	var heal_time := 0.0
	var clock := 0.0
	var reduced_motion := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func set_statuses(value: Dictionary) -> void:
		statuses = value.duplicate(true)
		queue_redraw()

	func play_status(key: String) -> void:
		if flashes.has(key):
			flashes[key] = 0.82
		queue_redraw()

	func play_heal() -> void:
		heal_time = 0.78
		queue_redraw()

	func _process(delta: float) -> void:
		if not reduced_motion:
			clock += delta
		heal_time = maxf(0.0, heal_time - delta)
		for key in flashes:
			flashes[key] = maxf(0.0, float(flashes[key]) - delta)
		queue_redraw()

	func _draw() -> void:
		var center := Vector2(size.x * 0.5, size.y * 0.47)
		var phase := 0.0 if reduced_motion else clock
		var weak := maxf(0.40 if int(statuses.get("weak", 0)) > 0 else 0.0, float(flashes.get("weak", 0.0)))
		if weak > 0.0:
			var blue := Color("49c9e8", weak * 0.9)
			var ring_center := center + Vector2(0, 8)
			draw_arc(ring_center, 47.0 + sin(phase * 2.0) * 2.0, phase * 1.4, phase * 1.4 + PI * 1.25, 32, blue, 3.2, true)
			draw_arc(ring_center, 54.0, -phase * 0.9, -phase * 0.9 + PI * 0.75, 24, Color(blue, blue.a * 0.58), 1.8, true)
			for i in 3:
				var angle := phase * 1.1 + i * TAU / 3.0
				draw_circle(ring_center + Vector2.from_angle(angle) * 50.0, 3.1, Color(blue, blue.a))
		var vulnerable := maxf(0.38 if int(statuses.get("vulnerable", 0)) > 0 else 0.0, float(flashes.get("vulnerable", 0.0)))
		if vulnerable > 0.0:
			var red := Color("ff624f", vulnerable * 0.88)
			draw_arc(center, 39.0 + sin(phase * 2.6) * 2.0, -0.2, TAU - 0.2, 36, red, 3.6, true)
			for i in 6:
				var direction := Vector2.from_angle(phase * 0.45 + i * TAU / 6.0)
				var origin := center + direction * 38.0
				draw_line(origin, origin + direction * 11.0, Color(red, red.a * 0.92), 2.5, true)
		var regen := maxf(0.34 if int(statuses.get("regen", 0)) > 0 else 0.0, float(flashes.get("regen", 0.0)))
		if regen > 0.0:
			var green := Color("7fe49b", regen * 0.94)
			for i in 4:
				var seed := float(i) * 1.71
				var travel := fposmod(phase * 0.48 + seed, 1.0)
				var x := size.x * 0.5 + sin(seed * 3.0) * 33.0
				var y := size.y * 0.75 - travel * size.y * 0.48
				draw_circle(Vector2(x, y), 2.8 + (1.0 - travel), Color(green, green.a * (1.0 - travel * 0.38)))
			if float(flashes.get("regen", 0.0)) > 0.0:
				var plus := center + Vector2(-34, -22 - (0.82 - float(flashes.regen)) * 18.0)
				draw_line(plus - Vector2(4, 0), plus + Vector2(4, 0), green, 2.4, true)
				draw_line(plus - Vector2(0, 4), plus + Vector2(0, 4), green, 2.4, true)
		if heal_time > 0.0:
			var progress := 1.0 - heal_time / 0.78
			var heal_color := Color("d6ffd0", (1.0 - progress) * 0.94)
			draw_arc(center, 18.0 + progress * 40.0, 0.0, TAU, 32, heal_color, 3.6 * (1.0 - progress) + 1.0, true)
			for i in 4:
				var ray := Vector2.from_angle(i * TAU / 4.0 + PI * 0.25)
				draw_line(center + ray * (13.0 + progress * 13.0), center + ray * (24.0 + progress * 30.0), heal_color, 2.0, true)

# ---- 与 CombatActor 对齐的公开状态 ----
var archetype := "humanoid"
var player := false
var selected := false
var dead := false
var accent := Color("c7a66a")
var role_id := ""
var role_art: Texture2D = null
var rank := 0
var clock := 0.0
var idle_seed := 0
var attack_time := 0.0
var hit_time := 0.0
var death_time := 0.0
var guard_time := 0.0
var shield_hit := false
var held := false
var animation_speed := 1.0
var reduced_motion := false
var height := 1.9
var bulk := 1.0
var health := 0
var max_health := 0

var _spec: Dictionary = {}
var _stage_ready := false
var _viewport: SubViewport = null
var _texture_rect: TextureRect = null
var _effect_overlay: StatusFxOverlay = null
var _world_root: Node3D = null
var _camera: Camera3D = null
var _key_light: DirectionalLight3D = null
var _fill_light: DirectionalLight3D = null
var _rim_light: DirectionalLight3D = null
var _warm_rim: DirectionalLight3D = null
var _bounce_light: DirectionalLight3D = null
var _world_env: WorldEnvironment = null
var _shadow: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _glow: Sprite3D = null
var _rig: Node3D = null
var _pivots: Dictionary = {}
var _base_pos: Dictionary = {}
var _base_rot: Dictionary = {}
var _base_scale: Dictionary = {}
var _flash_mats: Array = []
var _flash_tint := Color(1.0, 0.94, 0.86)
var _flash := 0.0
var _flash_tween: Tween = null
var _ember_particles: CPUParticles3D = null
var _tween: Tween = null
var _last_attack_at := -10.0
var _attack_combo := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(180, 144)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = false


func _ready() -> void:
	if not _spec.is_empty():
		_ensure_stage()
		_build_rig()
		_frame_camera()


func setup(entity: Dictionary, definition: Dictionary = {}, is_player: bool = false) -> void:
	if not entity is Dictionary:
		entity = {}
	if not definition is Dictionary:
		definition = {}
	player = is_player
	var entity_status: Variant = entity.get("status", {})
	var built_spec: Dictionary = ActorLibrary.spec_for(entity, definition, is_player)
	_spec = built_spec
	role_id = str(built_spec.get("role", entity.get("role", "")))
	# 与 CombatActor 对齐：玩家角色的 archetype 就是 role id（combat_actor.gd:43,62）。
	# 敌人仍用视觉体型，main 与测试都依赖这个区分。
	if is_player and role_id != "":
		archetype = role_id
	else:
		archetype = str(built_spec.get("archetype", "humanoid"))
	accent = _to_color(str(built_spec.get("palette", {}).get("accent", "")), Color("c7a66a"))
	height = float(built_spec.get("height", 1.9))
	bulk = float(built_spec.get("bulk", 1.0))
	rank = 2 if str(entity.get("kind", "")) == "boss" else (1 if str(entity.get("kind", "")) == "elite" else 0)
	idle_seed = abs(int(built_spec.get("seed", abs(str(built_spec.get("id", "actor")).hash())))) % 997
	max_health = int(entity.get("max_hp", entity.get("hp", 0)))
	health = int(entity.get("hp", max_health))
	# 重置演出状态（main 会复用同一个 actor 实例）
	dead = false
	shield_hit = false
	selected = false
	attack_time = 0.0
	hit_time = 0.0
	guard_time = 0.0
	death_time = 0.0
	_flash = 0.0
	clock = 0.0
	_last_attack_at = -10.0
	_attack_combo = false
	modulate = Color(1, 1, 1, 1)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_ensure_stage()
	if _effect_overlay != null:
		_effect_overlay.reduced_motion = reduced_motion
		_effect_overlay.set_statuses(entity_status if entity_status is Dictionary else {})
	_build_rig()
	_frame_camera()
	_apply_flash(0.0)


func set_selected(value: bool) -> void:
	selected = value
	if _ring != null:
		_ring.visible = selected and not dead


func set_health(value: int, maximum: int = -1) -> void:
	health = value
	if maximum >= 0:
		max_health = maximum
	elif max_health < health:
		max_health = health


func get_impact_position() -> Vector2:
	return global_position + size * Vector2(0.5, 0.47)


func play_attack() -> void:
	attack_time = ATTACK_TIME
	if not _can_animate():
		return
	var sp := _speed()
	_attack_combo = clock - _last_attack_at <= COMBO_WINDOW
	_last_attack_at = clock
	match _attack_style():
		"cast": _animate_cast(sp, _attack_combo)
		"thrust": _animate_thrust(sp, _attack_combo)
		"pounce": _animate_pounce(sp, _attack_combo)
		"dive": _animate_dive(sp, _attack_combo)
		_: _animate_slash(sp, _attack_combo)


## 按武器与体型选择攻击风格；法系举杖、长矛突刺、野兽扑咬、浮空俯冲、默认挥砍。
func _attack_style() -> String:
	var weapon := str(_spec.get("weapon", "sword"))
	if weapon == "staff":
		return "cast"
	if weapon in ["spear", "bell"]:
		return "thrust"
	if weapon == "claw" or archetype == "beast":
		return "pounce"
	if weapon == "none" or archetype in ["moth", "raven", "worm", "eye"]:
		return "dive"
	return "slash"


## 从 play_attack 到命中点的实际秒数，供演出调度对齐受击时机。
func attack_impact_delay() -> float:
	var windup: float = float(ATTACK_WINDUP.get(_attack_style(), 0.20))
	if _attack_combo:
		windup *= 0.5
	return windup / _speed()


func _finish_attack(t: Tween) -> void:
	t.chain().tween_callback(func() -> void: attack_time = 0.0)


func _animate_slash(sp: float, combo: bool) -> void:
	var t := _begin_tween()
	if t == null:
		return
	var h := height
	if not combo:
		# 前摇蓄力（Anticipation & Squash）：拉开角度，压低重心蓄势
		_phase(t, 0.085 / sp, {
			"Hips": {
				"pos": Vector3(0.0, -0.026 * h, -0.055 * h),
				"rot": Vector3(-0.08, 0.20, 0.03),
				"scale": Vector3(1.04, 0.94, 1.04),
			},
			"Torso": {"rot": Vector3(-0.06, 0.34, 0.0), "scale": Vector3(1.02, 0.96, 1.02)},
			"ArmR": {"rot": Vector3(-0.68, 0.20, -0.30)},
		})
	# 爆发斩击（Strike & Stretch）：大步前跨，挥刃破空过冲
	_phase(t, 0.075 / sp, {
		"Hips": {
			"pos": Vector3(0.0, 0.016 * h, 0.155 * h),
			"rot": Vector3(0.08, -0.20, -0.04),
			"scale": Vector3(0.96, 1.05, 0.96),
		},
		"Torso": {"rot": Vector3(0.18, -0.38, 0.0), "scale": Vector3(0.97, 1.04, 0.97)},
		"ArmR": {"rot": Vector3(-1.80, -0.42, -0.42)},
		"ArmL": {"rot": Vector3(0.26, -0.22, 0.18)},
	})
	# 命中与收招过冲（Follow-through & Damping）
	_phase(t, 0.12 / sp, {
		"Hips": {
			"pos": Vector3(0.0, -0.010 * h, 0.045 * h),
			"rot": Vector3(0.02, -0.07, -0.01),
			"scale": Vector3.ONE,
		},
		"Torso": {"rot": Vector3(0.05, -0.10, 0.0), "scale": Vector3.ONE},
		"ArmR": {"rot": Vector3(0.18, 0.04, 0.05)},
		"ArmL": {"rot": Vector3(0.04, 0.0, 0.0)},
	})
	# 顺畅归位（Recovery）
	_phase(t, 0.16 / sp, {
		"Hips": {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scale": Vector3.ONE},
		"Torso": {"rot": Vector3.ZERO, "scale": Vector3.ONE},
		"ArmR": {"rot": Vector3.ZERO},
		"ArmL": {"rot": Vector3.ZERO},
	})
	_finish_attack(t)


func _animate_cast(sp: float, combo: bool) -> void:
	var t := _begin_tween()
	if t == null:
		return
	var h := height
	if not combo:
		# 施法聚能（拉起法杖、深吸聚势）
		_phase(t, 0.085 / sp, {
			"Torso": {"rot": Vector3(-0.14, 0.12, 0.0), "scale": Vector3(0.96, 1.05, 0.96)},
			"ArmR": {"rot": Vector3(-2.15, -0.18, -0.24)},
			"ArmL": {"rot": Vector3(-1.65, 0.18, 0.32)},
			"Hips": {"pos": Vector3(0.0, 0.018 * h, -0.035 * h), "rot": Vector3.ZERO, "scale": Vector3.ONE},
		})
	# 咒文掷出（下压冲击）
	_phase(t, 0.065 / sp, {
		"Torso": {"rot": Vector3(0.14, -0.10, 0.0), "scale": Vector3(1.04, 0.94, 1.04)},
		"ArmR": {"rot": Vector3(-1.30, -0.05, -0.05)},
		"ArmL": {"rot": Vector3(-1.00, 0.05, 0.16)},
		"Hips": {"pos": Vector3(0.0, -0.008 * h, 0.060 * h), "rot": Vector3(0.04, -0.06, 0.0)},
	})
	# 回旋余韵
	_phase(t, 0.12 / sp, {
		"Torso": {"rot": Vector3(0.03, -0.03, 0.0), "scale": Vector3.ONE},
		"ArmR": {"rot": Vector3(-0.35, 0.0, -0.02)},
		"ArmL": {"rot": Vector3(-0.25, 0.0, 0.05)},
		"Hips": {"pos": Vector3.ZERO, "rot": Vector3.ZERO},
	})
	# 归位
	_phase(t, 0.18 / sp, {
		"Torso": {"rot": Vector3.ZERO, "scale": Vector3.ONE},
		"ArmR": {"rot": Vector3.ZERO},
		"ArmL": {"rot": Vector3.ZERO},
	})
	_finish_attack(t)


func _animate_thrust(sp: float, combo: bool) -> void:
	var t := _begin_tween()
	if t == null:
		return
	var h := height
	if not combo:
		# 蓄力回拉
		_phase(t, 0.085 / sp, {
			"Hips": {
				"pos": Vector3(0.0, -0.016 * h, -0.065 * h),
				"rot": Vector3(0.0, 0.22, 0.0),
				"scale": Vector3(1.04, 0.95, 1.04),
			},
			"Torso": {"rot": Vector3(-0.05, 0.28, 0.0), "scale": Vector3(1.02, 0.96, 1.02)},
			"ArmR": {"rot": Vector3(0.56, 0.12, -0.28)},
			"LegR": {"rot": Vector3(0.40, 0.0, -0.06)},
		})
	# 突刺爆发
	_phase(t, 0.075 / sp, {
		"Hips": {
			"pos": Vector3(0.0, 0.010 * h, 0.120 * h),
			"rot": Vector3(0.04, -0.12, 0.0),
			"scale": Vector3(0.95, 1.06, 0.95),
		},
		"Torso": {"rot": Vector3(0.22, -0.18, 0.0), "scale": Vector3(0.96, 1.05, 0.96)},
		"ArmR": {"rot": Vector3(-1.60, -0.06, -0.12)},
		"ArmL": {"rot": Vector3(0.38, -0.32, 0.22)},
		"LegR": {"rot": Vector3(-0.25, 0.0, 0.04)},
	})
	# 缓冲
	_phase(t, 0.13 / sp, {
		"Hips": {
			"pos": Vector3(0.0, -0.004 * h, 0.03 * h),
			"rot": Vector3(0.01, 0.04, 0.0),
			"scale": Vector3.ONE,
		},
		"Torso": {"rot": Vector3(0.06, -0.05, 0.0), "scale": Vector3.ONE},
		"ArmR": {"rot": Vector3(-0.42, 0.0, -0.05)},
		"ArmL": {"rot": Vector3(0.09, -0.07, 0.05)},
		"LegR": {"rot": Vector3.ZERO},
	})
	# 归位
	_phase(t, 0.15 / sp, {
		"Hips": {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scale": Vector3.ONE},
		"Torso": {"rot": Vector3.ZERO, "scale": Vector3.ONE},
		"ArmR": {"rot": Vector3.ZERO},
		"ArmL": {"rot": Vector3.ZERO},
	})
	_finish_attack(t)


func _animate_pounce(sp: float, combo: bool) -> void:
	var t := _begin_tween()
	if t == null:
		return
	var h := height
	if not combo:
		# 蓄力下潜压缩（Anticipation & Squash）
		_phase(t, 0.075 / sp, {
			"Hips": {
				"pos": Vector3(0.0, -0.055 * h, -0.060 * h),
				"rot": Vector3(-0.06, 0.06, 0.0),
				"scale": Vector3(1.08, 0.90, 1.08),
			},
			"Torso": {"rot": Vector3(-0.12, 0.0, 0.0), "scale": Vector3(1.05, 0.92, 1.05)},
			"LegL": {"rot": Vector3(-0.50, 0.0, 0.08)},
			"LegR": {"rot": Vector3(-0.50, 0.0, -0.08)},
			"Head": {"rot": Vector3(-0.28, 0.0, 0.0)},
			"ArmL": {"rot": Vector3(0.45, 0.0, 0.22)},
			"ArmR": {"rot": Vector3(0.45, 0.0, -0.22)},
		})
	# 扑咬爆发拉伸（Pounce & Stretch）
	_phase(t, 0.075 / sp, {
		"Hips": {
			"pos": Vector3(0.0, -0.006 * h, 0.120 * h),
			"rot": Vector3(0.12, -0.04, 0.0),
			"scale": Vector3(0.95, 1.06, 0.95),
		},
		"Torso": {"rot": Vector3(0.50, -0.06, 0.0), "scale": Vector3(0.96, 1.05, 0.96)},
		"LegL": {"rot": Vector3(0.42, 0.0, -0.06)},
		"LegR": {"rot": Vector3(0.42, 0.0, 0.06)},
		"Head": {"rot": Vector3(0.34, 0.0, 0.0)},
		"ArmL": {"rot": Vector3(-0.95, 0.0, 0.38)},
		"ArmR": {"rot": Vector3(-0.95, 0.0, -0.38)},
	})
	# 扑击命中与落地缓冲（Impact & Recovery）
	_phase(t, 0.15 / sp, {
		"Hips": {
			"pos": Vector3(0.0, -0.020 * h, 0.035 * h),
			"rot": Vector3(0.02, 0.0, 0.0),
			"scale": Vector3.ONE,
		},
		"Torso": {"rot": Vector3(0.10, 0.0, 0.0), "scale": Vector3.ONE},
		"LegL": {"rot": Vector3(-0.10, 0.0, 0.0)},
		"LegR": {"rot": Vector3(-0.10, 0.0, 0.0)},
		"Head": {"rot": Vector3(0.05, 0.0, 0.0)},
		"ArmL": {"rot": Vector3(-0.25, 0.0, 0.10)},
		"ArmR": {"rot": Vector3(-0.25, 0.0, -0.10)},
	})
	_phase(t, 0.16 / sp, {
		"Hips": {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scale": Vector3.ONE},
		"Torso": {"rot": Vector3.ZERO, "scale": Vector3.ONE},
		"LegL": {"rot": Vector3.ZERO},
		"LegR": {"rot": Vector3.ZERO},
		"Head": {"rot": Vector3.ZERO},
		"ArmL": {"rot": Vector3.ZERO},
		"ArmR": {"rot": Vector3.ZERO},
	})
	_finish_attack(t)


func _animate_dive(sp: float, combo: bool) -> void:
	var t := _begin_tween()
	if t == null:
		return
	var h := height
	if not combo:
		# 俯冲蓄势拔高
		_phase(t, 0.065 / sp, {
			"Hips": {
				"pos": Vector3(0.0, 0.045 * h, -0.050 * h),
				"rot": Vector3(0.0, 0.0, 0.0),
				"scale": Vector3(0.96, 1.05, 0.96),
			},
			"Torso": {"rot": Vector3(-0.40, 0.0, 0.0)},
			"Cloak": {"rot": Vector3(0.55, 0.0, 0.0)},
		})
	# 极速掠袭
	_phase(t, 0.065 / sp, {
		"Hips": {
			"pos": Vector3(0.0, -0.060 * h, 0.110 * h),
			"rot": Vector3(0.06, 0.0, 0.0),
			"scale": Vector3(0.95, 1.08, 0.95),
		},
		"Torso": {"rot": Vector3(0.62, 0.0, 0.0)},
		"Cloak": {"rot": Vector3(-0.40, 0.0, 0.0)},
	})
	# 掠过缓冲
	_phase(t, 0.14 / sp, {
		"Hips": {
			"pos": Vector3(0.0, -0.018 * h, 0.030 * h),
			"rot": Vector3(0.01, 0.0, 0.0),
			"scale": Vector3.ONE,
		},
		"Torso": {"rot": Vector3(0.12, 0.0, 0.0)},
		"Cloak": {"rot": Vector3(0.08, 0.0, 0.0)},
	})
	# 归位
	_phase(t, 0.18 / sp, {
		"Hips": {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scale": Vector3.ONE},
		"Torso": {"rot": Vector3.ZERO},
		"Cloak": {"rot": Vector3.ZERO},
	})
	_finish_attack(t)


func play_hit(amount: int = 0, blocked: int = 0) -> void:
	hit_time = HIT_TIME
	shield_hit = blocked > 0 and amount <= 0
	if not _can_animate():
		return
	if shield_hit:
		_animate_shield_hit()
	else:
		_animate_hit(amount)


func play_guard() -> void:
	guard_time = GUARD_TIME
	if not _can_animate():
		return
	var sp := _speed()
	var t := _begin_tween()
	if t == null:
		return
	_phase(t, 0.12 / sp, {
		"Hips": {"pos": Vector3(0.0, -0.015 * height, -0.010 * height), "rot": Vector3(-0.02, 0.0, 0.0)},
		"Torso": {"rot": Vector3(0.08, -0.10, 0.0)},
		"ArmL": {"rot": Vector3(-1.40, 0.18, 0.38)},
		"ArmR": {"rot": Vector3(-0.95, -0.18, -0.22)},
	})
	_phase(t, 0.24 / sp, {
		"Hips": {"pos": Vector3.ZERO, "rot": Vector3.ZERO},
		"Torso": {"rot": Vector3.ZERO},
		"ArmL": {"rot": Vector3.ZERO},
		"ArmR": {"rot": Vector3.ZERO},
	})


func play_status_effect(key: String) -> void:
	if _effect_overlay != null:
		_effect_overlay.play_status(key)


func play_heal() -> void:
	if _effect_overlay != null:
		_effect_overlay.play_heal()


func play_death() -> void:
	dead = true
	death_time = DEATH_TIME
	if _ring != null:
		_ring.visible = false
	if _ember_particles != null:
		_ember_particles.emitting = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	if not _can_animate():
		return
	var sp := _speed()
	if _is_floaty():
		_animate_death_drift(sp)
	else:
		_animate_death_collapse(sp)


## 浮空/飞行体型：蛾、鸦、蠕虫、天眼、幽魂。
func _is_floaty() -> bool:
	return archetype in ["moth", "raven", "worm", "eye", "wraith"]


## 地面体型：向后仰倒，肢体瘫开。
func _animate_death_collapse(sp: float) -> void:
	var h := height
	var t := _begin_tween()
	if t == null:
		return
	_phase(t, 0.22 / sp, {
		"Hips": {"pos": Vector3(0.0, -0.26 * h, -0.02 * h), "rot": Vector3(0.18, 0.0, 0.04)},
		"Torso": {"rot": Vector3(0.34, 0.0, 0.06)},
		"ArmR": {"rot": Vector3(0.45, 0.20, 0.22)},
		"ArmL": {"rot": Vector3(0.36, -0.20, -0.22)},
		"LegL": {"rot": Vector3(-0.55, 0.0, 0.10)},
		"LegR": {"rot": Vector3(0.45, 0.0, -0.10)},
	})
	_phase(t, 0.20 / sp, {
		"Hips": {"pos": Vector3(0.0, -0.46 * h, -0.03 * h), "rot": Vector3(0.36, 0.0, 0.07)},
		"Torso": {"rot": Vector3(0.55, 0.0, 0.10)},
		"ArmR": {"rot": Vector3(0.90, 0.30, 0.26)},
		"ArmL": {"rot": Vector3(0.80, -0.30, -0.26)},
		"LegL": {"rot": Vector3(-0.95, 0.0, 0.15)},
		"LegR": {"rot": Vector3(0.75, 0.0, -0.15)},
	})
	_phase(t, 0.23 / sp, {
		"Hips": {"pos": Vector3(0.0, -0.52 * h, -0.03 * h), "rot": Vector3(0.46, 0.0, 0.08)},
		"Torso": {"rot": Vector3(0.62, 0.0, 0.12)},
		"ArmR": {"rot": Vector3(1.05, 0.34, 0.30)},
		"ArmL": {"rot": Vector3(0.95, -0.34, -0.30)},
		"LegL": {"rot": Vector3(-1.10, 0.0, 0.18)},
		"LegR": {"rot": Vector3(0.90, 0.0, -0.18)},
	})
	t.tween_property(self, "modulate:a", 0.32, 0.25 / sp)


## 浮空体型：坠落下沉、缓慢自旋、随光消散。
func _animate_death_drift(sp: float) -> void:
	var h := height
	var t := _begin_tween()
	if t == null:
		return
	_phase(t, 0.18 / sp, {
		"Hips": {"pos": Vector3(0.0, -0.10 * h, 0.0), "rot": Vector3(0.0, 0.42, 0.10)},
		"Torso": {"rot": Vector3(-0.35, 0.0, 0.0)},
		"ArmL": {"rot": Vector3(0.30, 0.0, -0.45)},
		"ArmR": {"rot": Vector3(0.30, 0.0, 0.45)},
		"Head": {"rot": Vector3(-0.30, 0.0, 0.0)},
		"Cloak": {"rot": Vector3(0.45, 0.0, 0.0)},
	})
	_phase(t, 0.22 / sp, {
		"Hips": {"pos": Vector3(0.0, -0.30 * h, 0.0), "rot": Vector3(0.0, 1.15, 0.22)},
		"Torso": {"rot": Vector3(-0.62, 0.0, 0.0)},
		"ArmL": {"rot": Vector3(0.55, 0.0, -0.80)},
		"ArmR": {"rot": Vector3(0.55, 0.0, 0.80)},
		"Head": {"rot": Vector3(-0.48, 0.0, 0.0)},
		"Cloak": {"rot": Vector3(0.20, 0.0, 0.0)},
	})
	_phase(t, 0.25 / sp, {
		"Hips": {"pos": Vector3(0.0, -0.44 * h, 0.0), "rot": Vector3(0.0, 1.85, 0.30)},
		"Torso": {"rot": Vector3(-0.78, 0.0, 0.0)},
		"ArmL": {"rot": Vector3(0.75, 0.0, -1.05)},
		"ArmR": {"rot": Vector3(0.75, 0.0, 1.05)},
		"Head": {"rot": Vector3(-0.55, 0.0, 0.0)},
		"Cloak": {"rot": Vector3(-0.10, 0.0, 0.0)},
	})
	t.tween_property(self, "modulate:a", 0.10, 0.30 / sp)


func get_rig() -> Node3D:
	return _rig


func is_rendering() -> bool:
	return _viewport != null


func snapshot() -> Image:
	if _viewport == null:
		return null
	var tex := _viewport.get_texture()
	if tex == null:
		return null
	return tex.get_image()


func _can_animate() -> bool:
	return _rig != null and is_inside_tree()


func _begin_tween() -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if not is_inside_tree():
		return null
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT)
	return _tween


func _speed() -> float:
	return maxf(0.25, animation_speed)


func _phase(t: Tween, dur: float, changes: Dictionary) -> void:
	t.set_parallel(true)
	for key in changes:
		var node: Node3D = _pivots.get(key, null)
		if node == null:
			continue
		var delta: Dictionary = changes[key]
		if delta.has("pos"):
			var bp: Vector3 = _base_pos.get(key, node.position)
			t.tween_property(node, "position", bp + (delta["pos"] as Vector3), dur)
		if delta.has("rot"):
			var br: Vector3 = _base_rot.get(key, node.rotation)
			t.tween_property(node, "rotation", br + (delta["rot"] as Vector3), dur)
		if delta.has("scale"):
			var bs: Vector3 = _base_scale.get(key, Vector3.ONE)
			t.tween_property(node, "scale", bs * (delta["scale"] as Vector3), dur)
	t.set_parallel(false)


func _animate_hit(amount: int) -> void:
	var sp := _speed()
	var h := height
	var punch := clampf(0.6 + float(maxi(amount, 0)) / 18.0, 0.6, 1.5)
	var t := _begin_tween()
	if t == null:
		return
	# 阶段一：受击瞬时冲击与挤压（Squash & Impact）——重心后沉、纵向挤压
	_phase(t, 0.045 / sp, {
		"Hips": {
			"pos": Vector3(0.0, -0.022 * h * punch, -0.060 * h * punch),
			"rot": Vector3(-0.12 * punch, 0.08, 0.05),
			"scale": Vector3(1.08, 0.88, 1.08),
		},
		"Torso": {
			"rot": Vector3(-0.32 * punch, 0.14, 0.08),
			"scale": Vector3(1.05, 0.90, 1.05),
		},
		"ArmR": {"rot": Vector3(0.36, 0.18, 0.20)},
		"ArmL": {"rot": Vector3(0.32, -0.18, -0.20)},
	})
	# 阶段二：受击过冲与拉伸（Stretch & Rebound）——后仰拉伸
	_phase(t, 0.14 / sp, {
		"Hips": {
			"pos": Vector3(0.0, 0.010 * h * punch, -0.018 * h),
			"rot": Vector3(-0.04, 0.02, 0.01),
			"scale": Vector3(0.96, 1.06, 0.96),
		},
		"Torso": {
			"rot": Vector3(-0.10, 0.04, 0.02),
			"scale": Vector3(0.97, 1.04, 0.97),
		},
		"ArmR": {"rot": Vector3(0.12, 0.06, 0.06)},
		"ArmL": {"rot": Vector3(0.10, -0.06, -0.06)},
	})
	# 阶段三：阻尼复位（Recovery）——平滑回到初始标准比例与站位
	_phase(t, 0.16 / sp, {
		"Hips": {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scale": Vector3.ONE},
		"Torso": {"rot": Vector3.ZERO, "scale": Vector3.ONE},
		"ArmR": {"rot": Vector3.ZERO},
		"ArmL": {"rot": Vector3.ZERO},
	})
	# 震颤顿挫（Hit-shake）：高频 X 轴微抖动强化受击感
	if _rig != null and is_inside_tree():
		var base_rig_x: float = _rig.position.x
		var shake_w: float = 0.016 * h * punch
		var st := create_tween()
		st.tween_property(_rig, "position:x", base_rig_x + shake_w, 0.02 / sp)
		st.tween_property(_rig, "position:x", base_rig_x - shake_w * 0.7, 0.025 / sp)
		st.tween_property(_rig, "position:x", base_rig_x + shake_w * 0.35, 0.025 / sp)
		st.tween_property(_rig, "position:x", base_rig_x, 0.03 / sp)
	_flash_once(Color(1.0, 0.32, 0.28), 0.22 / sp)


func _animate_shield_hit() -> void:
	var sp := _speed()
	var t := _begin_tween()
	if t == null:
		return
	var h := height
	# 阶段一：盾牌格挡硬直压缩
	_phase(t, 0.05 / sp, {
		"Hips": {
			"pos": Vector3(0.0, -0.012 * h, -0.025 * h),
			"rot": Vector3(0.02, -0.04, 0.02),
			"scale": Vector3(1.04, 0.94, 1.04),
		},
		"Torso": {
			"rot": Vector3(-0.10, -0.12, 0.02),
			"scale": Vector3(1.03, 0.95, 1.03),
		},
		"ArmL": {"rot": Vector3(-1.25, 0.12, 0.35)},
		"ArmR": {"rot": Vector3(-0.35, -0.12, -0.12)},
	})
	# 阶段二：挺身顶住
	_phase(t, 0.14 / sp, {
		"Hips": {
			"pos": Vector3(0.0, 0.0, -0.008 * h),
			"rot": Vector3(0.01, -0.01, 0.0),
			"scale": Vector3(0.98, 1.02, 0.98),
		},
		"Torso": {
			"rot": Vector3(-0.03, -0.04, 0.0),
			"scale": Vector3.ONE,
		},
		"ArmL": {"rot": Vector3(-0.35, 0.03, 0.10)},
		"ArmR": {"rot": Vector3(-0.10, -0.03, -0.03)},
	})
	# 阶段三：归位
	_phase(t, 0.15 / sp, {
		"Hips": {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scale": Vector3.ONE},
		"Torso": {"rot": Vector3.ZERO, "scale": Vector3.ONE},
		"ArmL": {"rot": Vector3.ZERO},
		"ArmR": {"rot": Vector3.ZERO},
	})
	if _rig != null and is_inside_tree():
		var base_rig_x: float = _rig.position.x
		var shake_w: float = 0.009 * h
		var st := create_tween()
		st.tween_property(_rig, "position:x", base_rig_x - shake_w, 0.02 / sp)
		st.tween_property(_rig, "position:x", base_rig_x + shake_w * 0.5, 0.025 / sp)
		st.tween_property(_rig, "position:x", base_rig_x, 0.03 / sp)
	_flash_once(Color(0.65, 0.88, 1.0), 0.20 / sp)


func _flash_once(tint: Color, duration: float) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
		_flash_tween = null
	_flash_tint = Color.WHITE
	_apply_flash(1.0)
	if not is_inside_tree():
		return
	var sp := _speed()
	var white_time := 0.03 / sp
	var fade_time := maxf(0.08, duration - white_time)
	_flash_tween = create_tween()
	_flash_tween.tween_interval(white_time)
	_flash_tween.tween_callback(func() -> void: _flash_tint = tint)
	_flash_tween.tween_method(_apply_flash, 1.0, 0.0, fade_time)


func _apply_flash(value: float) -> void:
	_flash = clampf(value, 0.0, 1.0)
	for entry in _flash_mats:
		var mat: StandardMaterial3D = entry[0]
		if mat == null:
			continue
		var base_color: Color = entry[1]
		# 受击闪白保留轮廓：只压到 0.62，配合较弱的自发光，避免整个人被烧成白色剪影。
		mat.albedo_color = base_color.lerp(_flash_tint, _flash * 0.62)
		if bool(entry[2]):
			mat.emission_energy_multiplier = float(entry[3]) + _flash * 1.4


func _ensure_stage() -> void:
	# 幂等：main 会复用同一个 ActorView 实例反复 setup。
	# 已经建好的舞台（含 headless 骨架）直接复用，不能再把 ActorStage 加到第二个父节点。
	if _stage_ready or (_world_root != null and is_instance_valid(_world_root)):
		return
	_stage_ready = true
	_world_root = Node3D.new()
	_world_root.name = "ActorStage"
	if _is_headless():
		# headless 不建 GPU 舞台，但仍保留一个普通 Node3D 作为 rig 的父节点。
		add_child(_world_root)
		_create_effect_overlay()
		return
	_viewport = SubViewport.new()
	_viewport.name = "ActorViewport"
	_viewport.size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	# ActorStage 只挂在 SubViewport 下；之前先 add_child(self) 再转挂会触发
	# "already has a parent" 报错（capture_ui 每张截图都刷一行）。
	_viewport.add_child(_world_root)
	_build_environment()
	_build_lights()
	_build_shadow()
	_build_ring()
	_build_glow()
	_build_particles()
	_camera = Camera3D.new()
	_camera.name = "ActorCamera"
	_camera.fov = CAMERA_FOV
	_camera.near = 0.05
	_camera.far = 40.0
	_world_root.add_child(_camera)
	_camera.current = true
	_texture_rect = TextureRect.new()
	_texture_rect.name = "ActorFrame"
	_texture_rect.texture = _viewport.get_texture()
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_texture_rect)
	move_child(_texture_rect, 0)
	_create_effect_overlay()


func _create_effect_overlay() -> void:
	if _effect_overlay != null:
		return
	_effect_overlay = StatusFxOverlay.new()
	_effect_overlay.name = "StatusFxOverlay"
	_effect_overlay.reduced_motion = reduced_motion
	add_child(_effect_overlay)


func _build_environment() -> void:
	# 环境光只负责让暗部不至于死黑：能量抬到 0.30，冷蓝底给暗部一点空气感，
	# 但主体亮度仍由主光/轮廓光决定，避免低模被环境光洗成没有朝向的白模。
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.34, 0.43)
	env.ambient_light_energy = 0.30
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.97
	# 白点抬到 1.30：银甲/骨白这类高反照率材质的高光进 HDR 肩部滚降，
	# 不再在实战小尺寸下糊成一整块过曝的白色平板。
	env.tonemap_white = 1.30
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.06
	# 开启轻微 Glow/Bloom，让武器符文、眼瞳与余烬自发光呈现自然微晕
	env.glow_enabled = true
	env.glow_intensity = 0.50
	env.glow_bloom = 0.10
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_world_env = WorldEnvironment.new()
	_world_env.name = "ActorWorldEnv"
	_world_env.environment = env
	_world_root.add_child(_world_env)


func _build_lights() -> void:
	# 三点光按「一主一补一轮廓」分配亮度：主光决定体积，补光只抬暗部，
	# 冷色轮廓光从背后勾边。三盏同时给高能量会把暗色调角色洗成白模。
	_key_light = DirectionalLight3D.new()
	_key_light.name = "KeyLight"
	# 主光左上前 40°：略偏侧比正打更能在低模平面上拉出明暗交界，胸甲不再是平涂。
	_key_light.rotation_degrees = Vector3(-44.0, -36.0, 0.0)
	_key_light.light_color = Color(1.0, 0.93, 0.84)
	_key_light.light_energy = 1.42
	_key_light.shadow_enabled = true
	_key_light.shadow_blur = 2.0
	_key_light.directional_shadow_max_distance = 10.0
	_world_root.add_child(_key_light)
	_fill_light = DirectionalLight3D.new()
	_fill_light.name = "FillLight"
	_fill_light.rotation_degrees = Vector3(-14.0, 122.0, 0.0)
	_fill_light.light_color = Color(0.40, 0.56, 0.80)
	_fill_light.light_energy = 0.34
	_world_root.add_child(_fill_light)
	_rim_light = DirectionalLight3D.new()
	_rim_light.name = "RimLight"
	_rim_light.rotation_degrees = Vector3(-26.0, 158.0, 0.0)
	_rim_light.light_color = Color(0.58, 0.82, 1.0)
	_rim_light.light_energy = 1.55
	_world_root.add_child(_rim_light)
	# 暖轮廓（背左低角）：冷边勾右侧、暖边勾左侧，两侧都有一道亮边，
	# 角色在近黑面板上才不会被读成一团剪影。
	_warm_rim = DirectionalLight3D.new()
	_warm_rim.name = "WarmRimLight"
	_warm_rim.rotation_degrees = Vector3(-16.0, -142.0, 0.0)
	_warm_rim.light_color = Color(1.0, 0.70, 0.42)
	_warm_rim.light_energy = 0.62
	_world_root.add_child(_warm_rim)
	# 地面反弹：从下往上极弱暖光，把腿甲/披风下摆从死黑里捞回来。
	_bounce_light = DirectionalLight3D.new()
	_bounce_light.name = "GroundBounce"
	_bounce_light.rotation_degrees = Vector3(-104.0, 24.0, 0.0)
	_bounce_light.light_color = Color(0.52, 0.58, 0.68)
	_bounce_light.light_energy = 0.18
	_world_root.add_child(_bounce_light)


static var _soft_dot_cache: GradientTexture2D = null


## 柔边圆点（64px）：余烬粒子共用，避免每帧新建贴图。
func _soft_dot_texture() -> GradientTexture2D:
	if _soft_dot_cache != null:
		return _soft_dot_cache
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.add_point(0.35, Color(1.0, 1.0, 1.0, 0.85))
	grad.add_point(0.72, Color(1.0, 1.0, 1.0, 0.16))
	grad.set_color(grad.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_soft_dot_cache = tex
	return _soft_dot_cache


func _build_particles() -> void:
	if _is_headless():
		return
	if _ember_particles != null and is_instance_valid(_ember_particles):
		return
	_ember_particles = CPUParticles3D.new()
	_ember_particles.name = "EmberParticles"
	_ember_particles.amount = 14
	_ember_particles.lifetime = 2.4
	_ember_particles.preprocess = 1.0
	_ember_particles.speed_scale = 0.8
	_ember_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_ember_particles.emission_box_extents = Vector3(0.35 * height, 0.06, 0.35 * height)
	_ember_particles.position = Vector3(0.0, 0.04, 0.0)
	_ember_particles.direction = Vector3(0.08, 1.0, 0.0)
	_ember_particles.spread = 22.0
	_ember_particles.gravity = Vector3(0.0, 0.15, 0.0)
	_ember_particles.initial_velocity_min = 0.14
	_ember_particles.initial_velocity_max = 0.32
	_ember_particles.scale_amount_min = 0.6
	_ember_particles.scale_amount_max = 1.2
	_ember_particles.color = Color(1.0, 0.82, 0.52, 0.70)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.022 * height, 0.022 * height)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	# 程序化柔边圆点：原来的方形贴片在实战尺寸下会被读成「坏点/噪点」，
	# 换成径向渐隐的圆点后余烬才像飘起来的火星。
	mat.albedo_texture = _soft_dot_texture()
	quad.material = mat
	_ember_particles.mesh = quad
	_ember_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root.add_child(_ember_particles)


func _build_shadow() -> void:
	# 接地阴影分两层：内圈压住脚底，外圈软过渡，角色才不会浮在面板上。
	# PlaneMesh 天然朝 +Y，省掉 QuadMesh 旋转后朝向不确定的问题。
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	var grad := Gradient.new()
	# 内圈更实、外圈收得更快：脚底有一块明确的暗，远处才渐隐，
	# 接地感来自「接触」而不是一整块灰色椭圆。
	grad.set_color(0, Color(0.0, 0.0, 0.0, 1.0))
	grad.add_point(0.22, Color(0.0, 0.0, 0.0, 0.82))
	grad.add_point(0.44, Color(0.0, 0.0, 0.0, 0.42))
	grad.set_color(grad.get_point_count() - 1, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = tex
	_shadow = MeshInstance3D.new()
	_shadow.name = "ContactShadow"
	_shadow.mesh = quad
	_shadow.material_override = mat
	_shadow.position = Vector3(0.0, 0.004, 0.0)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root.add_child(_shadow)


func _build_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.255
	torus.outer_radius = 0.300
	torus.rings = 36
	torus.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = accent
	mat.emission_enabled = true
	mat.emission = accent
	mat.emission_energy_multiplier = 1.8
	_ring = MeshInstance3D.new()
	_ring.name = "SelectionRing"
	_ring.mesh = torus
	_ring.material_override = mat
	_ring.position = Vector3(0.0, 0.012, 0.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	_world_root.add_child(_ring)


func _build_glow() -> void:
	# 角色背后一块柔和舞台辉光：把人物从近黑面板上托起来，
	# 同时用旅者/敌人的主题色勾出轮廓，不引入任何外部贴图。
	var grad := Gradient.new()
	# 辉光只做「背景提亮」不抢主体：中心 0.68 已足够把人物从近黑面板上托起来，
	# 再高会在角色腰侧糊出一圈明显的主题色光斑。
	grad.set_color(0, Color(1.0, 1.0, 1.0, 0.68))
	grad.add_point(0.45, Color(1.0, 1.0, 1.0, 0.26))
	grad.set_color(grad.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_glow = Sprite3D.new()
	_glow.name = "StageGlow"
	_glow.texture = tex
	_glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glow.shaded = false
	_glow.transparent = true
	_glow.pixel_size = 0.01
	_glow.render_priority = -1
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root.add_child(_glow)


func _build_rig() -> void:
	if _world_root == null:
		return
	if _rig != null and is_instance_valid(_rig):
		if _rig.get_parent() != null:
			_rig.get_parent().remove_child(_rig)
		_rig.queue_free()
	_rig = null
	_pivots.clear()
	_base_pos.clear()
	_base_rot.clear()
	_base_scale.clear()
	_flash_mats.clear()
	if _spec.is_empty():
		return
	var rig: Node3D = ActorRig.build(_spec)
	if rig == null:
		return
	rig.name = "ActorRig"
	rig.rotation.y = deg_to_rad(PLAYER_YAW if player else ENEMY_YAW)
	_world_root.add_child(rig)
	_rig = rig
	for key in ["Idle", "Hips", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR", "Cloak", "WeaponMount"]:
		var node: Node3D = rig.find_child(key, true, false)
		if node != null:
			_pivots[key] = node
			_base_pos[key] = node.position
			_base_rot[key] = node.rotation
			_base_scale[key] = node.scale
	_collect_materials(rig)
	if _ring != null:
		var ring_mat: StandardMaterial3D = _ring.material_override
		if ring_mat != null:
			ring_mat.albedo_color = accent
			ring_mat.emission = accent
	if _ember_particles != null:
		_ember_particles.emitting = not dead
	if _texture_rect != null:
		_texture_rect.texture = _viewport.get_texture()


func _collect_materials(rig: Node3D) -> void:
	var seen := {}
	var stack: Array[Node] = [rig]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not node is MeshInstance3D:
			continue
		var mesh_inst := node as MeshInstance3D
		var mat := mesh_inst.material_override
		if mat == null and mesh_inst.mesh != null and mesh_inst.mesh.get_surface_count() > 0:
			mat = mesh_inst.mesh.surface_get_material(0)
		if mat is StandardMaterial3D and not seen.has(mat):
			seen[mat] = true
			_flash_mats.append([mat, mat.albedo_color, mat.emission_enabled, mat.emission_energy_multiplier])


func _frame_camera() -> void:
	if _camera == null:
		return
	var ext := height
	var center_y := height * 0.5
	if _rig != null and _rig.has_meta("bounds"):
		var bounds: AABB = _rig.get_meta("bounds")
		if bounds.size.y > 0.05:
			center_y = bounds.position.y + bounds.size.y * 0.5
			# 按真实包围盒取景：悬浮/钟形等特殊体型也能占满画幅。
			ext = maxf(bounds.size.y, maxf(bounds.size.x * 1.18, bounds.size.z * 1.18))
			ext *= 1.04
	# 留白从 10% 收到 6%：实战面板里角色再大一点点，正面细节才看得出来。
	var half := ext * 0.5 * 1.06
	var dist := half / tan(deg_to_rad(_camera.fov * 0.5))
	var direction := Vector3(0.33, 0.17, 1.0).normalized()
	var focus := Vector3(0.0, center_y, 0.0)
	_camera.position = focus + direction * dist
	_camera.look_at(focus, Vector3.UP)
	if _shadow != null:
		_shadow.position = Vector3(0.0, 0.006, 0.0)
		_shadow.scale = Vector3(maxf(0.60, 0.50 * height), maxf(0.46, 0.38 * height), 1.0)
	if _ring != null:
		_ring.scale = Vector3(height, 1.0, height)
	if _glow != null:
		# 沿相机轴线往人物后方放，光晕在屏幕上正好居中，不会被斜视角推到右侧。
		_glow.position = focus - direction * (height * 0.80)
		_glow.scale = Vector3.ONE * (height * 1.62)
		_glow.modulate = Color(accent.r, accent.g, accent.b, 1.0)
	if _ember_particles != null:
		_ember_particles.emission_box_extents = Vector3(maxf(0.20, 0.30 * height), 0.05, maxf(0.20, 0.30 * height))
		_ember_particles.position = Vector3(0.0, 0.04, 0.0)
		_ember_particles.color = accent.lightened(0.25).lerp(Color(1.0, 0.82, 0.50), 0.5)


func _process(delta: float) -> void:
	if _rig == null or _world_root == null:
		return
	# 视口可见性与休眠优化：当视口不可见时暂停更新，显著降低多角色并发渲染负担
	if not is_visible_in_tree():
		if _viewport != null and _viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	elif _viewport != null and _viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	if _tween != null and not _tween.is_valid():
		_tween = null
	if held:
		return
	if not reduced_motion:
		clock += delta * 1.0
	_pose_idle()
	if _ring != null and _ring.visible:
		var pulse := 0.0 if reduced_motion else sin(clock * 2.4) * 0.030
		_ring.scale = Vector3(height, 1.0, height) * (1.0 + pulse)


func _pose_idle() -> void:
	var amp := 0.0 if reduced_motion else 1.0
	var phase := float(idle_seed % 360) * 0.0174
	# 攻击动作期间由 tween 接管 Head/Cloak（扑咬低头、俯冲收翅），待机姿态不再覆盖。
	var busy_attacking := attack_time > 0.0
	var busy_hit := hit_time > 0.0 or guard_time > 0.0
	var idle: Node3D = _pivots.get("Idle", null)
	if idle != null:
		var ip: Vector3 = _base_pos.get("Idle", idle.position)
		var ir: Vector3 = _base_rot.get("Idle", idle.rotation)
		if dead:
			idle.position = ip
			idle.rotation = ir
		else:
			idle.position = ip + Vector3(0.0, sin(clock * 1.9 + phase) * 0.007 * height * amp, 0.0)
			idle.rotation = ir + Vector3(0.0, 0.0, sin(clock * 1.05 + phase) * 0.010 * amp)
	
	# 胸腔自然起伏（Torso Breathing）
	var torso: Node3D = _pivots.get("Torso", null)
	if torso != null and not busy_attacking and not busy_hit:
		var ts: Vector3 = _base_scale.get("Torso", Vector3.ONE)
		if dead:
			torso.scale = ts
		else:
			var breath := sin(clock * 1.9 + phase) * 0.010 * amp
			torso.scale = ts * Vector3(1.0 + breath * 0.7, 1.0 + breath, 1.0 + breath * 0.7)

	var head: Node3D = _pivots.get("Head", null)
	if head != null and not busy_attacking and not busy_hit:
		var hp: Vector3 = _base_pos.get("Head", head.position)
		var hr: Vector3 = _base_rot.get("Head", head.rotation)
		if dead:
			head.position = hp
			head.rotation = hr + Vector3(0.10, 0.0, 0.06)
		else:
			head.rotation = hr + Vector3(sin(clock * 1.2 + phase) * 0.045 * amp, sin(clock * 0.63 + phase) * 0.14 * amp, 0.0)

	var cloak: Node3D = _pivots.get("Cloak", null)
	if cloak != null and not busy_attacking and not busy_hit:
		var cr: Vector3 = _base_rot.get("Cloak", cloak.rotation)
		if dead:
			# 倒地/坠落后披风随之静止，不再保持漂浮摆动。
			cloak.rotation = cr
		else:
			var flutter := sin(clock * 3.6 + phase) * 0.010 * amp
			cloak.rotation = cr + Vector3((sin(clock * 1.55 + phase) * 0.028 + flutter) * amp, 0.0, sin(clock * 0.9 + phase) * 0.016 * amp)

	# 武器与右手二级惯性微动（Secondary Motion）
	var mount: Node3D = _pivots.get("WeaponMount", null)
	if mount != null and not busy_attacking and not busy_hit:
		var mr: Vector3 = _base_rot.get("WeaponMount", mount.rotation)
		if dead:
			mount.rotation = mr
		else:
			mount.rotation = mr + Vector3(sin(clock * 1.9 + phase - 0.42) * 0.020 * amp, 0.0, cos(clock * 1.2 + phase) * 0.012 * amp)


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _to_color(value: String, fallback: Color) -> Color:
	if value.is_empty():
		return fallback
	if not value.begins_with("#"):
		value = "#" + value
	if not Color.html_is_valid(value):
		return fallback
	return Color.html(value)
