class_name DieView
extends Control
## Кубик на экране. Показывает тип, выпавшее значение, порог Мощи и состояние.

signal clicked(die: Die)
signal drag_started(die: Die)

const SIZE := Vector2(84, 82)

var die: Die
var value: int = -1          ## что выпало (-1 = ещё не бросали)
var pickable: bool = false
var draggable: bool = false   ## можно вытащить в лоток мышью
var dimmed: bool = false
## Кубик отобран под карту, но ещё не брошен. Без явной пометки горсть
## невидима: игрок не понимает, сколько уже выбрал и чего от него ждут.
var staged: bool = false

var _bg: Panel
var _face: Label
var _value: Label
var _state: Label
var _thr: Label
var _spin: Tween
var preview: String = ""   ## что выйдет, если оплатить карту этим кубиком

func _init(p_die: Die) -> void:
	die = p_die
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = SIZE * 0.5

func _ready() -> void:
	_bg = Panel.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Водяной знак — силуэт кубика под текстом. На стойке кубики должны
	# читаться кубиками с одного взгляда, а не плашками с подписями.
	var die_mark := Icons.make("card_dice", 46, Color(Palette.element_color(die.element), 0.16))
	if die_mark:
		die_mark.position = Vector2((SIZE.x - 46) * 0.5, (SIZE.y - 46) * 0.5)
		die_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(die_mark)

	var col := UI.vbox(0)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	# перезарядка стоит прямо в названии: сколько ходов кубик будет молчать,
	# надо знать ДО броска — это половина решения, каким кубиком платить
	_face = UI.label("%s ↻%d" % [die.label(), _cool_len()], 12, Palette.BONE_DIM)
	_face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_face)

	_value = UI.label("", 24, Palette.BONE)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.custom_minimum_size.y = 26
	col.add_child(_value)

	_state = UI.label("", 10, Palette.MUTED)
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_state)

	# «Жёлтая цифра в углу» раньше ничего не сообщала. Теперь рядом с ней
	# стоит значок Мощи, и плашка читается как «Мощь с 15».
	var thr_row := UI.hbox(2)
	thr_row.position = Vector2(SIZE.x - 30, 3)
	thr_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thr_icon := Icons.make("power_eye", 10, Palette.BRASS)
	if thr_icon:
		thr_row.add_child(thr_icon)
	_thr = UI.label(str(die.power_threshold()), 10, Palette.BRASS)
	_thr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thr_row.add_child(_thr)
	add_child(thr_row)



	# особый кубик помечается точкой в углу и объясняется подсказкой:
	# свойство важнее числа граней, но места на плашке под текст нет
	if die.quirk != "":
		var mark := Panel.new()
		mark.custom_minimum_size = Vector2(8, 8)
		mark.size = Vector2(8, 8)
		mark.position = Vector2(5, 5)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var msb := StyleBoxFlat.new()
		msb.bg_color = Palette.CANDLE
		msb.border_color = Color(Palette.INK, 0.5)
		msb.set_border_width_all(1)
		msb.set_corner_radius_all(4)
		mark.add_theme_stylebox_override("panel", msb)
		add_child(mark)

	tooltip_text = _hint()

	refresh()

## Сколько ходов кубик будет остывать с учётом его свойств.
func _cool_len() -> int:
	var n := die.cooldown_max
	if die.has_quirk("swift"):
		n -= 1
	return maxi(1, n)

## Подсказка кубика: стихия, отклик и особое свойство.
func _hint() -> String:
	var parts: Array = []
	parts.append("%s · %s" % [die.full_label(), Palette.element_name(die.element)])
	if die.quirk != "":
		parts.append("%s: %s" % [die.quirk_name().capitalize(), die.quirk_text()])
	var echo := str(Palette.RESONANCE.get(die.element, ""))
	if echo != "":
		parts.append("Отклик стихии (когда стихия кубика совпала со стихией карты):\n" + echo)
	parts.append("Мощь с %d: бросок не ниже этого числа включает усиленный эффект карты.\nПосле броска остывает %d х." % [die.power_threshold(), _cool_len()])
	return "\n\n".join(parts)

