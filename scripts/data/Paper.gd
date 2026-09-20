class_name Paper
extends RefCounted
## Бумага, кожа и камень — генерируются кодом, файлов не нужно.
##
## Плоская заливка выдаёт прототип сильнее всего остального: настоящая
## поверхность всегда неровная. Здесь шум подмешивается в яркость базового
## цвета, края притемняются, а на бумагу добавляются волокна. Всё считается
## один раз при первом обращении и лежит в кэше.
##
## Текстуры вставляются как StyleBoxTexture с полями по краям (9-patch):
## углы и края не тянутся, растягивается только середина, поэтому
## притемнение по периметру остаётся ровным при любом размере панели.

static var _cache: Dictionary = {}

## Лист пергамента: светлый, с волокнами и потемневшими краями.
static func parchment(base: Color = Palette.PARCHMENT, size: Vector2i = Vector2i(128, 160), seed_value: int = 7, border: Color = Color(0, 0, 0, 0)) -> ImageTexture:
	var key := "parch:%s:%s:%d:%s" % [base.to_html(), size, seed_value, border.to_html()]
	if _cache.has(key):
		return _cache[key]

	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var blotch := FastNoiseLite.new()
	blotch.seed = seed_value
	blotch.noise_type = FastNoiseLite.TYPE_SIMPLEX
	blotch.frequency = 0.018
	blotch.fractal_octaves = 4

	var fibre := FastNoiseLite.new()
	fibre.seed = seed_value + 31
	fibre.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fibre.frequency = 0.5
	fibre.fractal_octaves = 1

	var edge := 9.0
	for y in size.y:
		for x in size.x:
			# крупные пятна выделки
			var v := 1.0 + blotch.get_noise_2d(x, y) * 0.075
			# волокна: шум, сильно растянутый по горизонтали
			v += fibre.get_noise_2d(x * 0.25, y * 3.0) * 0.022
			# края листа темнее — бумага лежит, а не парит
			var dx: float = min(float(x), float(size.x - 1 - x))
			var dy: float = min(float(y), float(size.y - 1 - y))
			var d: float = min(dx, dy)
			if d < edge:
				v -= (1.0 - d / edge) * 0.16
			img.set_pixel(x, y, Color(base.r * v, base.g * v, base.b * v, 1.0))

	_frame(img, border)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Кожа и камень: то же самое, но грубее и темнее — для панелей интерфейса.
static func hide(base: Color = Palette.PANEL, size: Vector2i = Vector2i(96, 96), seed_value: int = 3, border: Color = Color(0, 0, 0, 0)) -> ImageTexture:
	var key := "hide:%s:%s:%d:%s" % [base.to_html(), size, seed_value, border.to_html()]
	if _cache.has(key):
		return _cache[key]

	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var grain := FastNoiseLite.new()
	grain.seed = seed_value
	grain.noise_type = FastNoiseLite.TYPE_CELLULAR
	grain.frequency = 0.09
	grain.fractal_octaves = 2

	var wide := FastNoiseLite.new()
	wide.seed = seed_value + 17
	wide.frequency = 0.02

	for y in size.y:
		for x in size.x:
			var v := 1.0 + grain.get_noise_2d(x, y) * 0.10 + wide.get_noise_2d(x, y) * 0.13
			# лёгкий верхний свет: панель выпуклая, а не наклейка
			v += (1.0 - float(y) / float(size.y)) * 0.05
			img.set_pixel(x, y, Color(base.r * v, base.g * v, base.b * v, 1.0))

	_frame(img, border)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Рамка запекается прямо в картинку: у StyleBoxTexture своей рамки нет,
## а поля 9-patch не тянутся — значит, нарисованный по краю пиксель останется
## ровно на краю панели любого размера. Сверху линия светлее, снизу темнее:
## так край читается как тиснение, а не как обводка.
static func _frame(img: Image, border: Color) -> void:
	if border.a <= 0.0:
		return
	var w := img.get_width()
	var h := img.get_height()
	var light := border.lightened(0.30)
	var dark := border.darkened(0.45)
	for x in w:
		img.set_pixel(x, 0, border)
		img.set_pixel(x, h - 1, border)
		if h > 3:
			img.set_pixel(x, 1, img.get_pixel(x, 1).lerp(light, 0.45))
			img.set_pixel(x, h - 2, img.get_pixel(x, h - 2).lerp(dark, 0.45))
	for y in h:
		img.set_pixel(0, y, border)
		img.set_pixel(w - 1, y, border)
		if w > 3:
			img.set_pixel(1, y, img.get_pixel(1, y).lerp(light, 0.30))
			img.set_pixel(w - 2, y, img.get_pixel(w - 2, y).lerp(dark, 0.30))

## Панель из текстуры. Поля не тянутся, так что рамка не расплывается.
static func box(tex: Texture2D, pad: int = 12, margin: int = 8) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(margin)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb

## Тиснёная рамка поверх текстуры: светлая линия сверху, тёмная снизу —
## так край читается как вдавленный в материал, а не нарисованный на нём.
static func emboss(node: CanvasItem, rect: Rect2, edge: Color, depth: float = 0.35) -> void:
	var light := Color(edge.lightened(0.35), 0.55 * depth + 0.35)
	var dark := Color(Color.BLACK, 0.35)
	node.draw_rect(rect, edge, false, 1.0)
	node.draw_line(rect.position + Vector2(1, 1), rect.position + Vector2(rect.size.x - 1, 1), light, 1.0)
	node.draw_line(rect.position + Vector2(1, rect.size.y - 1),
		rect.position + Vector2(rect.size.x - 1, rect.size.y - 1), dark, 1.0)
