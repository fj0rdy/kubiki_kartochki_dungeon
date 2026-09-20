extends Control
## Событие: текст, выбор, иногда — проверка броском.
##
## Проверка нарочно заставляет выбрать кубик из мешочка. Вне боя перезарядка
## не тратится, поэтому выбор здесь — чистая ставка на шанс: крупный кубик
## чаще проходит высокий порог. Это даёт билдам на больших кубиках выплату
## за пределами боя.

signal finished()

var run: Run
var event_id: String = ""

var _column: VBoxContainer
var _dice_row: HFlowContainer
var _outcome: VBoxContainer
var _stage_holder: Control
var _tray: DiceTray
var _pending_choice: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func setup(p_run: Run, p_event_id: String) -> void:
	run = p_run
	event_id = p_event_id
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var ev := DB.event(event_id)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var sheet := UI.panel(Palette.PANEL, Palette.EDGE, 26)
	sheet.custom_minimum_size.x = 660
	center.add_child(sheet)

	_column = UI.vbox(12)
	sheet.add_child(_column)

	_column.add_child(UI.label(str(ev.get("title", "Событие")), UI.H2, Palette.BRASS))
	_column.add_child(UI.wrapped(str(ev.get("text", "")), UI.BODY, Palette.BONE_DIM, 600))
	_column.add_child(UI.gap(4))

	for choice in ev.get("choices", []):
		var label := str(choice.get("label", "…"))
		if choice.has("check"):
			label += "   (порог %d)" % int(choice.check.get("threshold", 0))
		var b := UI.button(label)
		b.pressed.connect(_on_choice.bind(choice))
		_column.add_child(b)

	_stage_holder = Control.new()
	_stage_holder.custom_minimum_size = Vector2(0, 0)
	_column.add_child(_stage_holder)

	_dice_row = HFlowContainer.new()
	_dice_row.add_theme_constant_override("h_separation", 9)
	_dice_row.add_theme_constant_override("v_separation", 9)
	_column.add_child(_dice_row)

	_outcome = UI.vbox(8)
	_column.add_child(_outcome)

func _clear_choices() -> void:
	for c in _column.get_children():
		if c is Button:
			c.queue_free()

func _on_choice(choice: Dictionary) -> void:
	_clear_choices()
	if choice.has("check"):
		_pending_choice = choice
		_ask_for_die()
	else:
		_resolve(choice, str(choice.get("text", "")), choice.get("effects", []))

func _ask_for_die() -> void:
	var threshold := int(_pending_choice.check.get("threshold", 0))
	_outcome.add_child(UI.wrapped(
		"Выбери кубик и брось его в лоток. Нужно %d или больше." % threshold,
		UI.BODY, Palette.BRASS, 600))

	# лоток тот же, что в бою: кубик кидает игрок, а не анимация
	_stage_holder.custom_minimum_size = Vector2(560, 230)
	_tray = DiceTray.new()
	_tray.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tray.die_thrown.connect(_on_die_thrown)
	var frame := UI.panel(Color(Palette.GROUND, 0.72), Palette.EDGE, 6)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(_tray)
	_stage_holder.add_child(frame)

	for d in run.bag:
		var v := DieView.new(d)
		v.pickable = true
		v.draggable = true
		v.drag_started.connect(func(die): _tray.grab(die, _tray.get_local_mouse_position()))
		_dice_row.add_child(v)

func _on_die_thrown(die: Die, value: int) -> void:
	for c in _dice_row.get_children():
		c.queue_free()
	for c in _outcome.get_children():
		c.queue_free()
	await get_tree().create_timer(0.5).timeout

	var threshold := int(_pending_choice.check.get("threshold", 0))
	var success := value >= threshold
	var branch: Dictionary = _pending_choice.get("success" if success else "failure", {})
	_outcome.add_child(UI.label(
		"%s — выпало %d, нужно было %d" % ["Успех" if success else "Мимо", value, threshold],
		UI.H3, Palette.HEAL if success else Palette.BLOOD))
	_resolve(_pending_choice, str(branch.get("text", "")), branch.get("effects", []))

func _resolve(_choice: Dictionary, text: String, effects: Array) -> void:
	if text != "":
		_outcome.add_child(UI.wrapped(text, UI.BODY, Palette.BONE_DIM, 600))
	var lines := run.apply_effects(effects, run.rng)
	for line in lines:
		_outcome.add_child(UI.label("· " + line, UI.SMALL + 1, Palette.BONE))
	if lines.is_empty() and text == "":
		_outcome.add_child(UI.label("Ничего не произошло.", UI.SMALL + 1, Palette.MUTED))

	_outcome.add_child(UI.gap(8))
	var next := UI.button("Дальше", true)
	next.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	next.pressed.connect(func(): finished.emit())
	_outcome.add_child(next)
