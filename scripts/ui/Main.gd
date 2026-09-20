extends Control
## Корень игры: верхняя панель и переходы между экранами.
## Порядок: сборка → карта акта → комната → карта → … → босс → следующий акт.

const BuildScreenScript := preload("res://scripts/ui/BuildScreen.gd")
const CombatScreenScript := preload("res://scripts/ui/CombatScreen.gd")
const MapScreenScript := preload("res://scripts/ui/MapScreen.gd")
const EventScreenScript := preload("res://scripts/ui/EventScreen.gd")
const MenuScreenScript := preload("res://scripts/ui/MenuScreen.gd")
const GalleryScreenScript := preload("res://scripts/ui/GalleryScreen.gd")

var run: Run
var rng := RandomNumberGenerator.new()

var _content: MarginContainer
var _progress_chip: PanelContainer
var _progress_label: Label
var _hp_label: Label
var _gold_label: Label
var _deck_btn: Button
var _relic_shelf: HBoxContainer
var _restart_btn: Button
var _combat_screen: Control
var _overlays: Array = []          # стопка открытых оверлеев

func _ready() -> void:
	rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	add_child(Backdrop.new())

	var page := MarginContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("margin_left", 26)
	page.add_theme_constant_override("margin_right", 26)
	page.add_theme_constant_override("margin_top", 12)
	page.add_theme_constant_override("margin_bottom", 12)
	add_child(page)

	var col := UI.vbox(10)
	page.add_child(col)
	col.add_child(_topbar())

	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_content)

	_show_menu()

func _topbar() -> Control:
	var row := UI.hbox(14)
	var brand := UI.vbox(0)
	brand.add_child(UI.label("Dice & Dungeon", 22, Palette.BRASS))
	brand.add_child(UI.caption("прототип механики · godot"))
	row.add_child(brand)
	row.add_child(UI.spacer())

	_hp_label = UI.label("", UI.BODY, Palette.HEAL)
	_hp_label.visible = false
	row.add_child(_hp_label)

	_gold_label = UI.label("", UI.BODY, Palette.BRASS)
	_gold_label.visible = false
	row.add_child(_gold_label)

	_relic_shelf = UI.hbox(4)
	_relic_shelf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_relic_shelf)

	_deck_btn = UI.button("Колода")
	_deck_btn.visible = false
	_deck_btn.tooltip_text = "Посмотреть все карты забега"
	_deck_btn.pressed.connect(_show_deck)
	row.add_child(_deck_btn)

	_progress_chip = UI.flat_panel(Color(Palette.GROUND, 0.6), Palette.EDGE, 0)
	var sb: StyleBoxFlat = _progress_chip.get_theme_stylebox("panel")
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_progress_label = UI.caption("")
	_progress_chip.add_child(_progress_label)
	_progress_chip.visible = false
	_progress_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_progress_chip)

	_restart_btn = UI.button("Заново")
	_restart_btn.visible = false
	_restart_btn.pressed.connect(_show_build)
	row.add_child(_restart_btn)
	return row

func _swap(node: Control) -> void:
	for c in _content.get_children():
		c.queue_free()
	_content.add_child(node)

func _update_topbar() -> void:
	if run == null:
		return
	_progress_label.text = run.map.progress_text().to_upper()
	_hp_label.text = "%d / %d" % [run.hp, run.max_hp]
	_hp_label.add_theme_color_override("font_color",
		Palette.HEAL if run.hp > run.max_hp * 0.35 else Palette.BLOOD)
	_gold_label.text = "%d зол." % run.gold
	_refresh_relics()

## Полка реликвий: значки в шапке, подробности — в подсказке при наведении.
func _refresh_relics() -> void:
	if _relic_shelf == null:
		return
	if _relic_shelf.get_child_count() == run.relics.ids.size():
		return
	for c in _relic_shelf.get_children():
		c.queue_free()
	for id in run.relics.ids:
		_relic_shelf.add_child(_relic_badge(str(id), 26))

