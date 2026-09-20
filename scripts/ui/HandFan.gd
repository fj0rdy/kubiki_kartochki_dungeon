class_name HandFan
extends Control
## Рука веером, как в Slay the Spire: карты перекрываются, наклонены к краям
## и приподняты по дуге. Числа взяты из разбора реализаций StS — наклон до
## 0.2 рад (11.5°), перекрытие 60 px, подъём дуги 40 px.
##
## Порядок отрисовки строго слева направо, наведённая карта поднимается наверх,
## иначе подъём читается как глюк.

signal card_clicked(index: int)

const ROT_MAX := 0.075          ## наклон к краям веера, рад
const MIN_GAP := 14.0          ## просвет между картами, когда рука помещается
const MIN_STEP := 74.0         ## насколько сдвигаются карты, когда уже не помещаются
const ARC_HEIGHT := 26.0
## Карта под курсором должна выходить из веера, а не тонуть в нём: подъём и
## увеличение заметно больше прежних, и оба идут плавно — резкий скачок
## читается как глюк, а не как отклик.
const HOVER_LIFT := 30.0
const HOVER_SCALE := 1.3
const EASE_TIME := 0.11

var _cards: Array = []          # CardView
var _hovered: int = -1
var _selected: int = -1
var _tweens: Array = []         # по одному на карту, чтобы анимации не дрались

func _ready() -> void:
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)

func set_hand(card_ids: Array, playable_flags: Array, selected_index: int) -> void:
	for c in _cards:
		c.queue_free()
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()
	_cards.clear()
	_hovered = -1
	_selected = selected_index
	if not is_node_ready():
		await ready

	for i in card_ids.size():
		var v := CardView.new(str(card_ids[i]))
		v.hover_lift = false
		v.playable = bool(playable_flags[i])
		v.selected = (i == selected_index)
		v.mouse_filter = Control.MOUSE_FILTER_STOP
		v.clicked.connect(func(_id): card_clicked.emit(i))
		v.mouse_entered.connect(func(): _hovered = i; _layout())
		v.mouse_exited.connect(func():
			if _hovered == i:
				_hovered = -1
			_layout())
		add_child(v)
		_cards.append(v)
		_tweens.append(null)
	# размер веера контейнер выставит только к следующему кадру —
	# раскладываем и сразу, и после него, иначе карты считаются по старому размеру
	_layout()
	call_deferred("_layout")

func _layout() -> void:
	var count := _cards.size()
	if count == 0:
		return

	# рука ужимается под окно, а не вылезает за него: масштаб считается от
	# доступной высоты. Интерфейс, который умеет только увеличиваться, —
	# типовая претензия к играм жанра.
	var need_h := CardView.SIZE.y + ARC_HEIGHT + HOVER_LIFT + 10.0
	var fit: float = clampf(size.y / maxf(need_h, 1.0), 0.42, 1.0)
	# жёсткий потолок: карта не может быть выше отведённого руке места, иначе
	# при полной руке нижний ряд уезжает за край экрана
	fit = minf(fit, maxf(0.42, (size.y - 14.0) / CardView.SIZE.y))

	var card_w := CardView.SIZE.x * fit
	var room := size.x - 24.0
	var step := card_w + MIN_GAP
	if count > 1 and card_w + step * (count - 1) > room:
		step = maxf(MIN_STEP * fit, (room - card_w) / float(count - 1))
	var total := card_w + step * (count - 1)
	var start_x := (size.x - total) * 0.5
	# запас снизу: наклонённая карта поворачивается вокруг нижнего края
	# и её дальний угол уходит ниже, чем прямая
	# карта наклонена и вращается вокруг нижнего края, поэтому дальний угол
	# уходит ниже прямой — оставляем на это запас, иначе низ руки срезается
	var base_y := size.y - CardView.SIZE.y * fit - 34.0

	for i in count:
		var v: CardView = _cards[i]
		var t := 0.0
		if count > 1:
			t = float(i) / float(count - 1) * 2.0 - 1.0
		var arc := (-ARC_HEIGHT * t * t + ARC_HEIGHT) * fit
		# выбранная карта поднимается вполовину: её и так видно по рамке,
		# а полный подъём наезжал на мешочек
		var hovered := (i == _hovered)
		var lifted := hovered or (i == _selected)
		var lift := 0.0
		if hovered:
			lift = HOVER_LIFT
		elif lifted:
			lift = HOVER_LIFT * 0.45
		v.pivot_offset = Vector2(CardView.SIZE.x * 0.5, CardView.SIZE.y)
		var want_rot := 0.0 if lifted else t * ROT_MAX
		var s := fit * (HOVER_SCALE if hovered else (1.12 if lifted else 1.0))
		var want_pos := Vector2(start_x + step * i, base_y - arc - lift * fit)
		_ease_to(i, v, want_pos, Vector2(s, s), want_rot)

	# порядок отрисовки: слева направо, поднятая карта поверх остальных
	for i in count:
		move_child(_cards[i], i)
	if _selected >= 0 and _selected < count:
		move_child(_cards[_selected], count - 1)
	if _hovered >= 0 and _hovered < count:
		move_child(_cards[_hovered], count - 1)

## Плавный переезд карты в новое положение. Отдельный твин на карту:
## общий твин на всю руку рвётся, когда курсор быстро идёт вдоль веера.
func _ease_to(i: int, v: CardView, pos: Vector2, scl: Vector2, rot: float) -> void:
	if i >= _tweens.size():
		return
	var old_tween: Tween = _tweens[i]
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	# первая раскладка — сразу на место, без анимации: иначе рука
	# «прилетает» из угла каждый ход
	if v.position == Vector2.ZERO and v.scale == Vector2.ONE:
		v.position = pos
		v.scale = scl
		v.rotation = rot
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "position", pos, EASE_TIME)
	tw.tween_property(v, "scale", scl, EASE_TIME)
	tw.tween_property(v, "rotation", rot, EASE_TIME)
	_tweens[i] = tw

## Карта по индексу — экрану боя нужно закрашивать на ней гнёзда под кубики.
func card_at(i: int) -> CardView:
	if i < 0 or i >= _cards.size():
		return null
	return _cards[i]
