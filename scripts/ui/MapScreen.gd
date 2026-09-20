extends Control
## Карта подземелья. Ряды идут снизу вверх; доступны только комнаты,
## соединённые с текущей.

signal node_chosen(node: Dictionary)

var run: Run

var _grid: VBoxContainer
var _buttons: Array = []      # [{node, control}]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func setup(p_run: Run) -> void:
	run = p_run
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()

	var root := UI.vbox(8)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var head := UI.hbox(14)
	root.add_child(head)
	var title_col := UI.vbox(0)
	title_col.add_child(UI.label("Акт %d · %s" % [run.map.act_index + 1, run.map.act_title()], UI.H2, Palette.BONE))
	var rule := run.act_rule()
	var rule_name := str(rule.get("name", ""))
	if rule_name != "" and rule.has("rest_penalty"):
		# правило акта надо читать ДО первого боя, а не выяснять по трупам
		title_col.add_child(UI.label("Правило акта: " + rule_name, UI.SMALL + 1, Palette.BRASS))
	else:
		title_col.add_child(UI.caption("куда дальше"))
	head.add_child(title_col)
	head.add_child(UI.spacer())
	head.add_child(UI.label("колода %d · кубиков %d · %d зол." % [run.deck.size(), run.bag.size(), run.gold],
		UI.SMALL, Palette.MUTED))

	var rule_text := str(rule.get("text", ""))
	if rule_text != "":
		root.add_child(UI.wrapped(rule_text, UI.SMALL + 1, Palette.BRASS, 760))
	root.add_child(UI.wrapped(
		"Элита и лавка дают больше, но стоят здоровья. Перед боссом акта всегда привал.",
		UI.SMALL + 1, Palette.BONE_DIM, 700))

	_grid = UI.vbox(6)
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_grid)

	var available := run.map.available()
	# рисуем сверху вниз: последний ряд карты — верхний на экране
	for r in range(run.map.rows.size() - 1, -1, -1):
		var row_box := UI.hbox(18)
		row_box.alignment = BoxContainer.ALIGNMENT_CENTER
		row_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_grid.add_child(row_box)
		for node in run.map.rows[r]:
			var is_available := false
			for a in available:
				if a.row == node.row and a.col == node.col:
					is_available = true
					break
			var ctrl := _node_button(node, is_available)
			row_box.add_child(ctrl)
			_buttons.append({"node": node, "control": ctrl})

	await get_tree().process_frame
	await get_tree().process_frame
	queue_redraw()

func _node_button(node: Dictionary, is_available: bool) -> Control:
	var type := str(node.type)
	var color := DungeonMap.type_color(type)
	var visited := bool(node.get("visited", false))

	var box := UI.panel(Palette.RAISED if visited else Palette.GROUND_2,
		color if is_available else Color(color, 0.30), 8)
	box.custom_minimum_size = Vector2(142, 56)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var col := UI.vbox(1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)

	var title_color := color if is_available else Color(color, 0.45)
	var title_row := UI.hbox(6)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := Icons.make("room_" + type, 20, title_color)
	if icon:
		title_row.add_child(icon)
	title_row.add_child(UI.label(DungeonMap.type_title(type), UI.SMALL + 2, title_color))
	col.add_child(title_row)

	var caption := ""
	if node.has("enemy"):
		caption = str(DB.enemy(str(node.enemy)).get("name", ""))
	elif type == "rest":
		caption = "восстановиться"
	elif type == "treasure":
		caption = "золото и кубик"
	elif type == "shop":
		caption = "потратить золото"
	elif type == "event":
		caption = "выбор и бросок"
	var sub := UI.label(caption, UI.TINY, Palette.MUTED if is_available else Color(Palette.MUTED, 0.5))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.clip_text = true
	col.add_child(sub)

	if is_available:
		var btn := Button.new()
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.flat = true
		btn.focus_mode = Control.FOCUS_ALL
		btn.add_theme_stylebox_override("focus", UI._btn_box(Color(0, 0, 0, 0), Palette.BRASS))
		btn.tooltip_text = _room_hint(type, node)
		btn.pressed.connect(func(): node_chosen.emit(node))
		var fill: Color = Palette.RAISED if visited else Palette.GROUND_2
		btn.mouse_entered.connect(func():
			box.add_theme_stylebox_override("panel", UI.panel_box(fill.lightened(0.06), Palette.BRASS, 8)))
		btn.mouse_exited.connect(func():
			box.add_theme_stylebox_override("panel", UI.panel_box(fill, color, 8)))
		box.add_child(btn)
	return box