func _relic_badge(id: String, px: int) -> Control:
	var r := DB.relic(id)
	var holder := UI.flat_panel(Color(Palette.GROUND, 0.6), Palette.BRASS_DIM, 0)
	var sb: StyleBoxFlat = holder.get_theme_stylebox("panel")
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	holder.tooltip_text = "%s\n\n%s" % [str(r.get("name", id)), str(r.get("text", ""))]
	var icon := Icons.make(str(r.get("icon", "chest")), px, Palette.BRASS)
	if icon:
		holder.add_child(icon)
	else:
		holder.add_child(UI.label(str(r.get("name", id)).substr(0, 2), UI.SMALL, Palette.BRASS))
	return holder

# ────────────────────────────────────────── экраны

## Главное меню. Игра начинается отсюда, а не сразу со сборки: у забега
## должно быть начало, у окна — кнопка выхода, а у пула предметов — место,
## где его можно рассмотреть, не начиная бой.
func _show_menu() -> void:
	_clear_overlays()
	run = null
	_hide_run_chrome()
	var screen := Control.new()
	screen.set_script(MenuScreenScript)
	screen.start_requested.connect(_show_build)
	screen.gallery_requested.connect(_show_gallery)
	_swap(screen)

func _show_gallery() -> void:
	_clear_overlays()
	_hide_run_chrome()
	var screen := Control.new()
	screen.set_script(GalleryScreenScript)
	screen.back_requested.connect(_show_menu)
	_swap(screen)

func _hide_run_chrome() -> void:
	_progress_chip.visible = false
	_hp_label.visible = false
	_gold_label.visible = false
	_deck_btn.visible = false
	_restart_btn.visible = false
	for c in _relic_shelf.get_children():
		c.queue_free()

func _show_build() -> void:
	_clear_overlays()
	_hide_run_chrome()
	var screen := Control.new()
	screen.set_script(BuildScreenScript)
	screen.run_requested.connect(_start_run)
	screen.back_requested.connect(_show_menu)
	_swap(screen)

func _start_run(bag: Array, deck_id: String = "", deck: Array = []) -> void:
	run = Run.start(bag, 0, deck_id)
	# колода, собранная руками, важнее заготовки: заготовка была лишь
	# быстрым способом её заполнить
	if not deck.is_empty():
		run.deck = deck.duplicate()
	run.seal_gained.connect(_on_seal_gained)
	_progress_chip.visible = true
	_hp_label.visible = true
	_gold_label.visible = true
	_deck_btn.visible = true
	_restart_btn.visible = true
	_show_map()

## Печать меняет правило боя, поэтому её нельзя показать строчкой в углу:
## игрок должен прочитать, что именно теперь работает иначе.
func _on_seal_gained(id: String) -> void:
	var rel := DB.relic(id)
	if rel.is_empty():
		return
	var col := _sheet("Печать легла", "Мешочек сложился так, что курган это признал.")
	var row := UI.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_relic_badge(id, 40))
	var text := UI.vbox(3)
	text.add_child(UI.named(str(rel.get("name", id)), UI.H3, Palette.BRASS))
	text.add_child(UI.wrapped(str(rel.get("text", "")), UI.SMALL + 1, Palette.BONE, 380))
	row.add_child(text)
	col.add_child(row)
	var ok := UI.button("Понял")
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func(): _pop_overlay())
	col.add_child(ok)

## Короткое сообщение поверх экрана: реликвия истёрлась, правило перестало
## действовать. Такие вещи нельзя оставлять молча — игрок решит, что игра
## сломалась, а не что срок вышел.
var _toast_queue: Array = []

func _toast(text: String) -> void:
	_toast_queue.append(text)

func _flush_toasts(into: VBoxContainer) -> void:
	for t in _toast_queue:
		into.add_child(UI.wrapped(str(t), UI.SMALL + 1, Palette.BRASS, 640))
	_toast_queue.clear()

func _show_map() -> void:
	_clear_overlays()
	if run.hp <= 0:
		_show_end(false)
		return
	if run.map.finished():
		_show_end(true)
		return
	_update_topbar()
	var screen := Control.new()
	screen.set_script(MapScreenScript)
	screen.node_chosen.connect(_enter_node)
	_swap(screen)
	screen.setup(run)

