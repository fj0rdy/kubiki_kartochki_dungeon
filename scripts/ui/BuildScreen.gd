extends Control
## Экран сборки перед забегом: мешочек слева, колода справа.
##
## Раньше и то и другое было списком подписей — «d10 · 3 оч» и кнопка
## «Ядовитый клинок». Собирать по ним нельзя: чтобы понять, что делает
## карта, приходилось наводиться на каждую и читать всплывающую плашку, а
## кубики отличались только числом в тексте. Теперь на экране лежат те же
## самые карты и кубики, что будут в бою: щёлкнул в пуле — предмет уехал в
## сборку, щёлкнул в сборке — вернулся обратно.
##
## Две колонки не случайны: мешочек и колода — два независимых набора с
## разными ограничениями (очки и слоты против числа карт), и мешать их в
## один список значит прятать, что именно сейчас закончилось.

signal run_requested(bag: Array, deck_id: String, deck: Array)
signal back_requested

var bag: Array = []                 # Array[Die]
var deck: Array = []                # Array[String]
var current_element: String = "fire"
var deck_id: String = ""

var _bag_row: HFlowContainer
var _bag_hint: Label
var _seal_hint: Label
var _shop_row: HFlowContainer
var _tabs_row: HFlowContainer
var _deck_tabs: HFlowContainer
var _deck_row: HFlowContainer
var _pool_row: HFlowContainer
var _deck_caption: Label
var _bag_caption: Label
var _stats_row: HBoxContainer
var _start_btn: Button
var _element_row: HFlowContainer

## Насколько уменьшены карты. В колоде — мельче, там важно видеть весь
## набор разом; в пуле — крупнее, там карту выбирают и читают.
const DECK_SCALE := 0.5
const POOL_SCALE := 0.62

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	var presets: Dictionary = DB.b("presets", {})
	if presets.size() > 1:
		_apply_preset(str(presets.keys()[1]))

