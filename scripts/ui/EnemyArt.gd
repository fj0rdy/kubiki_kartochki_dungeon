class_name EnemyArt
extends Control
## Фигура существа. Рисунки лежат в assets/art/*.svg — это векторные файлы,
## Godot растеризует их при импорте, поэтому они не мылятся при масштабировании.
##
## Раньше здесь были силуэты из многоугольников прямо в коде. Они читались как
## пятна: набором точек не нарисуешь ни капюшон, ни челюсть. Вектор решает это
## и остаётся таким же «бесплатным» — файлы текстовые, рисуются руками, весят
## килобайты.
##
## Узел отвечает за жизнь фигуры: дыхание, вздрагивание от удара, тень под
## ногами. Экран боя дёргает только set_art() и hit(), поэтому подменить
## рисунок на нарисованный художником спрайт можно будет одной строкой.

## Фигуры были мелкими: бой смотрится в них, а они занимали меньше места,
## чем список приёмов рядом. После переноса приёмов в подсказку место
## освободилось — отдаём его бойцам.
const SIZE := Vector2(168, 168)

## Имя файла в assets/art. Совпадает с полем "art" в enemies.json.
const KNOWN := ["scavenger", "chanter", "warden", "knight", "bonekeeper",
	"maw", "weaver", "hollow", "queen", "seeker"]

var art_id: String = "scavenger"
var tint: Color = Palette.BLOOD

var _tex: Texture2D
var _phase: float = 0.0
var _hit_flash: float = 0.0

func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	if _tex == null:
		_load_art(art_id)

func set_art(id: String, color: Color = Palette.BLOOD) -> void:
	art_id = id if KNOWN.has(id) else "scavenger"
	tint = color
	_load_art(art_id)
	queue_redraw()

func _load_art(id: String) -> void:
	var path := "res://assets/art/%s.svg" % id
	_tex = load(path) if ResourceLoader.exists(path) else null

func hit() -> void:
	_hit_flash = 1.0
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.06, 0.95), 0.07)
	t.tween_property(self, "scale", Vector2.ONE, 0.16)

func _process(delta: float) -> void:
	_phase += delta
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 3.2)
	queue_redraw()

func _draw() -> void:
	var box := size
	if box.x < 4.0 or box.y < 4.0:
		box = SIZE
	# дыхание: фигура едва заметно оседает и поднимается
	var breathe := sin(_phase * 1.4) * 2.0

	# тень под ногами — эллипс, а не круг: лежит на полу, а не висит
	draw_set_transform(Vector2(box.x * 0.5, box.y - 8.0), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, box.x * 0.30, Color(0, 0, 0, 0.38))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _tex == null:
		return
	var tex_size := Vector2(_tex.get_size())
	var scale_factor: float = min(box.x / tex_size.x, (box.y - 10.0) / tex_size.y)
	var draw_size := tex_size * scale_factor
	var pos := Vector2((box.x - draw_size.x) * 0.5, box.y - 8.0 - draw_size.y + breathe)

	# вспышка при попадании: фигура на кадр становится цвета свечи
	var modulate_color := Color.WHITE
	if _hit_flash > 0.0:
		modulate_color = Color.WHITE.lerp(Color(1.9, 1.4, 1.0), _hit_flash)
	draw_texture_rect(_tex, Rect2(pos, draw_size), false, modulate_color)
