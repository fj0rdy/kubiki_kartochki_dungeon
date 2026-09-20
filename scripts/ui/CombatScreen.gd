extends Control
## Экран боя.
##
## Главный на этом экране — лоток. Игрок смотрит туда каждый ход, и всё
## остальное расставлено вокруг него.
##
## Что поменялось и почему:
##  · лоток переехал вниз, к руке и мешочку — раньше кубики лежали справа,
##    карты снизу, и взгляд мотало по диагонали через весь экран;
##  · лог и список приёмов врага ушли из постоянной разметки: оба статичны и
##    занимали середину. Лог сворачивается в кнопку (поражение обязано быть
##    объяснимым, поэтому выбрасывать его нельзя), приёмы врага переехали в
##    подсказку по наведению на врага;
##  · фигуры и полосы здоровья крупнее, броня показана отдельным щитом;
##  · стопки колоды и сброса нарисованы, а не написаны словом.

signal fight_finished(player_won: bool)

const SHAKE_SMALL := 3.0
const SHAKE_MID := 6.0
const SHAKE_BIG := 10.0

var combat: Combat
var selected_index: int = -1
var assigned: Array = []          # [{die, value}] — уже брошенные
## Кубики, отобранные под карту, но ещё не брошенные.
##
## Раньше клик по кубику сразу его кидал, и карта на три кубика превращалась
## в три отдельных броска подряд, между которыми ничего нельзя было изменить.
## Теперь сначала набирается горсть, и только потом она летит на сукно —
## одним движением или кнопкой. Пока горсть не собрана, бросок недоступен.
var staged: Array = []            # [Die]
var busy: bool = false

var _tray: DiceTray
var _hand: HandFan

var _foe_name: Label
var _intent_box: PanelContainer
var _intent_label: Label
var _intent_icon_slot: Control
var _foe_hp_bar: ProgressBar
var _foe_hp_text: Label
var _foe_stats: HFlowContainer
var _foe_art: EnemyArt
var _foe_column: Control
var _log_btn: Button
var _log_panel_box: PanelContainer
var _throw_all_btn: Button
var _hero_shield: Control
var _hero_shield_n: Label
var _foe_shield: Control
var _foe_shield_n: Label
var _draw_stack: Control
var _disc_stack: Control
var _foe_tax: Label
var _foe_fx: Control

var _hp_big: Label
var _foe_hp_big: Label
var _preview_mine: VBoxContainer
var _preview_theirs: VBoxContainer
var _hp_bar: ProgressBar
var _hp_text: Label
var _hero_stats: HFlowContainer
var _hero_fx: Control
var _hero_art: EnemyArt
var _log: RichTextLabel

var _rack_main: Control
var _rack_special: Control
var _dice_row: HBoxContainer
var _special_row: HBoxContainer
var _hint: Label
var _draw_n: Label
var _disc_n: Label
var _end_btn: Button
var _regroup_btn: Button
var _cancel_btn: Button
var _die_views: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()

# ────────────────────────────────────────── разметка