func _enter_node(node: Dictionary) -> void:
	run.enter(node)
	_update_topbar()
	match str(node.type):
		"fight", "elite", "boss":
			_start_fight(node)
		"event":
			_start_event(str(node.get("event", "altar")))
		"rest":
			_show_rest()
		"treasure":
			_show_treasure()
		"shop":
			_show_shop()
		_:
			_show_map()

# ── бой

func _start_fight(node: Dictionary) -> void:
	_combat_screen = Control.new()
	_combat_screen.set_script(CombatScreenScript)
	_combat_screen.fight_finished.connect(func(won): _on_fight_finished(won, node))
	_swap(_combat_screen)
	await get_tree().process_frame
	_combat_screen.start_fight(run, run.enemy_for(node))

func _on_fight_finished(player_won: bool, node: Dictionary) -> void:
	await get_tree().create_timer(0.7).timeout
	if not player_won:
		run.hp = 0
		_show_end(false)
		return
	run.hp = _combat_screen.combat.hp
	# временные реликвии тратят заряд за каждый бой
	for worn in run.relics.spend_uses():
		var wr := DB.relic(str(worn))
		_toast("%s больше не работает." % str(wr.get("name", worn)))
	var kind := str(node.get("type", "fight"))
	var earned := run.gold_for(kind, rng)
	run.add_gold(earned)
	if run.map.act_cleared():
		if run.map.finished():
			_show_end(true)
			return
		_show_act_cleared(earned)
		return
	var finish := func():
		run.heal(run.heal_after_fight())
		_show_reward(kind, earned)

	# Постоянная вещь — только за примечательную комнату. Обычный бой даёт
	# карту и золото, и всё: реликвия, которая падает после каждого второго
	# боя, перестаёт быть зарубкой в памяти и становится обоями.
	if kind == "elite":
		if rng.randf() < float(DB.b("pact_chance", 0.4)):
			var pacts := run.relics.roll_many(rng, "pact", 3)
			if not pacts.is_empty():
				_show_relic_choice(pacts, "Договор",
					"Каждый даёт много и каждый чего-то стоит. Решай, чем платишь.", finish)
				return
		var tier := "rare" if run.map.act_index >= 2 else ("uncommon" if run.map.act_index >= 1 else "common")
		_show_relic_choice(run.relics.roll_many(rng, tier, 3),
			"Реликвия за элиту", "Возьми одну — или пройди мимо.", finish)
		return

	finish.call()

# ── событие

func _start_event(id: String) -> void:
	var screen := Control.new()
	screen.set_script(EventScreenScript)
	screen.finished.connect(func():
		if run.hp <= 0:
			_show_end(false)
		else:
			_show_map())
	_swap(screen)
	screen.setup(run, id)

# ────────────────────────────────────────── оверлеи

## Лист поверх экрана. Оверлеи складываются в стопку: из привала можно
## открыть выбор карты и вернуться обратно, ничего не потеряв.
func _sheet(title: String, subtitle: String, width: int = 540) -> VBoxContainer:
	var overlay := ColorRect.new()
	overlay.color = Color(0.04, 0.03, 0.055, 0.9)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_overlays.append(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var sheet := UI.panel(Palette.PANEL, Palette.EDGE, 26)
	center.add_child(sheet)
	var col := UI.vbox(12)
	sheet.add_child(col)

	var t := UI.label(title, UI.H2, Palette.BRASS)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	if subtitle != "":
		var s := UI.wrapped(subtitle, UI.SMALL + 1, Palette.BONE_DIM, width)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(s)
	return col

func _pop_overlay() -> void:
	if _overlays.is_empty():
		return
	var top: Node = _overlays.pop_back()
	if is_instance_valid(top):
		top.queue_free()

func _clear_overlays() -> void:
	for o in _overlays:
		if is_instance_valid(o):
			o.queue_free()
	_overlays.clear()

func _close_overlay() -> void:
	_clear_overlays()
	_show_map()

## Сетка карт с прокруткой — для просмотра колоды и выбора карты.
func _card_grid(ids: Array, on_pick: Callable, columns: int = 5, height: int = 430) -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(min(ids.size(), columns) * 170 + 20, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	for id in ids:
		var v := CardView.new(str(id))
		if on_pick.is_valid():
			v.clicked.connect(func(cid): on_pick.call(cid))
		else:
			v.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(v)
	return scroll

## Выбор одной карты из списка — чистка колоды, улучшение, витрина.
func _pick_card(ids: Array, title: String, subtitle: String, on_pick: Callable) -> void:
	if ids.is_empty():
		var col_empty := _sheet(title, "Подходящих карт нет.")
		var back := UI.button("Назад")
		back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		back.pressed.connect(_pop_overlay)
		col_empty.add_child(back)
		return
	var col := _sheet(title, subtitle, 700)
	col.add_child(_card_grid(ids, func(cid):
		_pop_overlay()
		on_pick.call(cid)))
	var cancel := UI.button("Назад")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_pop_overlay)
	col.add_child(cancel)

## Выбор кубика из мешочка — когда полный мешочек надо разменять.
func _pick_die(title: String, subtitle: String, on_pick: Callable) -> void:
	var col := _sheet(title, subtitle, 640)
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	flow.custom_minimum_size.x = 560
	col.add_child(flow)
	for d in run.bag:
		var v := DieView.new(d)
		v.pickable = true
		v.clicked.connect(func(die):
			_pop_overlay()
			on_pick.call(die))
		flow.add_child(v)
	var cancel := UI.button("Оставить как есть")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_pop_overlay)
	col.add_child(cancel)

