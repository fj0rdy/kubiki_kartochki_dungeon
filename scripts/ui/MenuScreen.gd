extends Control
## Главное меню.
##
## До него игра начиналась сразу с экрана сборки, и у неё не было ни начала,
## ни выхода: закрыть окно можно было только крестиком. Меню решает три
## вещи разом — даёт игре порог входа, кладёт галерею туда, где её ищут
## (а не в бой), и добавляет честную кнопку «Выход».

signal start_requested
signal gallery_requested

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := UI.vbox(10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := UI.label("Dice & Dungeon", UI.H1 + 14, Palette.BRASS)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := UI.wrapped(
		"Колодострой на настоящих кубиках. Карта говорит, что случится, "
		+ "кубик — насколько сильно.", UI.BODY, Palette.BONE_DIM, 460)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(UI.gap(18))

	col.add_child(_menu_button("Начать забег", true, func(): start_requested.emit()))
	col.add_child(_menu_button("Галерея", false, func(): gallery_requested.emit()))
	col.add_child(_menu_button("Выход", false, func(): get_tree().quit()))

	col.add_child(UI.gap(14))
	var hint := UI.label("В галерее собрано всё, что может попасться в подземелье.",
		UI.SMALL, Palette.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

func _menu_button(text: String, primary: bool, action: Callable) -> Button:
	var b := UI.button(text, primary)
	b.custom_minimum_size = Vector2(280, 46)
	b.add_theme_font_size_override("font_size", UI.BODY + 2)
	b.pressed.connect(action)
	return b
