extends Control
## Subtle deterministic ash; no gameplay RNG and no mouse interception.
var time := 0.0
var reduced := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.32, 0.65, 1.0])
	gradient.colors = PackedColorArray([Color(0.012, 0.017, 0.016, 0.82), Color(0.012, 0.017, 0.016, 0.52), Color(0.012, 0.017, 0.016, 0.06), Color(0.012, 0.017, 0.016, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1024
	texture.height = 1
	var falloff := TextureRect.new()
	falloff.texture = texture
	falloff.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	falloff.mouse_filter = Control.MOUSE_FILTER_IGNORE
	falloff.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(falloff)

func _process(delta: float) -> void:
	if visible and not reduced:
		time += delta
		queue_redraw()

func _draw() -> void:
	for i in range(42):
		var x := fposmod(float(i * 137) + sin(time * 0.14 + i) * 25, maxf(size.x, 1))
		var y := fposmod(float(i * 89) - time * (5 + i % 7), maxf(size.y, 1))
		var alpha := 0.15 + 0.22 * (0.5 + 0.5 * sin(time + i))
		draw_circle(Vector2(x, y), 1.0 + float(i % 3) * 0.5, Color(0.9, 0.65, 0.32, alpha))