## Взять кубик: если в мешочке нет места, предлагаем размен.
func _take_die(die: Die, after: Callable) -> void:
	if run.add_die(die):
		after.call()
		return
	_pick_die("Мешочек полон",
		"Слотов %d, все заняты. Выбери, какой кубик уступит место — или оставь мешочек как есть."
		% run.die_slots(),
		func(old_die):
			run.swap_die(old_die, die)
			after.call())

## Просмотр колоды в любой момент: без него собранную колоду не удержать в голове.
func _show_deck() -> void:
	if run == null:
		return
	var sorted := run.deck.duplicate()
	sorted.sort_custom(func(a, b):
		var ra := ["curse", "basic", "common", "uncommon", "rare"].find(DB.rarity(str(a)))
		var rb := ["curse", "basic", "common", "uncommon", "rare"].find(DB.rarity(str(b)))
		if ra != rb:
			return ra > rb
		return str(DB.card_name(str(a))) < str(DB.card_name(str(b))))
	var counts := {}
	for id in run.deck:
		var r := DB.rarity(str(id))
		counts[r] = int(counts.get(r, 0)) + 1
	var parts: Array = []
	for r in ["rare", "uncommon", "common", "basic", "curse"]:
		if counts.has(r):
			parts.append("%s — %d" % [Palette.rarity_name(r), int(counts[r])])
	var col := _sheet("Колода · %d карт" % run.deck.size(), ", ".join(parts), 700)
	col.add_child(_card_grid(sorted, Callable(), 5, 460))
	var close := UI.button("Закрыть", true)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_pop_overlay)
	col.add_child(close)

# ── награды

func _show_reward(kind: String, earned: int) -> void:
	var col := _sheet("Комната зачищена",
		"+%d здоровья, +%d золота. Возьми карту в колоду (сейчас %d)."
		% [run.heal_after_fight(), earned, run.deck.size()])
	_flush_toasts(col)
	var cards := UI.hbox(14)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(cards)
	for id in run.reward_options(rng, 3, kind):
		var v := CardView.new(str(id))
		v.clicked.connect(func(card_id):
			run.deck.append(card_id)
			_close_overlay())
		cards.add_child(v)
	var skip := UI.button("Пропустить (+%d здоровья)" % int(DB.b("heal_on_skip_reward", 6)))
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip.pressed.connect(func():
		run.heal(int(DB.b("heal_on_skip_reward", 6)))
		_close_overlay())
	col.add_child(skip)

