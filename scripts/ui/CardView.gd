class_name CardView
extends Control
## Карта в раскладке Hearthstone: рамка, окно с рисунком, лента с именем,
## поле правил и лента созвучия внизу.
##
## Почему так, а не листом пергамента, как было раньше. Карта — единственный
## предмет, который игрок читает каждый ход, и читать её надо с одного
## взгляда, по местам: имя всегда там, цена всегда там, стихия всегда там.
## Пергамент со сплошным текстом заставлял каждый раз вчитываться заново.
##
## Всё рисуется кодом в _draw(), а не собирается из узлов. Причина простая:
## лента с вырезанными концами, фаска по краю и алмазы сбоку — это
## многоугольники, а не прямоугольники, и контейнерами их не выложить.
##
## ПРАВИЛО ТЕКСТА: он обязан помещаться. Кегль подбирается измерением, а не
## на глаз (см. _fit_size), поэтому длинная карта просто набирается мельче,
## и ни одна строка никогда не вылезает за рамку.

signal clicked(card_id: String)

const SIZE := Vector2(158, 224)

## Геометрия карты. Все числа в её собственных координатах — от них же
## считаются положения детей, чтобы рисунок и текст не разъезжались.
const ART_RECT := Rect2(16, 20, 126, 88)
const NAME_BAND := Rect2(2, 106, 154, 29)
const TEXT_RECT := Rect2(19, 146, 120, 46)
const ECHO_BAND := Rect2(12, 193, 134, 25)
const GEM_STEP := 26.0
const GEM_SIZE := 13.0

var card_id: String
var selected: bool = false
var playable: bool = true

## Приподнимать карту под курсором самой.
##
## Везде, кроме руки: в веере этим занимается сам веер — там ещё наклон,
## дуга и порядок отрисовки, и две анимации на одном узле дерутся. А вот
## в награде, лавке и сборке карта раньше стояла мёртвая, и было неясно,
## кликается она вообще или просто нарисована.
var hover_lift: bool = true
## Базовый масштаб: карта в сетке уже уменьшена, и наведение должно
## увеличивать ОТ него, а не сбрасывать в единицу.
var base_scale: float = 1.0

var _hovered: bool = false
var _hover_tween: Tween

var _c: Dictionary = {}
var _element: String = "none"
var _tint: Color = Palette.MUTED
var _rarity: String = "common"
var _rarity_color: Color = Palette.MUTED
var _is_curse: bool = false
var _need: int = 1
var _filled: int = 0
var _art: Texture2D
var _name_label: Label
var _text: RichTextLabel
var _echo_label: Label

func _init(p_card_id: String) -> void:
	card_id = p_card_id
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = SIZE * 0.5