## Разметка не контейнерная, а якорная.
##
## Вложенные панели давали ровно то, чего на столе быть не должно: рамки,
## отступы и границы между «зонами». На макете нет ни одной рамки — есть
## доска, на ней сукно, по краям доски бойцы, снизу карты и стойка с
## кубиками. Каждая часть прибита якорями к своему углу, а фон один на всех.
func _build() -> void:
	# слой 1 — поле для броска. Оно лежит ниже всего остального, потому что
	# это буквально поверхность стола, а не окно поверх него
	_tray = DiceTray.new()
	_tray.anchor_left = 0.17
	_tray.anchor_right = 0.83
	_tray.anchor_top = 0.05
	_tray.anchor_bottom = 0.53
	_tray.die_thrown.connect(_on_die_thrown)
	_tray.drag_cancelled.connect(func(_die): _refresh())
	add_child(_tray)

	# слой 3 — предпросмотр: что получишь ты и что получит враг.
	# Числа висят прямо над сукном, между бойцами: решение принимается здесь,
	# и смотреть ради него в угол экрана не надо
	_preview_mine = UI.vbox(2)
	_preview_mine.alignment = BoxContainer.ALIGNMENT_CENTER
	_preview_mine.anchor_left = 0.21
	_preview_mine.anchor_right = 0.36
	_preview_mine.anchor_top = 0.06
	_preview_mine.anchor_bottom = 0.30
	_preview_mine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview_mine)

	_preview_theirs = UI.vbox(2)
	_preview_theirs.alignment = BoxContainer.ALIGNMENT_CENTER
	_preview_theirs.anchor_left = 0.64
	_preview_theirs.anchor_right = 0.79
	_preview_theirs.anchor_top = 0.06
	_preview_theirs.anchor_bottom = 0.30
	_preview_theirs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview_theirs)

	# слой 4 — бойцы по краям доски
	var hero := _hero_column()
	hero.anchor_left = 0.0
	hero.anchor_right = 0.0
	hero.anchor_top = 0.0
	hero.offset_left = 24
	hero.offset_top = 8
	hero.offset_right = 24 + 300
	add_child(hero)

	var foe := _enemy_column()
	foe.anchor_left = 1.0
	foe.anchor_right = 1.0
	foe.anchor_top = 0.0
	foe.offset_left = -24 - 320
	foe.offset_right = -24
	foe.offset_top = 8
	add_child(foe)

	# слой 5 — рука. Лежит поверх стола и заходит на сукно снизу,
	# как настоящие карты, которые держат над столом
	_hand = HandFan.new()
	_hand.anchor_left = 0.11
	_hand.anchor_right = 0.82
	_hand.anchor_top = 0.40
	_hand.anchor_bottom = 0.86
	_hand.card_clicked.connect(_on_card_clicked)
	add_child(_hand)

	# слой 6 — стойки с кубиками под рукой. Их две: обычные кубики и особые.
	# Особый кубик — редкая награда со своим правилом, и теряться в общем
	# ряду он не должен: сваленные в кучу, они читаются как один мешок.
	_rack_main = _dice_rack(false)
	add_child(_rack_main)
	_rack_special = _dice_rack(true)
	_rack_special.visible = false
	add_child(_rack_special)

	# слой 7 — стопки в углах
	var draw_pile := _pile("Колода", Palette.BRASS_DIM, false)
	_draw_stack = draw_pile[0]
	_draw_n = draw_pile[1]
	_draw_stack.anchor_top = 1.0
	_draw_stack.anchor_bottom = 1.0
	_draw_stack.offset_left = 30
	_draw_stack.offset_right = 30 + 104
	_draw_stack.offset_top = -136
	_draw_stack.offset_bottom = -16
	add_child(_draw_stack)

	var disc_pile := _pile("Сброс", Palette.MUTED, true)
	_disc_stack = disc_pile[0]
	_disc_n = disc_pile[1]
	_disc_stack.anchor_left = 1.0
	_disc_stack.anchor_right = 1.0
	_disc_stack.anchor_top = 1.0
	_disc_stack.anchor_bottom = 1.0
	_disc_stack.offset_left = -134
	_disc_stack.offset_right = -30
	_disc_stack.offset_top = -136
	_disc_stack.offset_bottom = -16
	add_child(_disc_stack)

	# слой 8 — кнопки справа, над стопкой сброса
	var acts := _action_column()
	acts.anchor_left = 1.0
	acts.anchor_right = 1.0
	acts.anchor_top = 0.5
	acts.offset_left = -24 - 210
	acts.offset_right = -24
	acts.offset_top = -30
	add_child(acts)

	# слой 9 — кнопка разбора боя в углу
	_log_btn = UI.button("Журнал боя")
	_log_btn.tooltip_text = "Разбор боя: кто сколько нанёс и что сработало.\nГорячая клавиша: Tab"
	_log_btn.pressed.connect(func(): _toggle_log())
	_log_btn.anchor_left = 0.5
	_log_btn.anchor_right = 0.5
	_log_btn.offset_left = -66
	_log_btn.offset_right = 66
	_log_btn.offset_top = 6
	add_child(_log_btn)

	_build_log_overlay()

## Стойка под кубики: доска, лежит под рукой.
##
## Мешочек стоял сбоку отдельной панелью, и от него до сукна было полэкрана.
## На стойке кубики лежат ровно там, где рука их берёт, и видно их все сразу.
func _dice_rack(special: bool) -> Control:
	var holder := Control.new()
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0

	var board := Panel.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2f2213") if special else Color("2a1f16")
	sb.border_color = Color(Palette.BRASS, 0.8) if special else Color(Palette.BRASS_DIM, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	board.add_theme_stylebox_override("panel", sb)
	holder.add_child(board)

	var col := UI.vbox(2)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("margin_left", 10)
	holder.add_child(col)

	var cap := UI.label("Особые" if special else "Выбери карту", UI.TINY + 1,
		Palette.BRASS if special else Palette.BRASS)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	if special:
		holder.tooltip_text = ("Особые кубики. У каждого своё правило — наведи на кубик,\n"
			+ "чтобы прочитать. Они падают за пройденный акт и из сундуков.")
	else:
		_hint = cap

	# Один ряд с прокруткой, а не перенос на вторую строку.
	#
	# Со вторым рядом доска росла вверх и закрывала руку — а рука это то,
	# чем игрок думает. Кубиков к третьему акту может быть девять, и лучше
	# прокрутить их вбок, чем потерять из виду карты.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	col.add_child(scroll)
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)
	if special:
		_special_row = row
	else:
		_dice_row = row
	return holder

## Разложить стойки по ширине и высоте под то, что в них лежит.
##
## Пока особых кубиков нет, обычные стоят по центру — так экран выглядит
## спокойнее. Появился особый — обычные съезжают влево, справа встаёт вторая
## полка. Ряд переносится сам, и высота доски считается по числу рядов,
## иначе седьмой кубик просто вываливался вниз мимо доски.
const DIE_SLOT := 94.0
const ROW_H := 88.0