## Босс акта повержен: редкая карта, золото и переход в следующий акт.
func _show_act_cleared(earned: int) -> void:
	var next_title := ""
	if run.map.act_index + 1 < run.map.acts.size():
		next_title = str(run.map.acts[run.map.act_index + 1].title)
	var bonus := int(DB.b("max_hp_per_act", 14))
	run.max_hp += bonus
	run.heal(int(round(run.max_hp * float(DB.b("heal_per_act", 0.45)))))
	var col := _sheet("%s пройден" % run.map.act_title(),
		"+%d золота, +%d к максимуму здоровья, раны затянулись. Впереди — %s." % [earned, bonus, next_title])

	var cards := UI.hbox(14)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(cards)
	var boss_relics := run.relics.roll_many(rng, "boss", 3)
	# Особый кубик за акт — обещание, а не удача. Мешочек к третьему акту
	# должен отличаться от стартового не только числом граней.
	var to_die := func():
		_pop_overlay()
		_show_act_die(_advance_act)
	var to_relic := func():
		_pop_overlay()
		_show_relic_choice(boss_relics, "Трофей босса",
			"Эти сильнее всего, что попадалось. И цена у них своя.", to_die)
	for id in run.reward_options(rng, 3, "boss"):
		var v := CardView.new(str(id))
		v.clicked.connect(func(card_id):
			run.deck.append(card_id)
			to_relic.call())
		cards.add_child(v)
	var skip := UI.button("Дальше без карты")
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip.pressed.connect(func(): to_relic.call())
	col.add_child(skip)

## Реликвии и договоры показываются одинаково: три карточки на выбор и
## кнопка отказа. Навязанная награда — не решение; решение начинается там,
## где можно взять другое или не брать ничего.
func _relic_card(id: String, on_take: Callable) -> Control:
	var r := DB.relic(id)
	var is_pact := str(r.get("rarity", "")) == "pact"
	var edge: Color = Palette.rarity_color("pact") if is_pact else Palette.BRASS
	var card := UI.panel(Palette.RAISED, edge, 16)
	card.custom_minimum_size = Vector2(250, 168)
	var inner := UI.vbox(8)
	card.add_child(inner)

	var head := UI.hbox(10)
	var icon := Icons.make(str(r.get("icon", "chest")), 34, edge)
	if icon:
		var holder := CenterContainer.new()
		holder.custom_minimum_size = Vector2(38, 38)
		holder.add_child(icon)
		head.add_child(holder)
	head.add_child(UI.named(str(r.get("name", id)), UI.SMALL + 4, edge))
	inner.add_child(head)

	# у договора цена написана вторым предложением — её надо видеть, а не
	# вычитывать из подсказки
	var text := str(r.get("text", ""))
	var body := UI.wrapped(text, UI.SMALL, Palette.BONE_DIM, 210)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(body)

	var take := UI.button("Взять", true)
	take.pressed.connect(func(): on_take.call(id))
	inner.add_child(take)
	return card

func _show_relic_choice(ids: Array, title: String, subtitle: String, after: Callable) -> void:
	if ids.is_empty():
		after.call()
		return
	var col := _sheet(title, subtitle, 760)
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for id in ids:
		row.add_child(_relic_card(str(id), func(picked):
			run.gain_relic(str(picked))
			_pop_overlay()
			after.call()))
	var skip := UI.button("Отказаться")
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip.tooltip_text = "Ничего не брать. Иногда цена не стоит силы."
	skip.pressed.connect(func():
		_pop_overlay()
		after.call())
	col.add_child(skip)

## Особый кубик за пройденный акт: выбор из трёх, все — со свойством.
func _show_act_die(after: Callable) -> void:
	var options := run.act_die_options(rng, 3)
	if options.is_empty():
		after.call()
		return
	var col := _sheet("Трофей акта",
		"Из кургана ты вынес не только шрамы. Возьми особый кубик — у каждого своё свойство.")
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for d in options:
		var holder := UI.vbox(4)
		var v := DieView.new(d)
		v.pickable = true
		v.clicked.connect(func(die):
			_take_die(die, after))
		holder.add_child(v)
		holder.add_child(UI.label(Palette.element_name(d.element), UI.TINY + 1, Palette.MUTED))
		var q := DB.quirk_of(d.quirk)
		if not q.is_empty():
			holder.add_child(UI.wrapped(str(q.get("text", "")), UI.TINY, Palette.BRASS, 150))
		row.add_child(holder)