func _ready() -> void:
	_c = DB.card(card_id)
	_element = str(_c.get("element", "none"))
	_tint = Palette.element_color(_element)
	_rarity = str(_c.get("rarity", "common"))
	_rarity_color = Palette.rarity_color(_rarity)
	_is_curse = _rarity == "curse"
	_need = int(_c.get("dice", 1))
	if _is_curse:
		_tint = Color("6d3350")
	tooltip_text = str(_c.get("name", card_id))

	# Заточенная карта — та же карта, у неё id с плюсом («dirge+»), а файл
	# рисунка лежит под базовым именем. Без отката на базовое имя окно
	# картинки у заточенной карты оказывалось пустым прямо посреди боя.
	_art = _load_art(card_id)
	if _art == null and card_id.ends_with("+"):
		_art = _load_art(card_id.trim_suffix("+"))

	# ── имя на ленте. Длинное имя набирается мельче, а не переносится вниз:
	# лента одной высоты у всех карт, и прыгающая высота ломала бы ряд
	_name_label = Label.new()
	_name_label.add_theme_font_override("font", UI.serif())
	_name_label.add_theme_color_override("font_color", Color("f6ecd6"))
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.text = str(_c.get("name", card_id))
	_name_label.position = Vector2(NAME_BAND.position.x + 15, NAME_BAND.position.y)
	_name_label.size = Vector2(NAME_BAND.size.x - 30, NAME_BAND.size.y)
	_name_label.add_theme_font_size_override("font_size", _fit_name())
	add_child(_name_label)

	# ── правила карты. RichTextLabel, а не Label, ради жирного внутри строки
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.fit_content = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_override("normal_font", UI.sans())
	_text.add_theme_font_override("bold_font", UI.bold())
	_text.add_theme_color_override("default_color", _ink())
	_text.add_theme_constant_override("line_separation", 1)
	_text.position = TEXT_RECT.position
	_text.size = TEXT_RECT.size
	var body := str(_c.get("text", ""))
	var body_size := _fit_size(body, TEXT_RECT.size)
	_text.add_theme_font_size_override("normal_font_size", body_size)
	_text.add_theme_font_size_override("bold_font_size", body_size)
	_text.text = "[center]%s[/center]" % _emphasise(body)
	add_child(_text)

	# ── лента созвучия
	_echo_label = Label.new()
	_echo_label.add_theme_font_override("font", UI.serif())
	_echo_label.add_theme_color_override("font_color", Color("f6ecd6"))
	_echo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_echo_label.add_theme_constant_override("shadow_offset_x", 1)
	_echo_label.add_theme_constant_override("shadow_offset_y", 1)
	_echo_label.add_theme_font_size_override("font_size", 11)
	_echo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_echo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_echo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_echo_label.text = _echo_text()
	_echo_label.position = ECHO_BAND.position
	_echo_label.size = ECHO_BAND.size
	add_child(_echo_label)

	refresh()

func _load_art(id: String) -> Texture2D:
	var path := "res://assets/cards/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path)
	return null

# ─────────────────────────────────────────── текст

## Цвет текста правил. У проклятий бумага грязная — и текст другой.
func _ink() -> Color:
	return Color("d8c0cf") if _is_curse else Color("efe3c6")

## Что написать на нижней ленте.
func _echo_text() -> String:
	if _is_curse:
		return "Проклятие"
	var short := Palette.resonance_short(_element)
	if short == "":
		return "Без стихии"
	return "Созвучие: " + short

## Что выделять жирным.
##
## Жирным помечается УСЛОВИЕ, а не число: цифру игрок и так находит глазами,
## а вот «при каком кубике она сработает» — то, из-за чего карту кладут на
## один кубик, а не на другой. Плюс всё, что меняет правила: пробивание
## блока, сгорание, накопление.
##
## Порядок важен: сперва длинные обороты, потом короткие. Иначе «Огненный»
## сработает внутри «Огненный кубик» и разорвёт разметку пополам.
const BOLD_PHRASES := [
	"Каждый следующий раз за бой", "Принимает только",
	"Каждый ледяной кубик", "Каждый огненный кубик",
	"каждый ледяной кубик", "каждый огненный кубик", "каждый готовый кубик",
	"Огненный кубик", "Ледяной кубик", "Природный кубик",
	"Светлый кубик", "Тёмный кубик", "Оплаченный кубик",
	"не уходит на перезарядку", "игнорирует блок", "не сгорает до конца боя",
	"Блок не сгорает", "Блок остаётся", "Ожог не слабеет",
	"Карта сгорает", "Нельзя разыграть", "Весь мешочек",
	"Верни в строй", "Возвращает в строй", "Остуди",
	"Мощь", "Огненный", "Ледяной", "Природный", "Светлый", "Тёмный",
]

## Метка-заполнитель. Ромб взят намеренно: в текстах карт его нет и быть не
## может, поэтому подстановка не наткнётся сама на себя.
const MARK := "◊"