func _place_racks(normal_count: int, special_count: int) -> void:
	var has_special := special_count > 0
	_rack_special.visible = has_special
	# доска всегда в один кубик высотой: если не влезает — прокручиваем вбок
	var h := 26.0 + ROW_H

	var main_l := -320.0
	var main_r := 320.0
	if has_special:
		main_l = -430.0
		main_r = 130.0
		var sp_w: float = clampf(DIE_SLOT * special_count + 24.0, 150.0, 300.0)
		_rack_special.offset_left = 146.0
		_rack_special.offset_right = 146.0 + sp_w
		_rack_special.offset_top = -h - 14.0
		_rack_special.offset_bottom = -14.0

	_rack_main.offset_left = main_l
	_rack_main.offset_right = main_r
	_rack_main.offset_top = -h - 14.0
	_rack_main.offset_bottom = -14.0

## Кнопки хода: конец хода — самый заметный элемент правой стороны,
## под ним всё, что делается реже.
func _action_column() -> Control:
	var col := UI.vbox(7)
	_end_btn = UI.button("Конец хода", true)
	_end_btn.tooltip_text = "Закончить ход. Горячая клавиша: пробел"
	_end_btn.custom_minimum_size.y = 46
	_end_btn.add_theme_font_size_override("font_size", UI.SMALL + 4)
	_end_btn.pressed.connect(func(): if not busy: combat.end_turn())
	col.add_child(_end_btn)

	_regroup_btn = UI.button("Собраться  \u2212%d" % int(DB.b("regroup_cost", 4)))
	_regroup_btn.tooltip_text = ("Закончить ход и снять %d хода перезарядки со всех кубиков.\n\n"
		+ "Цена: %d здоровья. Один раз за бой это дёшево, каждый ход — заметно.\n\n"
		+ "Кнопка на случай «нечем ходить»: когда все кубики остывают, а карты "
		+ "в руке требуют больше, чем у тебя есть.\n\nГорячая клавиша: R") % [int(DB.b("regroup_relief", 2)), int(DB.b("regroup_cost", 4))]
	_regroup_btn.pressed.connect(func(): if not busy: combat.regroup())
	col.add_child(_regroup_btn)

	_throw_all_btn = UI.button("Бросить всё", true)
	_throw_all_btn.tooltip_text = "Бросить собранную горсть.\nГорячая клавиша: Enter"
	_throw_all_btn.visible = false
	_throw_all_btn.pressed.connect(_throw_all)
	col.add_child(_throw_all_btn)

	_cancel_btn = UI.button("Отменить")
	_cancel_btn.tooltip_text = "Снять выделение с карты и вернуть кубики.\nГорячая клавиша: Esc"
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(_clear_selection)
	col.add_child(_cancel_btn)
	return col

func _hero_column() -> Control:
	var col := UI.vbox(4)

	_hero_fx = Control.new()
	_hero_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hero_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hero_fx)

	# Здоровье крупным числом рядом с фигурой. Полоса показывает долю, число —
	# сколько именно осталось; решение «переживу ли я следующий удар»
	# принимается по числу, и искать его глазами игрок не должен.
	var top := UI.hbox(10)
	_hero_art = EnemyArt.new()
	# герой смотрит вправо, на врага: тот же силуэт, отражённый по горизонтали
	_hero_art.scale.x = -1.0
	_hero_art.pivot_offset = EnemyArt.SIZE * 0.5
	top.add_child(_hero_art)
	var hp_box := UI.vbox(0)
	hp_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_hp_big = UI.named("0", 40, Palette.BONE)
	hp_box.add_child(_hp_big)
	hp_box.add_child(UI.caption("Искатель"))
	top.add_child(hp_box)
	col.add_child(top)

	var bar := _make_bar(Palette.HEAL, 280)
	_hp_bar = bar[0]
	_hp_text = bar[1]
	_hero_shield = bar[3]
	_hero_shield_n = bar[4]
	col.add_child(bar[2])
	_hero_stats = _make_flow()
	col.add_child(_hero_stats)
	return col

func _enemy_column() -> Control:
	var col := UI.vbox(4)
	# приёмы врага живут в подсказке: информация нужна, но постоянного места
	# на экране она не заслуживает
	col.mouse_filter = Control.MOUSE_FILTER_PASS

	_foe_fx = Control.new()
	_foe_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_foe_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_foe_fx)

	var intent_row := UI.hbox(0)
	intent_row.alignment = BoxContainer.ALIGNMENT_END
	_intent_box = UI.flat_panel(Color(Palette.GROUND, 0.72), Palette.EDGE, 0)
	var isb: StyleBoxFlat = _intent_box.get_theme_stylebox("panel")
	isb.content_margin_left = 12
	isb.content_margin_right = 12
	isb.content_margin_top = 5
	isb.content_margin_bottom = 5
	var intent_inner := UI.hbox(8)
	var icon_center := CenterContainer.new()
	icon_center.custom_minimum_size = Vector2(34, 34)
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intent_icon_slot = icon_center
	intent_inner.add_child(icon_center)
	_intent_label = UI.label("", UI.SMALL + 2, Palette.BONE)
	_intent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intent_inner.add_child(_intent_label)
	_intent_box.add_child(intent_inner)
	intent_row.add_child(_intent_box)
	col.add_child(intent_row)

	var top := UI.hbox(10)
	top.alignment = BoxContainer.ALIGNMENT_END
	var name_box := UI.vbox(0)
	name_box.alignment = BoxContainer.ALIGNMENT_END
	_foe_hp_big = UI.named("0", 34, Palette.BONE)
	_foe_hp_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_box.add_child(_foe_hp_big)
	_foe_name = UI.label("—", UI.SMALL + 3, Palette.BRASS)
	_foe_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_box.add_child(_foe_name)
	top.add_child(name_box)
	_foe_art = EnemyArt.new()
	top.add_child(_foe_art)
	col.add_child(top)
	_foe_column = col

	# Налог босса меняет правила боя, значит его нельзя прятать в лог: игрок
	# должен видеть его всё время, пока думает над ходом.
	_foe_tax = UI.wrapped("", UI.TINY + 1, Palette.BRASS, 300)
	_foe_tax.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_foe_tax)

	var bar := _make_bar(Palette.BLOOD, 300)
	_foe_hp_bar = bar[0]
	_foe_hp_text = bar[1]
	_foe_shield = bar[3]
	_foe_shield_n = bar[4]
	col.add_child(bar[2])
	_foe_stats = _make_flow()
	_foe_stats.alignment = FlowContainer.ALIGNMENT_END
	col.add_child(_foe_stats)
	return col

