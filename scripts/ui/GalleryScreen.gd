extends Control
## Галерея: всё, что может попасться в подземелье, в одном месте.
##
## Зачем она есть. Пул вырос до восьмидесяти с лишним карт, шести десятков
## реликвий и полутора десятков свойств кубиков — узнать про них в бою
## нельзя, там их показывают по три штуки и на секунду. Галерея не даёт
## преимущества в забеге, она даёт понимание, из чего игра вообще состоит:
## что бывает, каких стихий, что с чем сочетается.

signal back_requested

const TABS := [
	{"id": "cards", "name": "Карты"},
	{"id": "relics", "name": "Реликвии"},
	{"id": "pacts", "name": "Договоры"},
	{"id": "seals", "name": "Печати"},
	{"id": "quirks", "name": "Свойства кубиков"},
]

var _tab: String = "cards"
var _tabs_row: HFlowContainer
var _body: ScrollContainer
var _count: Label
## Фильтр по стихии для вкладки карт. Восемьдесят карт одной кучей
## не рассматривают — их листают в поисках «а что есть у льда».
var _element: String = ""
var _filter_row: HFlowContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := UI.vbox(10)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var head := UI.hbox(14)
	var title_col := UI.vbox(0)
	title_col.add_child(UI.label("Галерея", UI.H2, Palette.BONE))
	_count = UI.caption("")
	title_col.add_child(_count)
	head.add_child(title_col)
	head.add_child(UI.spacer())
	var back := UI.button("В меню")
	back.pressed.connect(func(): back_requested.emit())
	head.add_child(back)
	root.add_child(head)

	_tabs_row = HFlowContainer.new()
	_tabs_row.add_theme_constant_override("h_separation", 6)
	root.add_child(_tabs_row)

	_filter_row = HFlowContainer.new()
	_filter_row.add_theme_constant_override("h_separation", 6)
	root.add_child(_filter_row)

	_body = ScrollContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_body)

	_rebuild_tabs()
	_rebuild()

func _rebuild_tabs() -> void:
	for c in _tabs_row.get_children():
		c.queue_free()
	for t in TABS:
		var b := UI.button(str(t.name), str(t.id) == _tab)
		b.pressed.connect(func():
			_tab = str(t.id)
			_rebuild_tabs()
			_rebuild())
		_tabs_row.add_child(b)

func _rebuild_filters() -> void:
	for c in _filter_row.get_children():
		c.queue_free()
	_filter_row.visible = _tab == "cards"
	if not _filter_row.visible:
		return
	var all := UI.button("Все", _element == "")
	all.pressed.connect(func():
		_element = ""
		_rebuild())
	_filter_row.add_child(all)
	for key in Palette.ELEMENTS.keys():
		var b := UI.button(Palette.element_name(str(key)), _element == str(key))
		b.add_theme_color_override("font_color",
			Color("231a09") if _element == str(key) else Palette.element_color(str(key)))
		b.pressed.connect(func():
			_element = str(key)
			_rebuild())
		_filter_row.add_child(b)

func _rebuild() -> void:
	_rebuild_filters()
	for c in _body.get_children():
		c.queue_free()
	match _tab:
		"cards": _build_cards()
		"relics": _build_relics(["common", "uncommon", "rare", "boss"])
		"pacts": _build_relics(["pact"])
		"seals": _build_relics(["seal"])
		"quirks": _build_quirks()

## Карты показываются самими картами, а не списком: смысл галереи в том,
## чтобы увидеть их такими же, какими они придут в руку.
func _build_cards() -> void:
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(grid)
	var order := {"basic": 0, "common": 1, "uncommon": 2, "rare": 3, "curse": 4}
	var ids: Array = DB.card_ids()
	ids.sort_custom(func(a, b):
		var ca := DB.card(str(a))
		var cb := DB.card(str(b))
		var ra := int(order.get(str(ca.get("rarity", "common")), 9))
		var rb := int(order.get(str(cb.get("rarity", "common")), 9))
		if ra != rb:
			return ra < rb
		return str(ca.get("name", "")) < str(cb.get("name", "")))
	var shown := 0
	for id in ids:
		var c := DB.card(str(id))
		if _element != "" and str(c.get("element", "none")) != _element:
			continue
		grid.add_child(CardView.new(str(id)))
		shown += 1
	_count.text = "%d карт" % shown

func _build_relics(rarities: Array) -> void:
	var col := UI.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(col)
	var shown := 0
	for rarity in rarities:
		var ids: Array = []
		for id in DB.relics.keys():
			if str(id).begins_with("_") or id in ["pools", "seals", "seal_balance_id"]:
				continue
			var r: Variant = DB.relics[id]
			if typeof(r) != TYPE_DICTIONARY:
				continue
			if str(r.get("rarity", "")) == rarity:
				ids.append(str(id))
		if ids.is_empty():
			continue
		ids.sort()
		col.add_child(UI.caption(_rarity_title(rarity)))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(grid)
		for id in ids:
			grid.add_child(_relic_card(str(id)))
			shown += 1
		col.add_child(UI.gap(8))
	_count.text = "%d предметов" % shown

func _rarity_title(rarity: String) -> String:
	match rarity:
		"common": return "обычные — падают с ранних элит и лежат в лавке"
		"uncommon": return "необычные — элиты второго акта"
		"rare": return "редкие — элиты третьего акта"
		"boss": return "трофеи боссов — сильные, и у каждого своя цена"
		"pact": return "договоры — предлагают за элиту вместо реликвии"
		"seal": return "печати — приходят сами за три кубика одной стихии"
	return rarity

func _relic_card(id: String) -> Control:
	var r := DB.relic(id)
	var box := UI.panel(Palette.GROUND_2, Palette.EDGE_SOFT, 10)
	var row := UI.hbox(10)
	row.custom_minimum_size.x = 330
	box.add_child(row)

	var icon_holder := CenterContainer.new()
	icon_holder.custom_minimum_size = Vector2(34, 34)
	var icon := Icons.make(str(r.get("icon", "scroll")), 28, Palette.BRASS)
	if icon:
		icon_holder.add_child(icon)
	row.add_child(icon_holder)

	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.named(str(r.get("name", id)), UI.SMALL + 3, Palette.BONE))
	col.add_child(UI.wrapped(str(r.get("text", "")), UI.SMALL, Palette.BONE_DIM, 270))
	row.add_child(col)
	return box

func _build_quirks() -> void:
	var col := UI.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(col)
	col.add_child(UI.wrapped(
		"Особые кубики падают за пройденный акт, из сундуков и продаются в лавке. "
		+ "У каждого свойства есть цена, и платится она не тем же, чем даётся: "
		+ "за прибавку к броску кубик дольше остывает или стоит здоровья.",
		UI.SMALL + 1, Palette.BONE_DIM, 620))
	col.add_child(UI.gap(6))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(grid)
	var traits: Dictionary = DB.b("traits", {})
	for key in traits.keys():
		var t: Dictionary = traits[key]
		var box := UI.panel(Palette.GROUND_2, Palette.EDGE_SOFT, 10)
		var line := UI.vbox(2)
		line.custom_minimum_size.x = 300
		line.add_child(UI.named(str(t.get("name", key)).capitalize(), UI.SMALL + 3, Palette.BRASS))
		line.add_child(UI.wrapped(str(t.get("text", "")), UI.SMALL, Palette.BONE_DIM, 290))
		box.add_child(line)
		grid.add_child(box)
	_count.text = "%d свойств" % traits.size()
