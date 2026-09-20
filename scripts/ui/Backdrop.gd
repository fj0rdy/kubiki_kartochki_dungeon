class_name Backdrop
extends Control
## Задник: камень, свет свечи из левого верхнего угла и виньетка по краям.
##
## Плоская заливка фона — главная причина, по которой игра выглядит
## неготовой: у сцены нет ни глубины, ни источника света, и всё, что на ней
## лежит, кажется наклейками. Здесь три слоя, все считаются кодом:
## текстура камня, тёплое пятно света и затемнение к краям. Виньетка заодно
## работает на читаемость — взгляд сам собирается к центру экрана.

const CANDLE_STRENGTH := 0.10
const VIGNETTE_STRENGTH := 0.55

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var base := ColorRect.new()
	base.color = Palette.GROUND
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	var stone := TextureRect.new()
	stone.texture = Paper.hide(Palette.GROUND.lightened(0.06), Vector2i(192, 192), 11)
	stone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stone.stretch_mode = TextureRect.STRETCH_SCALE
	stone.set_anchors_preset(Control.PRESET_FULL_RECT)
	stone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stone.modulate = Color(1, 1, 1, 0.75)
	add_child(stone)

	add_child(_radial(Palette.CANDLE, CANDLE_STRENGTH, Vector2(0.12, 0.05), 0.85, false))
	add_child(_radial(Color("07050a"), VIGNETTE_STRENGTH, Vector2(0.5, 0.5), 0.78, true))

## Круглое пятно. inverted — прозрачное в центре и плотное по краям (виньетка),
## иначе наоборот (свет).
func _radial(color: Color, strength: float, center: Vector2, radius: float, inverted: bool) -> TextureRect:
	var grad := Gradient.new()
	if inverted:
		grad.set_color(0, Color(color, 0.0))
		grad.set_color(1, Color(color, strength))
		grad.add_point(0.55, Color(color, 0.0))
	else:
		grad.set_color(0, Color(color, strength))
		grad.set_color(1, Color(color, 0.0))

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = center
	tex.fill_to = center + Vector2(radius, 0)
	tex.width = 512
	tex.height = 512

	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