## Лог не выброшен, а свёрнут.
##
## Самое частое, за что хвалят Slay the Spire, — не сложность и не карты, а
## то, что поражение всегда объяснимо. Лог — ровно тот инструмент, которым
## игрок разбирает, почему проиграл. Поэтому основной канал — всплывающие
## числа над бойцами, а лог живёт за кнопкой и разворачивается кликом.
func _build_log_overlay() -> void:
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", UI.SMALL + 1)
	_log.add_theme_color_override("default_color", Palette.BONE_DIM)
	_log.add_theme_font_override("normal_font", UI.sans())
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_log_panel_box = UI.panel(Palette.GROUND.darkened(0.25), Palette.EDGE, 14)
	_log_panel_box.visible = false
	_log_panel_box.custom_minimum_size = Vector2(560, 340)
	_log_panel_box.size = Vector2(560, 340)
	var col := UI.vbox(6)
	var head := UI.hbox(10)
	head.add_child(UI.caption("Журнал боя"))
	head.add_child(UI.spacer())
	var close := UI.button("Закрыть")
	close.pressed.connect(func(): _toggle_log(false))
	head.add_child(close)
	col.add_child(head)
	col.add_child(_log)
	_log_panel_box.add_child(col)
	add_child(_log_panel_box)

func _toggle_log(force = null) -> void:
	if _log_panel_box == null:
		return
	var want: bool = (not _log_panel_box.visible) if force == null else bool(force)
	_log_panel_box.visible = want
	if want:
		_log_panel_box.position = (size - _log_panel_box.size) * 0.5
		_log.scroll_to_line(maxi(0, _log.get_line_count() - 1))

## Стопка карт: несколько смещённых листов и крупное число поверх.
## Словом «Колода: 12» это читалось как строчка настроек; рисунком — как
## предмет на столе, и число видно, не приглядываясь.
func _pile(title: String, tint: Color, worn: bool) -> Array:
	var col := UI.vbox(3)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(88, 96)
	for i in 3:
		var sheet := Panel.new()
		sheet.position = Vector2(i * 5, (2 - i) * 5)
		sheet.size = Vector2(70, 84)
		sheet.custom_minimum_size = Vector2(70, 84)
		sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.GROUND.lightened(0.03 * i) if worn else Palette.GROUND_2.lightened(0.05 * i)
		sb.border_color = Color(tint, 0.45 + 0.18 * i)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(5)
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 6
		sheet.add_theme_stylebox_override("panel", sb)
		holder.add_child(sheet)
	var n := UI.named("0", 28, Palette.BONE)
	n.position = Vector2(10, 28)
	n.size = Vector2(70, 34)
	n.custom_minimum_size = Vector2(70, 34)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(n)
	col.add_child(holder)
	var cap := UI.caption(title)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	return [col, n]

func _make_flow(sep: int = 8) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	return f

## Полоса здоровья + щит брони поверх неё.
##
## Броня раньше пряталась среди прочих плашек статуса, хотя это самое важное
## число после здоровья: именно оно решает, пройдёт удар или нет. Щит слева
## от полосы виден сразу и не требует чтения.
func _make_bar(fill: Color, width: int = 280) -> Array:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, 26)
	var bar := ProgressBar.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.max_value = 100
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("1a1622")
	bg.border_color = Palette.EDGE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	holder.add_child(bar)
	var text := UI.label("", UI.SMALL, Palette.BONE)
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	holder.add_child(text)

	# щит брони: круг с числом у левого края полосы
	var shield := Control.new()
	shield.custom_minimum_size = Vector2(30, 30)
	shield.position = Vector2(-6, -1)
	shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield.visible = false
	var disc := Panel.new()
	disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color("2a3546")
	dsb.border_color = Color("9fd0ef")
	dsb.set_border_width_all(2)
	dsb.set_corner_radius_all(15)
	disc.add_theme_stylebox_override("panel", dsb)
	shield.add_child(disc)
	var n := UI.label("", UI.SMALL + 1, Color("cfe6f6"))
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shield.add_child(n)
	holder.add_child(shield)

	return [bar, text, holder, shield, n]

# ────────────────────────────────────────── запуск боя

