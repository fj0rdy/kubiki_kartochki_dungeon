class_name FloatingText
extends Label
## Цифра урона, которая всплывает и тает. Мелочь, но именно она превращает
## «изменилось число в таблице» в «попал».

static func spawn(parent: Control, text: String, color: Color, at: Vector2, size: int = 32) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var l := FloatingText.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = at
	l.modulate.a = 0.0
	parent.add_child(l)

	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "modulate:a", 1.0, 0.10)
	t.tween_property(l, "position:y", at.y - 46, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(l, "modulate:a", 0.0, 0.45)
	t.chain().tween_callback(l.queue_free)

## Тряска любого контрола — вешается на арену при попадании.
static func shake(node: Control, strength: float = 6.0, time: float = 0.32) -> void:
	if node == null or not is_instance_valid(node):
		return
	var origin := node.position
	var t := node.create_tween()
	var steps := 6
	for i in steps:
		var dx := strength * (1.0 - float(i) / steps) * (1 if i % 2 == 0 else -1)
		t.tween_property(node, "position:x", origin.x + dx, time / steps)
	t.tween_property(node, "position:x", origin.x, time / steps)
