class_name UI
extends RefCounted
## Мелкие помощники, чтобы не повторять один и тот же код во всех экранах.

const H1 := 34
const H2 := 26
const H3 := 19
const BODY := 16
const SMALL := 13
const TINY := 11

## Два шрифта, оба свободные (OFL, лицензии в assets/fonts/LICENSE-fonts.txt).
## Lora — антиква с кириллицей: всё крупное, что должно звучать как надпись
## в книге. Carlito — гротеск: мелочь, которую читают быстро и не любуются.
## Правило простое и держится само: от H3 и выше — антиква, ниже — гротеск.
## Из-за него не приходится помнить про шрифт на каждом вызове.
static var _serif: FontFile
static var _sans: FontFile

static func serif() -> FontFile:
	if _serif == null:
		_serif = load("res://assets/fonts/Lora.ttf")
	return _serif

static func sans() -> FontFile:
	if _sans == null:
		_sans = load("res://assets/fonts/Carlito-Regular.ttf")
	return _sans

## Полужирный гротеск. Нужен ровно для одного: выделять внутри строки на
## карте условие, при котором эффект срабатывает. RichTextLabel подставляет
## его сам по тегу [b], если шрифт назначен как bold_font.
static var _bold: FontFile

static func bold() -> FontFile:
	if _bold == null:
		_bold = load("res://assets/fonts/Carlito-Bold.ttf")
	return _bold

static func label(text: String, size: int = BODY, color: Color = Palette.BONE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", serif() if size >= H3 else sans())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Принудительно антиквой — для имён карт и врагов, которые меньше H3,
## но всё равно должны звучать как имя.
static func named(text: String, size: int = BODY, color: Color = Palette.BONE) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", serif())
	return l

## Мелкая подпись-разделитель: РАЗРЯДКОЙ И КАПСОМ.
static func caption(text: String) -> Label:
	var l := label(text.to_upper(), TINY, Palette.MUTED)
	l.add_theme_constant_override("line_spacing", 2)
	return l

static func wrapped(text: String, size: int = BODY, color: Color = Palette.BONE_DIM, width: int = 560) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l

static func button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", sans())
	b.add_theme_font_size_override("font_size", SMALL + 1)
	var fill := Palette.BRASS if primary else Palette.RAISED
	var edge := Color("e2b76a") if primary else Palette.EDGE
	var text_color := Color("231a09") if primary else Palette.BONE
	b.add_theme_stylebox_override("normal", _btn_box(fill, edge))
	b.add_theme_stylebox_override("hover", _btn_box(fill.lightened(0.08), Palette.BRASS_DIM if not primary else edge))
	b.add_theme_stylebox_override("pressed", _btn_box(fill.darkened(0.12), edge))
	b.add_theme_stylebox_override("disabled", _btn_box(fill.darkened(0.35), Palette.EDGE_SOFT))
	b.add_theme_stylebox_override("focus", _btn_box(Color(0, 0, 0, 0), Palette.BRASS))
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", text_color)
	b.add_theme_color_override("font_disabled_color", Color(text_color, 0.45))
	return b

static func _btn_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Панель — кусок выделанной кожи, а не залитый прямоугольник.
## Текстура и рамка запекаются в картинку один раз на сочетание цветов,
## дальше берутся из кэша, так что панелей можно делать сколько угодно.
static func panel(fill: Color = Palette.GROUND_2, edge: Color = Palette.EDGE_SOFT, pad: int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(fill, edge, pad))
	return p

static func panel_box(fill: Color = Palette.GROUND_2, edge: Color = Palette.EDGE_SOFT, pad: int = 14) -> StyleBoxTexture:
	var tex := Paper.hide(fill, Vector2i(96, 96), 3, edge)
	return Paper.box(tex, pad, 8)

## Плоская панель — там, где текстура мешает: узкие плашки, подложки.
static func flat_panel(fill: Color, edge: Color, pad: int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel", sb)
	return p

static func vbox(gap: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v

static func hbox(gap: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func gap(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	return c

## Ключевые слова. Игрок не должен угадывать, что делает «уязвимость» —
## подсказка всплывает над любой картой и плашкой, где слово встретилось.
const KEYWORDS := {
	"мощь": "Мощь — бросок попал в верхнюю треть граней кубика (у d4 — максимум). Многие карты дают за это добавку.",
	"блок": "Блок гасит урон в ход врага и сгорает в начале твоего следующего хода, если не сказано иначе.",
	"броня": "Броня врага не сгорает в конце хода, но теряет 1 за каждый твой удар.",
	"яд": "Яд срабатывает в конце хода врага и после этого уменьшается на 1.",
	"уязвимость": "Уязвимость — получаемый урон вырастает в полтора раза на указанное число ходов.",
	"слабость": "Слабость — удары бьют слабее на указанное число, пока она держится.",
	"шипы": "Шипы отвечают уроном тому, кто ударил.",
	"ржавчина": "Ржавчина добавляет ходы перезарядки кубикам — они дольше возвращаются в мешочек.",
	"перезарядка": "После броска кубик уходит остывать и вернётся через столько своих ходов, сколько указано на нём.",
	"сжигается": "Сжигается — карта уходит из боя насовсем и не вернётся в колоду добора.",
	"вампиризм": "Часть нанесённого урона возвращается здоровьем.",
	"ожог": "Ожог жжёт врага в конце каждого его хода и, в отличие от яда, не слабеет со временем.",
	"стужа": "Стужа — враг бьёт слабее на указанное число, пока держится.",
	"побег": "Побег снимает ход перезарядки с остывающего кубика.",
	"озарение": "Озарение добирает карту.",
	"порча": "Порча делает врага уязвимым, но забирает 2 твоего здоровья.",
	"стихия": "Стихия кубика (огонь, лёд, природа, свет, тьма). Некоторые карты требуют или награждают совпадение.",
}

## Собирает подсказку из тех ключевых слов, что встретились в тексте.
static func keyword_hint(text: String) -> String:
	var low := text.to_lower()
	var out: Array = []
	for k in KEYWORDS.keys():
		if low.find(str(k)) >= 0:
			out.append(str(KEYWORDS[k]))
	return "\n\n".join(out)

## Плашка статуса: «Блок 12», «Яд 4» и т.п.
## Если для смысла есть иконка — ставится она, иначе только текст.
static func chip(text: String, color: Color, icon_concept: String = "") -> PanelContainer:
	var p := flat_panel(Color(Palette.GROUND, 0.55), Color(color, 0.7), 0)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.content_margin_left = 7
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	var row := hbox(5)
	if icon_concept != "":
		var ic := Icons.make(icon_concept, 15, color)
		if ic:
			row.add_child(ic)
	row.add_child(label(text, SMALL, color))
	p.add_child(row)
	# плашка сама объясняет свой статус: игроку не надо помнить, чем ожог
	# отличается от яда
	var hint := keyword_hint(text)
	if hint != "":
		p.tooltip_text = hint
		p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p