func refresh() -> void:
	if _bg == null:
		return
	# число, закреплённое за кубиком в этом ходу, показываем всегда:
	# игрок должен видеть, что переброса не будет
	if value < 0 and die.is_locked():
		value = die.rolled
	var tint := Palette.element_color(die.element)
	var fill := Palette.RAISED.lerp(tint, 0.16)
	var border := tint
	var alpha := 1.0

	if die.broken:
		_state.text = "сломан"
		alpha = 0.25
		border = Palette.BLOOD
	elif value >= 0:
		_state.text = "закреплён"
		border = Palette.BRASS if DB.is_power(value, die.sides) else tint
	elif die.cooldown > 0:
		_state.text = "ещё %d" % die.cooldown
		alpha = 0.34
	else:
		_state.text = "готов"

	if dimmed and value < 0:
		alpha = min(alpha, 0.35)

	# Отобранный кубик поднят и обведён латунью: горсть должна быть видна
	# сразу, иначе непонятно, сколько уже выбрано и чего ждёт кнопка броска.
	if staged and value < 0:
		_state.text = "в горсти"
		border = Palette.BRASS
		fill = Palette.RAISED.lerp(Palette.BRASS, 0.22)
		alpha = 1.0

	if preview != "" and value < 0:
		_state.text = preview
		_state.add_theme_color_override("font_color", Palette.BRASS)
	else:
		_state.add_theme_color_override("font_color", Palette.MUTED)
	_value.text = "" if value < 0 else str(value)
	modulate.a = alpha

	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(3 if staged else (2 if (value >= 0 and DB.is_power(value, die.sides)) else 1))
	sb.set_corner_radius_all(3)
	_bg.add_theme_stylebox_override("panel", sb)

## Анимация броска: цифры мелькают, кубик подрагивает, потом останавливается.
func roll_to(final_value: int, duration: float = 0.42) -> void:
	value = -1
	refresh()
	if _spin:
		_spin.kill()
	_spin = create_tween()
	_spin.tween_property(self, "rotation", deg_to_rad(-9), duration * 0.25)
	_spin.tween_property(self, "rotation", deg_to_rad(8), duration * 0.28)
	_spin.tween_property(self, "rotation", deg_to_rad(-4), duration * 0.25)
	_spin.tween_property(self, "rotation", 0.0, duration * 0.22)
	var flicker := create_tween()
	flicker.set_loops(int(duration / 0.055))
	flicker.tween_callback(func():
		if is_instance_valid(_value):
			_value.text = str(randi_range(1, die.sides))
	).set_delay(0.055)
	await get_tree().create_timer(duration).timeout
	value = final_value
	refresh()
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2(1.16, 1.16), 0.08)
	pop.tween_property(self, "scale", Vector2.ONE, 0.12)

## Два способа сделать одно и то же.
##
## Потянул — кубик едет за курсором, и бросок получается свой, с размахом.
## Просто щёлкнул — кубик летит сам. Второй способ появился после плейтеста:
## тащить каждый кубик рукой красиво первые полчаса, дальше это работа.
## Отличаем одно от другого по тому, сдвинулась ли мышь после нажатия.
const DRAG_SLOP := 6.0
var _press_at := Vector2.ZERO
var _pressed := false

func _gui_input(event: InputEvent) -> void:
	if not pickable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_at = event.global_position
			accept_event()
		else:
			if _pressed:
				_pressed = false
				clicked.emit(die)
				accept_event()
	elif event is InputEventMouseMotion and _pressed and draggable:
		if event.global_position.distance_to(_press_at) > DRAG_SLOP:
			_pressed = false
			drag_started.emit(die)
			accept_event()

func _notification_mouse_exit_drag() -> void:
	_pressed = false

func _notification(what: int) -> void:
	# позицию внутри контейнера трогать нельзя — он её пересчитает, поэтому масштаб
	if what == NOTIFICATION_MOUSE_ENTER and pickable:
		create_tween().tween_property(self, "scale", Vector2(1.08, 1.08), 0.1)
	elif what == NOTIFICATION_MOUSE_EXIT and pickable:
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.1)