func _build() -> void:
	var root := UI.vbox(8)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(UI.label("Сборка перед забегом", UI.H2, Palette.BONE))
	root.add_child(UI.wrapped(
		"Кубик не тратится насовсем — он уходит на перезарядку и возвращается через "
		+ "несколько ходов. Мелкие держат темп, крупные бьют больно. Неистраченные "
		+ "очки уходят в здоровье.", UI.SMALL + 1, Palette.BONE_DIM, 900))

	var columns := UI.hbox(14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	columns.add_child(_bag_column())
	columns.add_child(_deck_column())

	root.add_child(_bottom_bar())

# ─────────────────────────────────────────── мешочек

func _bag_column() -> Control:
	var col := UI.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 0.86

	_bag_caption = UI.caption("")
	col.add_child(_bag_caption)

	var bag_panel := UI.panel(Palette.GROUND_2, Palette.EDGE, 10)
	bag_panel.custom_minimum_size.y = 104
	col.add_child(bag_panel)
	_bag_row = _flow(9)
	bag_panel.add_child(_bag_row)

	_seal_hint = UI.wrapped("", UI.TINY + 1, Palette.BRASS, 620)
	col.add_child(_seal_hint)

	col.add_child(UI.gap(4))
	col.add_child(UI.caption("Стихия нового кубика"))
	_element_row = _flow(6)
	col.add_child(_element_row)

	col.add_child(UI.caption("Добавить кубик — нажми на нужный"))
	_shop_row = _flow(9)
	col.add_child(_shop_row)

	col.add_child(UI.gap(6))
	col.add_child(UI.caption("Что делают стихии"))
	var roles := ScrollContainer.new()
	roles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roles.custom_minimum_size.y = 96
	roles.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(roles)
	var roles_col := UI.vbox(5)
	roles_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roles.add_child(roles_col)
	for key in Palette.ELEMENTS.keys():
		if key == "none":
			continue
		roles_col.add_child(_element_role(str(key)))
	return col

## Строчка про стихию: работа на виду, цена — там же, но тише.
## Стихия без цены — не выбор, поэтому цена не уезжает в подсказку.
func _element_role(key: String) -> Control:
	var tint: Color = Palette.element_color(key)
	var row := UI.vbox(0)
	var line := UI.hbox(6)
	var pip := Panel.new()
	pip.custom_minimum_size = Vector2(7, 7)
	pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var psb := StyleBoxFlat.new()
	psb.bg_color = tint
	psb.set_corner_radius_all(4)
	pip.add_theme_stylebox_override("panel", psb)
	line.add_child(pip)
	line.add_child(UI.label(Palette.element_name(key), UI.TINY + 1, tint))
	line.add_child(UI.wrapped(Palette.element_job(key), UI.TINY + 1, Palette.BONE, 400))
	row.add_child(line)
	row.add_child(UI.wrapped("Цена: " + Palette.element_cost(key), UI.TINY, Palette.MUTED, 440))
	return row

func _refresh_element_tabs() -> void:
	for c in _element_row.get_children():
		c.queue_free()
	for key in Palette.ELEMENTS.keys():
		if key == "none":
			continue
		var tint: Color = Palette.element_color(str(key))
		var b := UI.button(Palette.element_name(str(key)), str(key) == current_element)
		if str(key) != current_element:
			b.add_theme_color_override("font_color", tint)
			b.add_theme_color_override("font_hover_color", tint)
		b.pressed.connect(func():
			current_element = str(key)
			_refresh())
		_element_row.add_child(b)

## Витрина кубиков: настоящие кубики, а не строчки прайса. Один и тот же
## d10 в витрине и в мешочке выглядит одинаково — значит, выбирая, игрок
## уже видит то, чем будет играть.
func _refresh_shop() -> void:
	for c in _shop_row.get_children():
		c.queue_free()
	var slots_left := bag.size() < int(DB.b("max_dice", 7))
	for sides in DB.die_types():
		var cost := DB.die_cost(int(sides))
		var die := Die.make(int(sides), current_element)
		var holder := UI.vbox(2)
		var v := DieView.new(die)
		var affordable: bool = slots_left and _cost() + cost <= int(DB.b("budget", 15))
		v.pickable = affordable
		v.tooltip_text = "d%d — %d очк., остывает %d хода\n\nПорог Мощи: %d" % [
			int(sides), cost, DB.die_cooldown(int(sides)), DB.power_threshold(int(sides))]
		if affordable:
			v.clicked.connect(func(_d):
				bag.append(Die.make(int(sides), current_element))
				_refresh())
		else:
			v.modulate.a = 0.35
		holder.add_child(v)
		var price := UI.label("%d оч." % cost, UI.TINY, Palette.BRASS if affordable else Palette.MUTED)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(price)
		_shop_row.add_child(holder)

func _refresh_bag() -> void:
	for c in _bag_row.get_children():
		c.queue_free()
	_bag_caption.text = ("МЕШОЧЕК — %d ИЗ %d СЛОТОВ · НАЖМИ НА КУБИК, ЧТОБЫ УБРАТЬ"
		% [bag.size(), int(DB.b("max_dice", 7))])
	if bag.is_empty():
		_bag_row.add_child(UI.label("Пусто — возьми хотя бы 3 кубика", UI.SMALL, Palette.MUTED))
		return
	for d in bag:
		var v := DieView.new(d)
		v.pickable = true
		v.clicked.connect(func(die):
			var at := bag.find(die)
			if at >= 0:
				bag.remove_at(at)
			_refresh())
		_bag_row.add_child(v)

# ─────────────────────────────────────────── колода

func _deck_column() -> Control:
	var col := UI.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.14

	_deck_caption = UI.caption("")
	col.add_child(_deck_caption)

	var deck_panel := UI.panel(Palette.GROUND_2, Palette.EDGE, 10)
	deck_panel.custom_minimum_size.y = 118
	col.add_child(deck_panel)
	_deck_row = _flow(6)
	deck_panel.add_child(_deck_row)

	col.add_child(UI.caption("Заготовка — быстрый старт, дальше меняй по карте"))
	_deck_tabs = _flow(6)
	_deck_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_deck_tabs)

	col.add_child(UI.caption("Пул — базовые и обычные карты. Нажми, чтобы добрать"))
	var pool := ScrollContainer.new()
	pool.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pool.custom_minimum_size.y = 170
	pool.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(pool)
	_pool_row = _flow(8)
	_pool_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool.add_child(_pool_row)
	return col