func start_fight(run: Run, foe: Dictionary) -> void:
	combat = Combat.new()
	combat.logged.connect(_on_log)
	combat.changed.connect(_refresh)
	combat.foe_damaged.connect(_on_foe_damaged)
	combat.player_damaged.connect(_on_player_damaged)
	_hero_art.set_art("seeker", Palette.BRASS)
	combat.player_blocked.connect(func(n): FloatingText.spawn(_hero_fx, "+%d" % n, Color("9fd0ef"), Vector2(80, 60), 24))
	combat.power_triggered.connect(func(): FloatingText.spawn(_foe_fx, "МОЩЬ", Palette.BRASS, Vector2(130, 96), 24))
	combat.fight_over.connect(func(won): fight_finished.emit(won))
	_log.clear()
	_die_views.clear()
	selected_index = -1
	assigned.clear()
	_tray.clear_all()
	combat.setup(run.bag, run.deck, run.hp, run.max_hp, foe, run.relics)
	_rebuild_move_book()

func _on_log(text: String, kind: String) -> void:
	var color := Palette.BONE_DIM
	match kind:
		"dmg": color = Color("f0a08e")
		"block": color = Color("9fd0ef")
		"good": color = Color("9fd8a8")
		"power": color = Palette.BRASS
		"enemy": color = Palette.BRASS
	_log.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text])

func _shake_for(amount: int) -> float:
	if amount >= 20:
		return SHAKE_BIG
	elif amount >= 8:
		return SHAKE_MID
	return SHAKE_SMALL

func _on_foe_damaged(amount: int) -> void:
	FloatingText.spawn(_foe_fx, str(amount), Color("f2795f"), Vector2(120 + randf() * 90, 150))
	if is_instance_valid(_foe_art):
		_foe_art.hit()
		FloatingText.shake(_foe_art, _shake_for(amount))

func _on_player_damaged(amount: int) -> void:
	if amount <= 0:
		FloatingText.spawn(_hero_fx, "блок", Color("9fd0ef"), Vector2(70, 60), 22)
		return
	FloatingText.spawn(_hero_fx, "−%d" % amount, Color("f2795f"), Vector2(60 + randf() * 60, 50), 28)
	if is_instance_valid(_hero_art):
		_hero_art.hit()
		FloatingText.shake(_hero_art, _shake_for(amount))

# ────────────────────────────────────────── ввод

## Горячие клавиши.
##
## 1…9 — выбрать карту, Enter — бросить всё, что просит карта,
## Пробел — конец хода, R — собраться, Esc — отменить выбор.
## Смысл не в скорости: игра, где каждый ход надо трижды прицелиться мышью,
## утомляет к третьему акту, и это была одна из жалоб после плейтеста.
func _unhandled_key_input(event: InputEvent) -> void:
	if combat == null or combat.finished or not is_visible_in_tree():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		if _log_panel_box != null and _log_panel_box.visible:
			_toggle_log(false)
		else:
			_clear_selection()
		accept_event()
		return
	if busy or _tray.is_busy():
		return
	if key >= KEY_1 and key <= KEY_9:
		_on_card_clicked(int(key) - int(KEY_1))
		accept_event()
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		if _staged_full():
			_throw_all()
			accept_event()
	elif key == KEY_SPACE:
		combat.end_turn()
		accept_event()
	elif key == KEY_R:
		if combat.has_cooling_dice():
			combat.regroup()
			accept_event()
	elif key == KEY_TAB:
		_toggle_log()
		accept_event()

func _selected_card_id() -> String:
	if combat == null or selected_index < 0 or selected_index >= combat.hand.size():
		return ""
	return str(combat.hand[selected_index])

func _on_card_clicked(index: int) -> void:
	if busy or combat == null or combat.finished or _tray.is_busy():
		return
	if selected_index == index:
		_clear_selection()
		return
	if index < 0 or index >= combat.hand.size():
		return
	if not combat.can_play(str(combat.hand[index])):
		# карта не оплачивается — подсветим мешочек, а не промолчим
		FloatingText.spawn(_hero_fx, "нет готовых кубиков", Palette.BLOOD, Vector2(40, 90), 18)
		return
	selected_index = index
	assigned.clear()
	staged.clear()
	_tray.clear_all()
	_refresh()

func _clear_selection() -> void:
	selected_index = -1
	assigned.clear()
	staged.clear()
	_tray.clear_all()
	_refresh()

## Клик по кубику — отбор в горсть, а не бросок.
##
## Раньше клик кидал сразу, и карта на три кубика распадалась на три броска,
## между которыми уже ничего не поменять. Теперь щелчком набирают горсть,
## щелчком по выбранному — возвращают обратно, и только собранная горсть
## летит на сукно.
func _toggle_stage(die: Die) -> void:
	if busy or _tray.is_busy():
		return
	var sel := _selected_card_id()
	if sel == "":
		return
	var idx := staged.find(die)
	if idx >= 0:
		staged.remove_at(idx)
		_refresh()
		return
	var need := int(DB.card(sel).get("dice", 1))
	if staged.size() + assigned.size() >= need:
		return
	staged.append(die)
	_refresh()

## Собрана ли горсть целиком — от этого зависит, светится ли кнопка броска.
func _staged_full() -> bool:
	var sel := _selected_card_id()
	if sel == "":
		return false
	return staged.size() + assigned.size() >= int(DB.card(sel).get("dice", 1)) \
		and not staged.is_empty()

