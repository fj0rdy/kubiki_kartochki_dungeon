extends Node
## Скриншоты экранов на виртуальном дисплее.

var main: Node

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	await _shot("menu")
	_press("Галерея")
	await get_tree().create_timer(0.6).timeout
	await _shot("gallery")
	_press("В меню")
	await get_tree().create_timer(0.3).timeout
	_press("Начать забег")
	await get_tree().create_timer(0.4).timeout
	await _shot("build")

	_press("В подземелье")
	await get_tree().create_timer(0.2).timeout
	# реликвии на полку, чтобы шапка была как в середине забега
	if main.run:
		for rid in ["bone_charm", "gamblers_skull", "oiled_bag"]:
			main.run.gain_relic(rid)
		# особые кубики: без них не видно вторую полку мешочка,
		# а именно на ней ломалась вёрстка при седьмом кубике
		main.run.bag.append(Die.make(12, "dark", "greedy"))
		main.run.bag.append(Die.make(8, "light", "prism"))
		main._update_topbar()
	await get_tree().create_timer(0.8).timeout
	await _shot("map")

	# зайти в первую доступную комнату с боем
	var map_screen := _find_by_script(main, "MapScreen.gd")
	if map_screen:
		var options: Array = main.run.map.available()
		var target = options[0]
		for o in options:
			if str(o.type) in ["fight", "elite"]:
				target = o
				break
		map_screen.node_chosen.emit(target)
	await get_tree().create_timer(1.0).timeout
	await _shot("combat")

	var combat := _find_by_script(main, "CombatScreen.gd")
	if combat:
		# выбрать первую играбельную карту
		var hand = combat._hand
		for i in combat.combat.hand.size():
			if combat.combat.can_play(str(combat.combat.hand[i])):
				combat._on_card_clicked(i)
				break
		await get_tree().create_timer(0.5).timeout
		await _shot("card-selected")

		# вытащить кубик в лоток и бросить — тот же путь, что у живого игрока
		for d in _collect(combat, "DieView"):
			if d.draggable:
				combat._on_drag_started(d.die)
				break
		await get_tree().create_timer(0.4).timeout
		await _shot("dice-grab")
		combat._tray._release()
		await get_tree().create_timer(1.2).timeout
		await _shot("dice-roll")
		await get_tree().create_timer(2.2).timeout
		await _shot("after-roll")

		# для снимка навешиваем статусы вручную: ждать, пока они выпадут
		# сами, в скриптованном прогоне ненадёжно
		combat.combat.foe_burn = 5
		combat.combat.foe_poison = 4
		combat.combat.foe_vulnerable = 2
		combat.combat.foe_plated = 6
		combat.combat.thorns = 3
		combat.combat.changed.emit()
		await get_tree().create_timer(0.4).timeout
		await _shot("statuses")

		# худший случай вёрстки: полная рука длинных карт
		combat.combat.hand = ["typhoon", "swarmlord", "bloodpact", "covenant",
			"resonance", "harvest", "mirror", "fortress"]
		combat.combat.changed.emit()
		await get_tree().create_timer(0.5).timeout
		await _shot("full-hand")

	# событие показываем напрямую — на карте оно может не выпасть
	if main.run:
		main._start_event("altar")
		await get_tree().create_timer(0.6).timeout
		await _shot("event")

		# новые экраны: колода, лавка, привал, награда
		main._show_map()
		await get_tree().create_timer(0.5).timeout
		main._show_deck()
		await get_tree().create_timer(0.6).timeout
		await _shot("deck")
		main._clear_overlays()

		main._show_shop()
		await get_tree().create_timer(0.6).timeout
		await _shot("shop")
		main._clear_overlays()

		main._show_rest()
		await get_tree().create_timer(0.5).timeout
		await _shot("rest")
		main._clear_overlays()

		main._show_reward("fight", 17)
		await get_tree().create_timer(0.6).timeout
		await _shot("reward")
		main._clear_overlays()

		main._show_relic_found("thorn_crown", "elite", 34)
		await get_tree().create_timer(0.6).timeout
		await _shot("relic")
		main._clear_overlays()

		main._show_treasure()
		await get_tree().create_timer(0.6).timeout
		await _shot("treasure")
		main._clear_overlays()
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/g-%s.png" % name)
	print("shot: ", name)

func _press(text: String) -> void:
	var b := _find_button(main, text)
	if b:
		b.pressed.emit()

func _find_map_button(prefixes: Array) -> Button:
	var map := _find_by_script(main, "MapScreen.gd")
	if map == null:
		return null
	return _first_enabled(map, prefixes)

func _first_enabled(node: Node, prefixes: Array) -> Button:
	if node is Button and not node.disabled:
		for p in prefixes:
			if node.text.begins_with(p):
				return node
	for c in node.get_children():
		var r := _first_enabled(c, prefixes)
		if r:
			return r
	return null

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for c in node.get_children():
		var r := _find_button(c, text)
		if r:
			return r
	return null

func _find_by_script(node: Node, tail: String) -> Node:
	var s = node.get_script()
	if s and str(s.resource_path).ends_with(tail):
		return node
	for c in node.get_children():
		var r := _find_by_script(c, tail)
		if r:
			return r
	return null

func _collect(node: Node, cls: String) -> Array:
	var out: Array = []
	var s = node.get_script()
	if s and str(s.resource_path).ends_with(cls + ".gd"):
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect(c, cls))
	return out