func _refresh_deck_tabs() -> void:
	for c in _deck_tabs.get_children():
		c.queue_free()
	for deck_name in DB.deck_names():
		var info := DB.deck_info(str(deck_name))
		var tint: Color = Palette.element_color(str(info.get("element", "none")))
		var b := UI.button(str(deck_name), str(deck_name) == deck_id)
		b.tooltip_text = str(info.get("text", ""))
		if str(deck_name) != deck_id:
			b.add_theme_color_override("font_color", tint)
			b.add_theme_color_override("font_hover_color", tint)
		b.pressed.connect(func(): _apply_deck_preset(str(deck_name)))
		_deck_tabs.add_child(b)
	var clear := UI.button("Очистить")
	clear.pressed.connect(func():
		deck.clear()
		deck_id = ""
		_refresh())
	_deck_tabs.add_child(clear)

## Заготовка — быстрый старт, а не приговор: карты после неё по-прежнему
## меняются по одной.
func _apply_deck_preset(id: String) -> void:
	deck_id = id
	deck = DB.starter_deck(id)
	_refresh()

func _refresh_deck() -> void:
	for c in _deck_row.get_children():
		c.queue_free()
	var limit := int(DB.b("deck_slots", 10))
	_deck_caption.text = ("КОЛОДА — %d ИЗ %d КАРТ · НАЖМИ НА КАРТУ, ЧТОБЫ УБРАТЬ"
		% [deck.size(), limit])
	if deck.is_empty():
		_deck_row.add_child(UI.label(
			"Пусто — возьми заготовку или набери карты из пула", UI.SMALL, Palette.MUTED))
		return
	var sorted := deck.duplicate()
	sorted.sort()
	for id in sorted:
		var holder := CardView.scaled(str(id), DECK_SCALE)
		var card := CardView.inner(holder)
		if card != null:
			card.clicked.connect(func(cid):
				var at := deck.find(cid)
				if at >= 0:
					deck.remove_at(at)
				deck_id = ""
				_refresh())
		_deck_row.add_child(holder)

## Пул стартовых карт: только базовые и обычные.
##
## Ограничение по редкости здесь не косметика. Пустить в стартовую колоду
## редкие — значит начать забег уже собранным, и весь смысл подземелья,
## искать карты, пропадает.
func _refresh_pool() -> void:
	for c in _pool_row.get_children():
		c.queue_free()
	var limit := int(DB.b("deck_slots", 10))
	var copies := int(DB.b("deck_max_copies", 4))
	var counts := {}
	for id in deck:
		counts[id] = int(counts.get(id, 0)) + 1

	var ids: Array = []
	for id in DB.card_ids():
		var r := str(DB.card(str(id)).get("rarity", ""))
		if r == "basic" or r == "common":
			ids.append(str(id))
	ids.sort_custom(func(a, b):
		var ea := str(DB.card(a).get("element", "none"))
		var eb := str(DB.card(b).get("element", "none"))
		if ea != eb:
			return ea < eb
		return str(DB.card(a).get("name", "")) < str(DB.card(b).get("name", "")))

	for id in ids:
		var used := int(counts.get(id, 0))
		var blocked := deck.size() >= limit or used >= copies
		var holder := CardView.scaled(str(id), POOL_SCALE)
		var card := CardView.inner(holder)
		if card != null:
			if blocked:
				card.playable = false
				card.refresh()
			else:
				card.clicked.connect(func(cid):
					deck.append(cid)
					deck_id = ""
					_refresh())
		# сколько таких уже в колоде — видно, не пересчитывая колоду глазами
		if used > 0:
			var badge := UI.named("×%d" % used, 15, Palette.BRASS)
			badge.position = Vector2(CardView.SIZE.x * POOL_SCALE - 26, 4)
			badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
			badge.add_theme_constant_override("shadow_offset_x", 1)
			badge.add_theme_constant_override("shadow_offset_y", 1)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(badge)
		_pool_row.add_child(holder)