func _on_drag_started(die: Die) -> void:
	if busy or _selected_card_id() == "" or _tray.is_busy():
		return
	var card := DB.card(_selected_card_id())
	if die.cooldown > 0 or die.broken:
		return
	if die.sides < int(card.get("min_faces", 0)):
		return
	for a in assigned:
		if a.die.id == die.id:
			return
	if staged.size() + assigned.size() >= int(card.get("dice", 1)) and not staged.has(die):
		return
	# потянули кубик, который ещё не в горсти — считаем, что игрок его выбрал
	var idx := staged.find(die)
	if idx >= 0:
		staged.remove_at(idx)
	# кубик уже брошен в этом ходу — он держит своё число, кидать нечего
	if die.is_locked():
		_on_die_thrown(die, die.rolled)
		return
	_tray.grab(die, _tray.get_local_mouse_position())

## «Бросить всё» — отправить собранную горсть на сукно.
##
## Кнопка не выбирает кубики за игрока: она кидает ровно те, что он отобрал.
## Пока горсть неполная, кнопка погашена — так видно, что от тебя ещё ждут
## решения, а не что игра зависла.
func _throw_all() -> void:
	if busy or combat == null or combat.finished or not _staged_full():
		return
	var batch := staged.duplicate()
	for die in batch:
		if not staged.has(die):
			continue
		await _throw_one(die)
		if busy or combat == null or combat.finished:
			return

## Кубики, которыми можно оплатить выбранную карту прямо сейчас.
func _pickable_dice() -> Array:
	var sel := _selected_card_id()
	if sel == "":
		return []
	var card := DB.card(sel)
	var out: Array = []
	for d in combat.bag:
		if not d.is_ready():
			continue
		if d.sides < int(card.get("min_faces", 0)) and not d.has_quirk("hollow"):
			continue
		if bool(card.get("require_element", false)) and not d.suits(str(card.get("element", "none"))):
			continue
		var taken := false
		for a in assigned:
			if a.die.id == d.id:
				taken = true
		if not taken:
			out.append(d)
	return out

## Один бросок без перетаскивания — по клику или из «бросить всё».
func _throw_one(die: Die) -> void:
	var idx := staged.find(die)
	if idx >= 0:
		staged.remove_at(idx)
	if die.is_locked():
		_on_die_thrown(die, die.rolled)
		return
	_tray.toss(die)
	while _tray.is_busy():
		await get_tree().process_frame

func _on_die_thrown(die: Die, value: int) -> void:
	# Физический бросок даёт голую грань. Свойства кубика применяются здесь,
	# иначе они работали бы только у «виртуального» броска, а игрок видел бы,
	# как тяжёлый d12 выбрасывает единицу вопреки собственному тексту.
	if not die.is_locked():
		value = combat.apply_quirks(die, value)
	die.rolled = value
	assigned.append({"die": die, "value": value})
	var view: DieView = _die_views.get(die.id)
	if view:
		view.value = value
		view.refresh()
	_refresh_slots()

	var card_id := _selected_card_id()
	if card_id == "":
		return
	var need := int(DB.card(card_id).get("dice", 1))
	if assigned.size() >= need:
		busy = true
		await get_tree().create_timer(0.55).timeout
		var dice: Array = []
		var rolls: Array = []
		for a in assigned:
			dice.append(a.die)
			rolls.append(a.value)
		selected_index = -1
		assigned.clear()
		busy = false
		_tray.clear_all()
		combat.play_card(card_id, dice, rolls)

# ────────────────────────────────────────── отрисовка

## Смысл иконки намерения и её размер.
## В Slay the Spire значок атаки растёт вместе с уроном — угрозу видно
## ещё до того, как прочитал число. Здесь то же самое: одна иконка,
## но её размер зависит от того, сколько прилетит.
func _intent_kind(act: Dictionary) -> String:
	var kind := str(act.get("kind", "aggro"))
	if act.has("damage"):
		return "attack"
	if kind == "hex":
		return "hex"
	return "defend"

func _intent_color(act: Dictionary) -> Color:
	match _intent_kind(act):
		"defend": return Color("9fd0ef")
		"hex": return Color("c9a8e8")
	return Color("f0a08e")

func _intent_size(act: Dictionary) -> float:
	if not act.has("damage"):
		return 22.0
	var dmg := int(act.get("damage_total", int(act.get("damage", 0)) * int(act.get("times", 1))))
	return clampf(16.0 + dmg * 0.55, 16.0, 34.0)

## Запасной значок, если иконок в проекте нет.
func _intent_glyph(act: Dictionary) -> String:
	match _intent_kind(act):
		"defend": return "▦"
		"hex": return "◆"
	var dmg := int(act.get("damage_total", int(act.get("damage", 0)) * int(act.get("times", 1))))
	return "❯".repeat(clampi(int(dmg / 6.0) + 1, 1, 5))