func _emphasise(text: String) -> String:
	# Замена идёт через метки, а не сразу в [b]: иначе следующая фраза нашла
	# бы себя внутри уже размеченного куска и вложила теги друг в друга.
	var out := text
	var found: Array = []
	for phrase in BOLD_PHRASES:
		var at := out.find(phrase)
		while at >= 0:
			var token := "%s%d%s" % [MARK, found.size(), MARK]
			found.append(phrase)
			out = out.substr(0, at) + token + out.substr(at + phrase.length())
			at = out.find(phrase)
	for i in found.size():
		out = out.replace("%s%d%s" % [MARK, i, MARK], "[b]%s[/b]" % str(found[i]))
	return out

## Подобрать кегль так, чтобы текст ГАРАНТИРОВАННО влез в поле.
##
## Это единственный честный способ: автоподбора у Godot нет, а «на глаз»
## ломается на первой же длинной карте. Меряем настоящим шрифтом сверху
## вниз и берём первый кегль, который помещается. Запас по ширине — под
## жирное начертание, оно шире обычного.
func _fit_size(text: String, box: Vector2) -> int:
	# Меряем ЖИРНЫМ, хотя большая часть текста обычная: жирный шире, и если
	# влезает он — влезет и всё остальное. Первая версия мерила обычным, и
	# на «Ледяном щите» последняя строка уезжала на ленту созвучия.
	var f := UI.bold()
	for s in range(12, 6, -1):
		var m := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
			box.x - 10.0, s)
		# межстрочный интервал RichTextLabel в замер не входит — добавляем сами
		var lines: int = maxi(1, int(round(m.y / maxf(1.0, f.get_height(s)))))
		if m.y + float(lines - 1) <= box.y - 3.0:
			return s
	return 7

func _fit_name() -> int:
	var f := UI.serif()
	var card_name := str(_c.get("name", card_id))
	for s in range(15, 8, -1):
		var m := f.get_multiline_string_size(card_name, HORIZONTAL_ALIGNMENT_CENTER,
			NAME_BAND.size.x - 32.0, s)
		if m.y <= NAME_BAND.size.y - 4.0:
			return s
	return 10

## Своя подсказка вместо системной плашки.
##
## Системная — это серый прямоугольник с полем текста во всю ширину экрана:
## пустоты много, стиля нет, а читать в нём нечего, потому что всё главное
## и так написано на карте. Здесь только то, чего на карте НЕТ: во что она
## превращается после заточки, что именно сделает созвучие и какие
## ограничения на кубик.
func _make_custom_tooltip(_for_text: String) -> Object:
	var box := UI.panel(Palette.GROUND.darkened(0.18), Palette.EDGE, 12)
	var col := UI.vbox(6)
	col.custom_minimum_size.x = 260
	box.add_child(col)

	var head := UI.hbox(8)
	head.add_child(UI.named(str(_c.get("name", card_id)), UI.SMALL + 4, Palette.BONE))
	head.add_child(UI.spacer())
	head.add_child(UI.chip(Palette.rarity_name(_rarity), _rarity_color, ""))
	col.add_child(head)

	col.add_child(UI.label("%s · %s" % [
		_dice_word(),
		Palette.element_name(_element) if _element != "none" else "без стихии",
	], UI.TINY + 1, Palette.MUTED))

	col.add_child(_rule_line())

	var up: Dictionary = _c.get("upgrade", {})
	if not up.is_empty():
		col.add_child(UI.label("После заточки", UI.TINY, Palette.BRASS_DIM))
		col.add_child(UI.wrapped(str(up.get("text", "")), UI.SMALL, Palette.BRASS, 250))

	if _element != "none" and not _is_curse:
		col.add_child(_rule_line())
		col.add_child(UI.label("Созвучие", UI.TINY, Palette.MUTED))
		col.add_child(UI.wrapped(Palette.resonance(_element), UI.SMALL,
			Palette.element_color(_element).lightened(0.15), 250))

	var notes: Array = []
	if _c.has("min_faces"):
		notes.append("Годится только кубик от d%d." % int(_c.min_faces))
	if bool(_c.get("require_element", false)):
		notes.append("Принимает только %s кубики." % Palette.element_name(_element).to_lower())
	if bool(_c.get("exhaust", false)):
		notes.append("Сгорает: до конца боя карты больше не будет.")
	if not notes.is_empty():
		col.add_child(_rule_line())
		col.add_child(UI.wrapped("\n".join(notes), UI.TINY + 1, Palette.BONE_DIM, 250))
	return box