# ─────────────────────────────────────────── низ экрана

## Нижняя полоса: выход слева, цифры посередине, старт справа.
## Кнопка старта стоит последней по ходу чтения — там, где её ищут, когда
## сборка закончена, а не в углу над пустым мешочком.
func _bottom_bar() -> Control:
	var bar := UI.panel(Palette.GROUND_2, Palette.EDGE_SOFT, 10)
	var row := UI.hbox(18)
	bar.add_child(row)

	var back := UI.button("Назад в меню")
	back.pressed.connect(func(): back_requested.emit())
	row.add_child(back)

	_stats_row = UI.hbox(20)
	_stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_stats_row)

	_start_btn = UI.button("В подземелье", true)
	_start_btn.custom_minimum_size = Vector2(200, 44)
	_start_btn.add_theme_font_size_override("font_size", UI.BODY + 1)
	_start_btn.pressed.connect(func(): run_requested.emit(bag, deck_id, deck))
	row.add_child(_start_btn)
	return bar

func _stat(key: String, value: String, warn: bool = false) -> void:
	var col := UI.vbox(1)
	col.add_child(UI.caption(key))
	col.add_child(UI.label(value, 21, Palette.BLOOD if warn else Palette.BONE))
	_stats_row.add_child(col)

# ─────────────────────────────────────────── общее

func _flow(sep: int) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	return f

func _apply_preset(preset_name: String) -> void:
	var presets: Dictionary = DB.b("presets", {})
	if not presets.has(preset_name):
		return
	bag.clear()
	for entry in presets[preset_name]:
		bag.append(Die.make(int(entry[0]), str(entry[1])))
	# у каждого готового мешочка есть колода, с которой он задуман
	var pair: Dictionary = DB.b("preset_decks", {})
	if pair.has(preset_name):
		deck_id = str(pair[preset_name])
		deck = DB.starter_deck(deck_id)
	_refresh()

func _refresh() -> void:
	_refresh_element_tabs()
	_refresh_shop()
	_refresh_bag()
	_refresh_deck_tabs()
	_refresh_deck()
	_refresh_pool()
	_seal_hint.text = _seal_progress()
	_seal_hint.visible = _seal_hint.text != ""

	for c in _stats_row.get_children():
		c.queue_free()
	var slots := int(DB.b("max_dice", 7))
	var budget := int(DB.b("budget", 15))
	var limit := int(DB.b("deck_slots", 10))
	_stat("Очки", "%d / %d" % [_cost(), budget])
	_stat("Слоты", "%d / %d" % [bag.size(), slots], bag.size() < 3)
	_stat("Карты", "%d / %d" % [deck.size(), limit], deck.size() < limit)
	_stat("Темп, карт/ход", "%.1f" % Run.tempo(bag))
	_stat("Здоровье", str(int(DB.b("base_hp", 70)) + Run.spare_hp(bag)))

	var ready := bag.size() >= 3 and deck.size() == limit
	_start_btn.disabled = not ready
	_start_btn.tooltip_text = "" if ready else "Нужно хотя бы 3 кубика и ровно %d карт" % limit

## Что даст мешочек, если добрать до трёх кубиков одной стихии.
## Печать — долгая цель забега, и решение о ней принимается ЗДЕСЬ.
func _seal_progress() -> String:
	var need := int(DB.b("seal_dice", 3))
	var counts := {}
	for d in bag:
		counts[d.element] = int(counts.get(d.element, 0)) + 1
	var parts: Array = []
	for element in DB.relics.get("seals", {}).keys():
		var n := int(counts.get(element, 0))
		if n <= 0:
			continue
		var rel := DB.relic(str(DB.relics["seals"][element]))
		var mark := "✔" if n >= need else "%d/%d" % [n, need]
		parts.append("%s %s" % [str(rel.get("name", element)), mark])
	if parts.is_empty():
		return ""
	return "Печати: " + "   ".join(parts)

func _cost() -> int:
	return Run.bag_cost(bag)