## Приёмы врага — в подсказку по наведению.
##
## Панель «что он умеет» появилась не просто так: без неё намерение читается
## как случайность. Но она статична, а место занимала посреди экрана.
## Подсказка сохраняет всю информацию и не отнимает ни пикселя.
func _rebuild_move_book() -> void:
	if combat == null:
		return
	var lines: Array = []
	lines.append(combat.foe_name)
	var tax := combat.foe_tax
	if not tax.is_empty():
		lines.append("%s — %s" % [str(tax.get("name", "")), str(tax.get("text", ""))])
		_foe_tax.text = "%s — %s" % [str(tax.get("name", "")), str(tax.get("text", ""))]
		_foe_tax.visible = true
	else:
		_foe_tax.text = ""
		_foe_tax.visible = false
	if combat.foe_note != "":
		lines.append(combat.foe_note)
	lines.append("")
	lines.append("ЧТО ОН УМЕЕТ")
	for entry in combat.move_book():
		lines.append("· " + str(entry.text))
	var tip := "\n".join(lines)
	if _foe_column != null:
		_foe_column.tooltip_text = tip
	if _foe_art != null:
		_foe_art.tooltip_text = tip

func _refresh() -> void:
	if combat == null:
		return
	var act := combat.resolved_action()
	var kc := _intent_color(act)
	for c in _intent_icon_slot.get_children():
		c.queue_free()
	var icon := Icons.make(_intent_kind(act), _intent_size(act), kc)
	var text := combat.intent_text()
	if icon:
		_intent_icon_slot.add_child(icon)
		_intent_label.text = text
	else:
		_intent_label.text = "%s  %s" % [_intent_glyph(act), text]
	_intent_label.add_theme_color_override("font_color", kc)
	var isb: StyleBoxFlat = _intent_box.get_theme_stylebox("panel")
	isb.border_color = Color(kc, 0.6)

	_foe_name.text = combat.foe_name
	if _foe_art.art_id != combat.foe_art:
		_foe_art.set_art(combat.foe_art, Palette.BLOOD)

	_foe_hp_bar.value = 100.0 * max(0, combat.foe_hp) / max(1, combat.foe_max_hp)
	_foe_hp_text.text = "%d / %d" % [max(0, combat.foe_hp), combat.foe_max_hp]
	_foe_hp_big.text = str(max(0, combat.foe_hp))
	_hp_bar.value = 100.0 * max(0, combat.hp) / max(1, combat.max_hp)
	_hp_text.text = "%d / %d" % [max(0, combat.hp), combat.max_hp]
	_hp_big.text = str(max(0, combat.hp))
	# здоровье краснеет заранее, а не в момент смерти
	var share := float(max(0, combat.hp)) / float(max(1, combat.max_hp))
	_hp_big.add_theme_color_override("font_color",
		Palette.BLOOD if share < 0.3 else (Palette.BRASS if share < 0.6 else Palette.BONE))

	_fill_stats(_foe_stats, [
		["Сила +%d" % combat.foe_strength, combat.foe_strength > 0, Color("f0a08e"), "strength"],
		["Шипы %d" % combat.foe_thorns, combat.foe_thorns > 0, Color("e0b46a"), "thorns"],
		["Ожог %d" % combat.foe_burn, combat.foe_burn > 0, Color("e08a4a"), "fire"],
		["Яд %d" % combat.foe_poison, combat.foe_poison > 0, Color("9fd8a8"), "poison"],
		["Уязвимость %d" % combat.foe_vulnerable, combat.foe_vulnerable > 0, Color("f0a08e"), "vulnerable"],
		["Слабость −%d (%d)" % [combat.foe_weak_amount, combat.foe_weak_turns], combat.foe_weak_turns > 0, Color("c9a8e8"), "weak"],
		["Заморожен", combat.foe_frozen, Color("bfe5ff"), "frozen"],
	])
	_fill_stats(_hero_stats, [
		# Потолок возврата — такой же ресурс хода, как энергия в колодостроях,
		# и прятать его нельзя: без него игрок читает «остудить не вышло» как
		# поломку, а не как «на этот ход ты уже всё вернул».
		["Возврат %d" % combat.refresh_left, true, Palette.BRASS_DIM, "chest"],
		["Сила +%d" % combat.strength, combat.strength > 0, Palette.BRASS, "strength"],
		["Шипы %d" % combat.thorns, combat.thorns > 0, Color("e0b46a"), "thorns"],
		["Уязвимость %d" % combat.vulnerable, combat.vulnerable > 0, Color("f0a08e"), "vulnerable"],
		["Слабость −%d (%d)" % [combat.weak_amount, combat.weak_turns], combat.weak_turns > 0, Color("c9a8e8"), "weak"],
		["Блок не сгорает", combat.block_retained or combat.block_retained_once, Color("9fd0ef"), "block"],
	])

	# щит брони: блок и броня — одно и то же для игрока («сколько удара
	# съест»), поэтому и показываются одним числом
	var hero_guard := combat.block
	_hero_shield.visible = hero_guard > 0
	_hero_shield_n.text = str(hero_guard)
	var foe_guard := combat.foe_block + combat.foe_plated
	_foe_shield.visible = foe_guard > 0
	_foe_shield_n.text = str(foe_guard)

	if _log_panel_box != null and _log_panel_box.visible:
		_log.scroll_to_line(maxi(0, _log.get_line_count() - 1))
	_refresh_dice()
	_refresh_slots()
	_refresh_hand()
	_draw_n.text = str(combat.draw_pile.size())
	_disc_n.text = str(combat.discard_pile.size())
	_refresh_preview()
	_end_btn.disabled = busy or _tray.is_busy()
	_regroup_btn.disabled = busy or _tray.is_busy() or not combat.has_cooling_dice()
	var has_sel := _selected_card_id() != "" and not busy
	_cancel_btn.visible = has_sel
	_throw_all_btn.visible = has_sel
	_throw_all_btn.disabled = _tray.is_busy() or not _staged_full()