## Волосяная линия-разделитель: подсказка делится на смысловые куски,
## но заголовки на каждый кусок — это уже документ, а не подсказка.
func _rule_line() -> Control:
	var line := Panel.new()
	line.custom_minimum_size.y = 1
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.EDGE, 0.9)
	line.add_theme_stylebox_override("panel", sb)
	return line

func _dice_word() -> String:
	if _need == 1:
		return "1 кубик"
	if _need < 5:
		return "%d кубика" % _need
	return "%d кубиков" % _need

# ─────────────────────────────────────────── состояние

## Сколько кубиков уже положено на карту: закрашивает алмазы слева.
func set_filled(n: int) -> void:
	if n == _filled:
		return
	_filled = n
	queue_redraw()

func refresh() -> void:
	modulate = Color(1, 1, 1, 1.0 if playable else 0.55)
	queue_redraw()

# ─────────────────────────────────────────── рисование

func _draw() -> void:
	var frame := Color("3a2130") if _is_curse else _tint.darkened(0.42)
	var frame_hi := _tint.lightened(0.18)
	var body := Color("1d141c") if _is_curse else Color("241c16")

	# 1. корпус карты
	_rounded(Rect2(Vector2.ZERO, SIZE), 14, Color(0, 0, 0, 0.55))
	_rounded(Rect2(2, 2, SIZE.x - 4, SIZE.y - 4), 13, frame)
	# фаска: светлая линия по краю — без неё карта читается плоской наклейкой
	_rounded_outline(Rect2(3, 3, SIZE.x - 6, SIZE.y - 6), 12, Color(frame_hi, 0.55), 2.0)
	_rounded(Rect2(9, 9, SIZE.x - 18, SIZE.y - 18), 9, body)

	# 2. окно с рисунком
	_rounded(ART_RECT.grow(3), 8, Color(0, 0, 0, 0.6))
	_rounded(ART_RECT, 6, Color("15110d"))
	if _art != null:
		# вписываем целиком, не обрезая: у иконок своя рамка, и кроп её рубит
		var s: float = minf(ART_RECT.size.x / 128.0, ART_RECT.size.y / 128.0)
		var draw_size := Vector2(128, 128) * s
		var at := ART_RECT.position + (ART_RECT.size - draw_size) * 0.5
		draw_texture_rect(_art, Rect2(at, draw_size), false)
	_rounded_outline(ART_RECT, 6, Color(frame_hi, 0.7), 2.0)

	# 3. лента с именем
	_band(NAME_BAND, frame.lightened(0.10), frame_hi)

	# 4. самоцвет редкости под лентой
	var gem_c := Vector2(SIZE.x * 0.5, NAME_BAND.end.y + 5.0)
	draw_circle(gem_c, 7.0, Color(0, 0, 0, 0.5))
	draw_circle(gem_c, 5.5, _rarity_color)
	draw_circle(gem_c - Vector2(1.4, 1.6), 2.0, Color(1, 1, 1, 0.55))

	# 5. поле правил
	_rounded(TEXT_RECT.grow(5), 8, Color(0, 0, 0, 0.34))
	_rounded(TEXT_RECT.grow(3), 7, Color("18101a") if _is_curse else Color("1b1510"))

	# 6. лента созвучия
	_band(ECHO_BAND, Color("4a2438") if _is_curse else _tint.darkened(0.24), frame_hi)

	# 7. алмазы по числу кубиков — слева, поверх рамки
	for i in _need:
		_diamond(Vector2(12.0, 27.0 + GEM_STEP * i), GEM_SIZE, i < _filled)

	# 8. выделение: выбранная — сплошным, наведённая — потоньше
	if selected:
		_rounded_outline(Rect2(1, 1, SIZE.x - 2, SIZE.y - 2), 14, Palette.BRASS, 3.0)
	elif _hovered:
		_rounded_outline(Rect2(1, 1, SIZE.x - 2, SIZE.y - 2), 14, Color(Palette.BRASS, 0.75), 2.0)