func _advance_act() -> void:
	run.map.advance_act()
	_close_overlay()

func _show_treasure() -> void:
	var earned := run.gold_for("treasure", rng)
	run.add_gold(earned)
	# Реликвия в каждом сундуке обесценивала реликвии: к третьему акту их
	# набиралось шесть, и очередная уже ничего не решала.
	var relic_id := ""
	if rng.randf() < float(DB.b("treasure_relic_chance", 0.45)):
		relic_id = run.relics.roll_for_room(rng, "treasure", run.map.act_index)
		run.gain_relic(relic_id)
	else:
		var extra := run.gold_for("treasure", rng)
		run.add_gold(extra)
		earned += extra
	var head := "+%d золота." % earned
	if relic_id != "":
		head += " В сундуке лежала реликвия. Ещё выбери кубик или карту."
	else:
		head += " Выбери кубик в мешочек или карту в колоду."
	var col := _sheet("Сокровище", head)
	if relic_id != "":
		var rel := DB.relic(relic_id)
		var relic_row := UI.hbox(10)
		relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
		relic_row.add_child(_relic_badge(relic_id, 28))
		var rtext := UI.vbox(2)
		rtext.add_child(UI.named(str(rel.get("name", relic_id)), UI.SMALL + 3, Palette.BRASS))
		rtext.add_child(UI.wrapped(str(rel.get("text", "")), UI.SMALL, Palette.BONE_DIM, 380))
		relic_row.add_child(rtext)
		col.add_child(relic_row)
		col.add_child(UI.gap(4))
	var dice_row := UI.hbox(12)
	dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(dice_row)
	for d in run.die_options(rng, 3):
		var holder := UI.vbox(4)
		var v := DieView.new(d)
		v.pickable = true
		v.clicked.connect(func(die):
			_take_die(die, _close_overlay))
		holder.add_child(v)
		holder.add_child(UI.label(Palette.element_name(d.element), UI.TINY + 1, Palette.MUTED))
		dice_row.add_child(holder)

	col.add_child(UI.gap(6))
	var cards := UI.hbox(14)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(cards)
	for id in run.reward_options(rng, 2, "treasure"):
		var cv := CardView.new(str(id))
		cv.clicked.connect(func(card_id):
			run.deck.append(card_id)
			_close_overlay())
		cards.add_child(cv)

# ── лавка

func _show_shop() -> void:
	var stock := run.shop_stock(rng)
	_build_shop(stock)

func _build_shop(stock: Array) -> void:
	_clear_overlays()
	var col := _sheet("Лавка", "Золота: %d. Здесь тратят то, что заработали на элите." % run.gold, 720)
	var cards := UI.hbox(12)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(cards)
	var services := UI.hbox(12)
	services.alignment = BoxContainer.ALIGNMENT_CENTER

	for item in stock:
		if bool(item.get("sold", false)):
			continue
		var price := int(item.price)
		var affordable := run.gold >= price
		match str(item.kind):
			"card":
				var holder := UI.vbox(4)
				var v := CardView.new(str(item.id))
				v.playable = affordable
				v.refresh()
				v.clicked.connect(func(_cid):
					if run.spend(price):
						run.deck.append(str(item.id))
						item["sold"] = true
						_build_shop(stock))
				holder.add_child(v)
				var tag := UI.label("%d зол." % price, UI.SMALL + 1,
					Palette.BRASS if affordable else Palette.MUTED)
				tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				holder.add_child(tag)
				cards.add_child(holder)
			"die":
				var holder2 := UI.vbox(4)
				var dv := DieView.new(item.die)
				dv.pickable = affordable
				dv.clicked.connect(func(die):
					if run.spend(price):
						item["sold"] = true
						_take_die(die, func(): _build_shop(stock)))
				holder2.add_child(dv)
				holder2.add_child(UI.label(Palette.element_name(item.die.element), UI.TINY + 1, Palette.MUTED))
				var tag2 := UI.label("%d зол." % price, UI.SMALL + 1,
					Palette.BRASS if affordable else Palette.MUTED)
				tag2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				holder2.add_child(tag2)
				services.add_child(holder2)
			"relic":
				var rel := DB.relic(str(item.id))
				var holder3 := UI.vbox(4)
				var b3 := UI.button("%s — %d зол." % [str(rel.get("name", item.id)), price])
				b3.disabled = not affordable
				b3.tooltip_text = str(rel.get("text", ""))
				b3.pressed.connect(func():
					if run.spend(price):
						run.gain_relic(str(item.id))
						item["sold"] = true
						_build_shop(stock))
				holder3.add_child(b3)
				holder3.add_child(UI.wrapped(str(rel.get("text", "")), UI.TINY + 1, Palette.MUTED, 240))
				services.add_child(holder3)
			"remove":
				var b := UI.button("Выжечь карту — %d зол." % price)
				b.disabled = not affordable
				b.pressed.connect(func():
					_pick_card(run.deck.duplicate(), "Какую карту выжечь",
						"Она уйдёт из колоды навсегда.", func(cid):
							if run.spend(price):
								run.deck.erase(cid)
								run.removals_bought += 1
								item["sold"] = true
								_build_shop(stock)))
				services.add_child(b)
			"upgrade":
				var b2 := UI.button("Заточить карту — %d зол." % price)
				b2.disabled = not affordable
				b2.pressed.connect(func():
					_pick_card(run.upgradable(), "Какую карту заточить",
						"Улучшенная версия сильнее — наведись, чтобы увидеть разницу.", func(cid):
							if run.spend(price):
								run.upgrade_card(cid)
								item["sold"] = true
								_build_shop(stock)))
				services.add_child(b2)
	col.add_child(services)

	var leave := UI.button("Уйти", true)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(_close_overlay)
	col.add_child(leave)
	_update_topbar()

