extends Node
## Разбор боёв по одному врагу. Запуск:
##   godot --headless --path . res://tools/FightLab.tscn -- 60
##
## Каждый враг проверяется отдельно: побеждает ли бот, за сколько ходов
## и сколько здоровья это стоит. Так видно, какой именно враг ломает акт.

func _ready() -> void:
	var n := 40
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			n = int(a)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	var presets: Dictionary = DB.b("presets", {})
	var bag_def: Array = presets.get("Баланс", [])
	print("=== ВРАГИ ПО ОДНОМУ (мешочек «Баланс», %d боёв) ===" % n)
	print("старт — колода 10 карт; +8 и +16 — как в середине и в конце забега")
	var order: Array = []
	for act in DB.enemies.get("acts", []):
		for group in ["normal", "elite", "boss"]:
			for eid in act.get(group, []):
				if not order.has(eid):
					order.append(eid)
	for eid in order:
		var foe: Dictionary = DB.enemy(str(eid))
		var line := str(foe.get("name", eid)).rpad(24) + "hp %3d " % int(foe.get("hp", 0))
		for extra in [0, 8, 16]:
			var wins := 0
			var turns := 0
			var lost := 0
			for i in n:
				var res := _fight(bag_def, foe, rng, extra)
				wins += 1 if res.won else 0
				turns += res.turns
				lost += res.lost
			line += "  | +%2d: %3d%% побед, %.1f х., −%.0f hp" % [
				extra,
				int(round(100.0 * wins / n)),
				float(turns) / n,
				float(lost) / n,
			]
		print(line)
	get_tree().quit()

## Колода из стартовой плюс extra случайных драфтовых карт; часть заточена —
## примерно так выглядит колода к середине и к концу забега.
func _grown_deck(extra: int, rng: RandomNumberGenerator) -> Array:
	var deck: Array = DB.b("starter_deck", []).duplicate()
	var pool: Array = []
	for r in ["common", "common", "uncommon", "uncommon", "rare"]:
		pool.append_array(DB.cards_of_rarity(r))
	for i in extra:
		var id := str(pool[rng.randi_range(0, pool.size() - 1)])
		if rng.randf() < 0.35 and DB.can_upgrade(id):
			id = DB.upgraded_id(id)
		deck.append(id)
	return deck

func _fight(bag_def: Array, foe: Dictionary, rng: RandomNumberGenerator, extra: int = 0) -> Dictionary:
	var bag: Array = []
	for entry in bag_def:
		bag.append(Die.make(int(entry[0]), str(entry[1])))
	# с ростом колоды растёт и мешочек — на сокровищах добавляют кубики
	if extra >= 8:
		bag.append(Die.make(8, "light"))
	if extra >= 16:
		bag.append(Die.make(12, "dark"))
	var max_hp: int = int(DB.b("base_hp", 64)) + Run.spare_hp(bag)

	var combat := Combat.new()
	combat.rng = rng
	var result := {"done": false, "won": false}
	combat.fight_over.connect(func(w): result.done = true; result.won = w)
	combat.setup(bag, _grown_deck(extra, rng), max_hp, max_hp, foe)

	var tempo := Run.tempo(bag)
	var pool := tempo
	var guard := 0
	while not result.done and guard < 800:
		guard += 1
		var playable: Array = []
		for cid in combat.hand:
			if combat.can_play(cid):
				playable.append(cid)
		if playable.is_empty():
			if combat.has_cooling_dice() and combat.hp > int(DB.b("regroup_cost", 4)) * 3:
				combat.regroup()
			else:
				combat.end_turn()
			pool = minf(tempo * 2.0, pool + tempo)
			continue
		var pick: String = playable[rng.randi_range(0, playable.size() - 1)]
		var need := int(DB.card(pick).get("dice", 1))
		if pool < need:
			combat.end_turn()
			pool = minf(tempo * 2.0, pool + tempo)
			continue
		var ready := combat.ready_dice_for(pick)
		var chosen: Array = []
		for k in need:
			if ready.is_empty():
				break
			var idx := rng.randi_range(0, ready.size() - 1)
			chosen.append(ready[idx])
			ready.remove_at(idx)
		if chosen.size() < need:
			combat.end_turn()
			pool = minf(tempo * 2.0, pool + tempo)
			continue
		combat.play_card(pick, chosen)
		pool -= need
		var still := false
		for cid in combat.hand:
			if combat.can_play(cid):
				still = true
				break
		if not still and not result.done:
			combat.end_turn()
			pool = minf(tempo * 2.0, pool + tempo)
	return {"won": result.won, "turns": combat.turn, "lost": max_hp - max(0, combat.hp)}