## Предпросмотр прямо на сукне: слева — что получишь ты, справа — что
## достанется врагу. Пока карта не выбрана, поле пустое и на нём стоит
## приглашение бросить.
##
## Раньше исход был написан мелким текстом на кубике в мешочке, то есть в
## стороне от места, куда игрок смотрит. Решение принимается над столом —
## значит и цифры должны висеть там.
func _refresh_preview() -> void:
	for c in _preview_mine.get_children():
		c.queue_free()
	for c in _preview_theirs.get_children():
		c.queue_free()
	var sel := _selected_card_id()
	if sel == "":
		return
	var dice: Array = []
	for a in assigned:
		dice.append(a.die)
	if dice.is_empty():
		return
	var p := combat.preview(sel, dice)
	if p.is_empty():
		return
	var op := str(p.op)
	var lo := int(p.min)
	var hi := int(p.max)
	var word := Combat.preview_word(op)
	var mine := op in ["block", "heal"]
	var into: VBoxContainer = _preview_mine if mine else _preview_theirs
	var tint: Color = Color("9fd0ef") if op == "block" else (Color("9fd8a8") if op in ["heal", "poison"] else Color("f0a08e"))
	var sign := "+" if mine else "−"
	var value := str(lo) if lo == hi else "%d–%d" % [lo, hi]
	var big := UI.named("%s%s" % [sign, value], 34, tint)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	into.add_child(big)
	var cap := UI.label(word, UI.SMALL, Color(tint, 0.8))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	into.add_child(cap)

func _fill_stats(row: HFlowContainer, entries: Array) -> void:
	for c in row.get_children():
		c.queue_free()
	for e in entries:
		if e[1]:
			row.add_child(UI.chip(str(e[0]), e[2], str(e[3]) if e.size() > 3 else ""))

func _refresh_dice() -> void:
	for c in _dice_row.get_children():
		c.queue_free()
	for c in _special_row.get_children():
		c.queue_free()
	_die_views.clear()
	var sel := _selected_card_id()
	var card := DB.card(sel) if sel != "" else {}

	var normal := 0
	var special := 0
	for d in combat.bag:
		var v := DieView.new(d)
		_die_views[d.id] = v
		var used = null
		for a in assigned:
			if a.die.id == d.id:
				used = a
		if used != null:
			v.value = used.value
		elif not card.is_empty() and d.is_ready() and (d.sides >= int(card.get("min_faces", 0)) or d.has_quirk("hollow")) \
			 and (staged.has(d) or staged.size() + assigned.size() < int(card.get("dice", 1))):
			v.pickable = true
			v.draggable = true
			v.drag_started.connect(_on_drag_started)
			# клик отбирает кубик в горсть; бросок — отдельным действием
			v.staged = staged.has(d)
			v.clicked.connect(func(_d): _toggle_stage(d))
			# показываем исход ДО оплаты — иначе игрок платит вслепую
			var p := combat.preview(sel, [d])
			if not p.is_empty():
				var word := Combat.preview_word(str(p.op))
				v.preview = "%s %d–%d" % [word, int(p.min), int(p.max)]
		elif not card.is_empty():
			v.dimmed = true
		# кубик со свойством уходит на свою полку
		if d.quirk != "":
			_special_row.add_child(v)
			special += 1
		else:
			_dice_row.add_child(v)
			normal += 1
	_place_racks(normal, special)

## Подсказка на стойке — единственный текстовый канал про кубики.
##
## На сукне надпись стояла ровно там, куда игрок целится броском, и мешала
## смотреть на сам бросок. Всё, что нужно сказать, помещается под рукой.
func _refresh_slots() -> void:
	var sel := _selected_card_id()
	if sel == "":
		_hint.text = "Выбери карту — потом кубики"
		return
	var card := DB.card(sel)
	var need := int(card.get("dice", 1))
	var picked := staged.size() + assigned.size()
	var left := need - picked
	if left > 0:
		_hint.text = "«%s»: выбери ещё %d %s" % [
			str(card.get("name", "")), left, "кубик" if left == 1 else "кубика"]
	elif not staged.is_empty():
		_hint.text = "Горсть собрана — бросай"
	else:
		_hint.text = "Бросок принят"

func _refresh_hand() -> void:
	var ids: Array = []
	var flags: Array = []
	for card_id in combat.hand:
		ids.append(card_id)
		flags.append(combat.can_play(str(card_id)))
	_hand.set_hand(ids, flags, selected_index)
	# гнёзда на выбранной карте закрашиваются по мере броска: «сколько ещё
	# надо» видно на самой карте, а не в отдельной строке
	await get_tree().process_frame
	var v := _hand.card_at(selected_index)
	if v != null:
		v.set_filled(assigned.size())