# ── привал

func _show_rest() -> void:
	var heal_amount := run.rest_heal()
	var col := _sheet("Привал", "Костёр, тишина и один выбор.", 620)
	var row := UI.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var sleep := UI.button("Выспаться (+%d здоровья)" % heal_amount, true)
	sleep.pressed.connect(func():
		run.heal(heal_amount)
		_close_overlay())
	row.add_child(sleep)

	var sharpen_card := UI.button("Заточить карту")
	sharpen_card.tooltip_text = "Улучшить одну карту до конца забега"
	sharpen_card.pressed.connect(func():
		_pick_card(run.upgradable(), "Какую карту заточить",
			"Наведись на карту — в подсказке видно, чем станет.", func(cid):
				run.upgrade_card(cid)
				_close_overlay()))
	row.add_child(sharpen_card)

	var row2 := UI.hbox(12)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row2)

	var thin := UI.button("Проредить колоду")
	thin.tooltip_text = "Убрать одну карту — тонкая колода чаще выдаёт нужное"
	thin.pressed.connect(func():
		_pick_card(run.deck.duplicate(), "Какую карту убрать",
			"Чем тоньше колода, тем чаще приходит то, ради чего она собрана.", func(cid):
				run.deck.erase(cid)
				_close_overlay()))
	row2.add_child(thin)

	var sharpen := UI.button("Обточить кубик (−1 к перезарядке)")
	sharpen.pressed.connect(func():
		run.apply_effects([{"op": "upgrade_die"}], rng)
		_close_overlay())
	row2.add_child(sharpen)

# ────────────────────────────────────────── финал

func _show_end(won: bool) -> void:
	_clear_overlays()
	_progress_chip.visible = false
	var screen := Control.new()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var col := UI.vbox(16)
	center.add_child(col)

	var title := UI.label("Подземелье пройдено" if won else "Забег окончен", 42,
		Palette.BRASS if won else Palette.BLOOD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var text := "Отследи одну вещь: в какой момент выбор кубика был самым тяжёлым? Это и есть ядро игры."
	if not won and run != null:
		text = "Дошёл до: %s. Попробуй другой маршрут — элита даёт больше золота и карт, но забирает здоровье, которого потом не хватит на босса." % run.map.progress_text()
	var body := UI.wrapped(text, UI.BODY, Palette.BONE_DIM, 540)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(body)

	var again := UI.button("Новый забег", true)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(_show_build)
	col.add_child(again)
	_swap(screen)