## Скруглённый прямоугольник заливкой.
func _rounded(r: Rect2, radius: int, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	draw_style_box(sb, r)

## Скруглённый прямоугольник контуром.
func _rounded_outline(r: Rect2, radius: int, color: Color, width: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.draw_center = false
	sb.border_color = color
	sb.set_border_width_all(int(width))
	sb.set_corner_radius_all(radius)
	draw_style_box(sb, r)

## Лента: полоса с вырезанными «ласточкиным хвостом» концами.
## Именно вырез отличает ленту от плашки — без него верх карты читается
## как ещё одна панель, а не как надпись на баннере.
func _band(r: Rect2, fill: Color, edge: Color) -> void:
	var notch: float = minf(13.0, r.size.x * 0.09)
	var top := r.position.y
	var bot := r.end.y
	var mid := (top + bot) * 0.5
	var pts := PackedVector2Array([
		Vector2(r.position.x, top),
		Vector2(r.end.x, top),
		Vector2(r.end.x - notch, mid),
		Vector2(r.end.x, bot),
		Vector2(r.position.x, bot),
		Vector2(r.position.x + notch, mid),
	])
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 2))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
	draw_colored_polygon(pts, fill)
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	draw_polyline(outline, Color(edge, 0.8), 1.6)

## Алмаз — цена карты в кубиках. Один алмаз = один кубик: считать проще, чем
## читать цифру, и на маленькой карте цифра всё равно нечитаема.
func _diamond(c: Vector2, s: float, lit: bool) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0, -s), c + Vector2(s * 0.72, 0),
		c + Vector2(0, s), c + Vector2(-s * 0.72, 0),
	])
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 2))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.5))
	var face: Color = _tint.lightened(0.35) if lit else _tint.darkened(0.15)
	if _is_curse:
		face = Color("8a4a70") if lit else Color("4b2740")
	draw_colored_polygon(pts, face)
	# блик на верхней грани — иначе камень читается плоским ромбом
	draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c]), Color(1, 1, 1, 0.30))
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	draw_polyline(outline, Color("f0dcae") if lit else Color(0, 0, 0, 0.55), 1.5)

func _notification(what: int) -> void:
	if not hover_lift or not playable:
		return
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		_grow(base_scale * 1.12, 12)
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		_grow(base_scale, 0)

func _grow(target: float, z: int) -> void:
	queue_redraw()
	z_index = z          # z_index, а не move_to_front: порядок детей в
	                     # контейнере — это порядок раскладки, трогать нельзя
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", Vector2(target, target), 0.1)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
	   and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(card_id)
		accept_event()

## Уменьшенная карта для сеток, где важен охват, а не чтение мелочей.
##
## Масштаб через scale, а не через отдельную вёрстку: карта рисуется одним
## и тем же кодом, поэтому в сетке она выглядит ровно так же, как в руке, —
## и выбирать её игрок учится один раз, а не дважды.
static func scaled(p_card_id: String, factor: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = SIZE * factor
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := CardView.new(p_card_id)
	# растём от нижнего края: карта в сетке поднимается, а не расползается
	v.pivot_offset = Vector2(SIZE.x * 0.5, SIZE.y)
	v.position = Vector2(SIZE.x * 0.5 * (factor - 1.0), SIZE.y * (factor - 1.0))
	v.scale = Vector2(factor, factor)
	v.base_scale = factor
	holder.add_child(v)
	return holder

## Достать карту из обёртки, которую вернул scaled().
static func inner(holder: Control) -> CardView:
	for c in holder.get_children():
		if c is CardView:
			return c
	return null