## Линии переходов.
##
## Раньше они были кривыми, потому что начало и конец считались в разных
## системах координат: одно через глобальный прямоугольник, другое — через
## позицию внутри строки. Теперь обе точки берутся одинаково, из глобальных
## прямоугольников, и переводятся в локальные координаты одним и тем же
## преобразованием.
##
## Линия идёт кривой Безье с вертикальными «усами»: она выходит из комнаты
## строго вверх и входит в следующую строго снизу, поэтому не читается как
## случайно проведённая диагональ.
## Что ждёт в комнате. Висит на кнопке, а не на панели: кнопка лежит сверху
## и своей подсказкой перекрывает чужую.
func _room_hint(type: String, node: Dictionary) -> String:
	var lines: Array = [DungeonMap.type_title(type)]
	match type:
		"fight", "elite", "boss":
			var foe := DB.enemy(str(node.get("enemy", "")))
			lines.append(str(foe.get("name", "")))
			if str(foe.get("_", "")) != "":
				lines.append(str(foe.get("_")))
			lines.append("Здоровье: %d" % int(foe.get("hp", 0)))
			if type == "elite":
				lines.append("За элиту дают реликвию и заметно больше золота.")
		"rest":
			lines.append("Выспаться, заточить или убрать карту, обточить кубик.")
		"treasure":
			lines.append("Золото, реликвия и кубик на выбор.")
		"shop":
			lines.append("Карты, кубик с особым свойством, заточка и чистка колоды — за золото.")
		"event":
			lines.append("Выбор, иногда с проверкой броском.")
	return "\n\n".join(lines)

func _draw() -> void:
	if run == null or _buttons.is_empty():
		return
	var inv := get_global_transform().affine_inverse()
	var current := run.map.current()

	for entry in _buttons:
		var node: Dictionary = entry.node
		var from_ctrl: Control = entry.control
		if not is_instance_valid(from_ctrl):
			continue
		var from_rect := from_ctrl.get_global_rect()
		# ряды нарисованы сверху вниз, поэтому следующая комната — ВЫШЕ:
		# линия выходит из верхнего края
		var from_pos: Vector2 = inv * (from_rect.position + Vector2(from_rect.size.x * 0.5, 0.0))

		for c in node.get("next", []):
			var to_ctrl: Control = _control_at(int(node.row) + 1, int(c))
			if to_ctrl == null:
				continue
			var to_rect := to_ctrl.get_global_rect()
			var to_pos: Vector2 = inv * (to_rect.position + Vector2(to_rect.size.x * 0.5, to_rect.size.y))

			var walked := bool(node.get("visited", false))
			var live := (not current.is_empty()
				and int(current.get("row", -1)) == int(node.row)
				and int(current.get("col", -1)) == int(node.col))
			var color := Palette.EDGE
			var width := 1.5
			if walked:
				color = Palette.BRASS_DIM
				width = 2.0
			if live:
				color = Palette.BRASS
				width = 2.5
			_draw_link(from_pos, to_pos, color, width)

func _control_at(row: int, col: int) -> Control:
	for other in _buttons:
		var target: Dictionary = other.node
		if int(target.row) == row and int(target.col) == col:
			return other.control if is_instance_valid(other.control) else null
	return null

## Кривая Безье, выходящая вертикально с обоих концов.
func _draw_link(from_pos: Vector2, to_pos: Vector2, color: Color, width: float) -> void:
	var lift: float = clampf(absf(from_pos.y - to_pos.y) * 0.45, 12.0, 44.0)
	var c1 := from_pos + Vector2(0, -lift)
	var c2 := to_pos + Vector2(0, lift)
	var points := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var t := float(i) / float(steps)
		points.append(from_pos.bezier_interpolate(c1, c2, to_pos, t))
	draw_polyline(points, color, width, true)
