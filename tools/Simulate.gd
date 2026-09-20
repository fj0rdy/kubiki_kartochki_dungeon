extends Node
## Прогон забегов без графики. Запуск:
##   godot --headless --path . res://tools/Simulate.tscn -- 100
##
## Бот ходит по карте, дерётся случайными картами и случайными кубиками,
## но держит темп: тратит за ход не больше кубиков, чем мешочек успевает
## восстановить. Жадная игра «вылить всё» проваливается из-за пустых ходов
## без блока — это и проверяется.
##
## Замер ловит тупики, мёртвые билды и непроходимые числа. Живой плейтест
## он не заменяет: бот не приберегает d20 под «Мощный удар».
##
## ВАЖНО: случайный бот НЕ находит комбо, поэтому по одному винрейту нельзя
## судить, что игра не ломается. Для этого есть два инструмента.
##
## 1. Счётчики вырождения. Ход, в котором сыграно 6+ карт, или кубик,
##    брошенный больше трёх раз за бой, или колода, опустевшая по три раза, —
##    это следы вечного двигателя, даже если бот наткнулся на него случайно.
## 2. Жадный режим (--greedy): бот сначала играет всё, что возвращает кубики
##    и тянет карты, и только потом бьёт. Он специально ищет двигатель. Если
##    у жадного бота ходы не кончаются — правило дырявое, и это видно сразу.

## Жадный бот: сначала возврат кубиков и добор, потом всё остальное.
## Он не «играет лучше» — он специально пытается не заканчивать ход.
var _greedy := false

func _ready() -> void:
	var runs := 40
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			runs = int(a)
		elif str(a) == "--greedy":
			_greedy = true

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260824

	print("=== СИМУЛЯЦИЯ: %d забегов на билд%s ===" % [runs, "  (жадный режим: ищем двигатель)" if _greedy else ""])
	var presets: Dictionary = DB.b("presets", {})
	for preset_name in presets.keys():
		var acc := {
			"wins": 0, "rooms": 0, "turns": 0, "fights": 0,
			"cards": 0, "dead": 0, "deck": 0, "acts": 0, "relics": 0,
			"max_cards_turn": 0, "engine_turns": 0, "reshuffles": 0,
			"max_die_rolls": 0, "hot_dice": 0, "longest_fight": 0,
		}
		var died_in := [0, 0, 0]
		for i in runs:
			var res := _one_run(presets[preset_name], rng, str(DB.b("preset_decks", {}).get(preset_name, "")))
			acc.wins += 1 if res.win else 0
			acc.rooms += res.rooms
			acc.turns += res.turns
			acc.fights += res.fights
			acc.cards += res.cards
			acc.dead += res.dead_turns
			acc.deck += res.deck
			acc.acts += res.act_reached
			acc.relics += res.relics
			acc.max_cards_turn = maxi(acc.max_cards_turn, int(res.max_cards_turn))
			acc.engine_turns += int(res.engine_turns)
			acc.reshuffles += int(res.reshuffles)
			acc.max_die_rolls = maxi(acc.max_die_rolls, int(res.max_die_rolls))
			acc.hot_dice += int(res.hot_dice)
			acc.longest_fight = maxi(acc.longest_fight, int(res.longest_fight))
			if not res.win:
				var idx: int = clampi(int(res.act_reached), 0, 2)
				died_in[idx] += 1
		print("%s  вырождение: макс карт за ход %d   ходов по 8+ карт %d   перетасовок/бой %.2f   макс трат одного кубика за ход %d   ходов с повторной тратой %d   самый долгий бой %d ходов" % [
			preset_name.rpad(14), acc.max_cards_turn, acc.engine_turns,
			float(acc.reshuffles) / maxf(1.0, float(acc.fights)),
			acc.max_die_rolls, acc.hot_dice, acc.longest_fight])
		print("%s  винрейт %3d%%   комнат %.1f   актов %.2f   ходов/бой %.1f   карт/ход %.2f   пустых %.2f   колода %.1f   реликвий %.1f   смерти по актам %s" % [
			preset_name.rpad(14),
			int(round(100.0 * acc.wins / runs)),
			float(acc.rooms) / runs,
			float(acc.acts) / runs + 1.0,
			float(acc.turns) / max(1, acc.fights),
			float(acc.cards) / max(1, acc.turns),
			float(acc.dead) / runs,
			float(acc.deck) / runs,
			float(acc.relics) / runs,
			str(died_in),
		])
	get_tree().quit()

## Грубая оценка полезности реликвии.
##
## Бот не умеет читать текст, а брать наугад — значит мерить не сложность
## игры, а его глупость: у договоров есть цена, и случайный выбор её не
## учитывает. Веса подобраны на глаз и нужны ровно для того, чтобы бот
## предпочитал то же, что предпочёл бы человек.
const RELIC_WEIGHTS := {
	"damage_bonus": 3.0, "block_bonus": 2.5, "hand_size": 8.0,
	"cooldown_off": 7.0, "power_threshold_down": 5.0, "draw_on_power": 6.0,
	"extra_die_slot": 6.0, "combat_start_strength": 3.0, "combat_start_block": 0.8,
	"combat_start_thorns": 1.5, "poison_bonus": 1.5, "turn_block": 2.0,
	"heal_on_kill": 0.4, "heal_after_fight": 0.4, "max_hp": 0.4,
	"reroll_ones": 3.0, "element_cooldown_off": 2.0,
	"gold_bonus": 0.08, "rest_heal_bonus": 0.05, "shop_discount": 0.05,
	"start_gold": 0.03,
	"turn_self_damage": -7.0, "enemy_strength": -5.0, "enemy_hp_bonus": -0.5,
	# свойства, появившиеся вместе с печатями и новыми трофеями. Без них бот
	# оценивал новую реликвию в ноль и брал её как пустышку — и замер врал
	"burn_bonus": 2.2, "refresh_cap_up": 7.0, "light_draws": 5.0,
	"dark_free": 2.0, "resonance_up": 4.0, "ignore_rest_penalty": 3.0,
	"curse_cap": 1.0,
}

func _score_relic(id: String) -> float:
	var r := DB.relic(id)
	var score := 0.0
	for key in RELIC_WEIGHTS.keys():
		if r.has(key):
			score += float(r[key]) * float(RELIC_WEIGHTS[key])
	return score

## Лучшее из предложенного — и только если оно вообще стоит того.
func _best_relic(ids: Array, floor_value: float = 0.0) -> String:
	var best := ""
	var best_score := floor_value
	for id in ids:
		var sc := _score_relic(str(id))
		if sc > best_score:
			best_score = sc
			best = str(id)
	return best

func _one_run(preset: Array, rng: RandomNumberGenerator, deck_id: String = "") -> Dictionary:
	var bag: Array = []
	for entry in preset:
		bag.append(Die.make(int(entry[0]), str(entry[1])))

	var run := Run.start(bag, rng.randi_range(1, 1 << 30), deck_id)
	var stats := {
		"win": false, "rooms": 0, "turns": 0, "fights": 0,
		"cards": 0, "dead_turns": 0, "deck": 0, "act_reached": 0, "relics": 0,
		"max_cards_turn": 0, "engine_turns": 0, "reshuffles": 0,
		"max_die_rolls": 0, "hot_dice": 0, "longest_fight": 0,
	}

	var guard := 0
	while run.hp > 0 and not run.map.finished() and guard < 200:
		guard += 1
		var options := run.map.available()
		if options.is_empty():
			# босс акта повержен — редкая карта и следующий акт
			run.gain_relic(_best_relic(run.relics.roll_many(rng, "boss", 3)))
			var boss_reward := run.reward_options(rng, 3, "boss")
			if not boss_reward.is_empty():
				run.deck.append(boss_reward[rng.randi_range(0, boss_reward.size() - 1)])
			# награда за акт: особый кубик
			var act_dice := run.act_die_options(rng, 3)
			if not act_dice.is_empty():
				var prize: Die = act_dice[rng.randi_range(0, act_dice.size() - 1)]
				if not run.add_die(prize):
					var weakest: Die = run.bag[0]
					for d in run.bag:
						if d.quirk == "" and (weakest.quirk != "" or d.sides < weakest.sides):
							weakest = d
					run.swap_die(weakest, prize)
			run.max_hp += int(DB.b("max_hp_per_act", 14))
			run.heal(int(round(run.max_hp * float(DB.b("heal_per_act", 0.45)))))
			if not run.map.advance_act():
				break
			continue
		var node: Dictionary = options[rng.randi_range(0, options.size() - 1)]
		run.enter(node)
		stats.rooms += 1
		stats.act_reached = run.map.act_index

		match str(node.type):
			"fight", "elite", "boss":
				var res := _fight(run, run.enemy_for(node), rng, stats)
				if not res:
					stats.deck = run.deck.size()
					stats.relics = run.relics.ids.size()
					return stats
				var kind := str(node.type)
				run.relics.spend_uses()
				run.add_gold(run.gold_for(kind, rng))
				if kind == "elite":
					# договор — самый интересный выбор в игре, и стоять он
					# должен там, где игрок уже заплатил здоровьем
					if rng.randf() < float(DB.b("pact_chance", 0.4)):
						run.gain_relic(_best_relic(run.relics.roll_many(rng, "pact", 3), 2.0))
					else:
						var tier := "rare" if run.map.act_index >= 2 else ("uncommon" if run.map.act_index >= 1 else "common")
						run.gain_relic(_best_relic(run.relics.roll_many(rng, tier, 3)))
				if not run.map.act_cleared():
					run.heal(run.heal_after_fight())
					var opts := run.reward_options(rng, 3, kind)
					if not opts.is_empty():
						run.deck.append(opts[rng.randi_range(0, opts.size() - 1)])
			"event":
				_event(run, str(node.get("event", "")), rng)
			"rest":
				# бот чередует сон и заточку — как живой игрок
				if run.hp < run.max_hp * 0.7 or run.upgradable().is_empty():
					run.heal(run.rest_heal())
				else:
					var up := run.upgradable()
					run.upgrade_card(str(up[rng.randi_range(0, up.size() - 1)]))
			"treasure":
				run.add_gold(run.gold_for("treasure", rng))
				if rng.randf() < float(DB.b("treasure_relic_chance", 0.45)):
					run.gain_relic(run.relics.roll_for_room(rng, "treasure", run.map.act_index))
				else:
					run.add_gold(run.gold_for("treasure", rng))
				var dice := run.die_options(rng, 3)
				var pick: Die = dice[rng.randi_range(0, dice.size() - 1)]
				if not run.add_die(pick):
					# мешочек полон: меняем самый мелкий, если новый крупнее
					var smallest: Die = run.bag[0]
					for d in run.bag:
						if d.sides < smallest.sides:
							smallest = d
					if pick.sides > smallest.sides:
						run.swap_die(smallest, pick)
			"shop":
				_shop(run, rng)

	stats.win = run.map.finished() and run.hp > 0
	stats.deck = run.deck.size()
	stats.relics = run.relics.ids.size()
	return stats

## Бот в лавке: сначала карта, потом заточка, потом чистка.
func _shop(run: Run, rng: RandomNumberGenerator) -> void:
	for item in run.shop_stock(rng):
		var price := int(item.price)
		if run.gold < price:
			continue
		match str(item.kind):
			"card":
				if run.spend(price):
					run.deck.append(str(item.id))
			"upgrade":
				var up := run.upgradable()
				if not up.is_empty() and run.spend(price):
					run.upgrade_card(str(up[rng.randi_range(0, up.size() - 1)]))
			"relic":
				if run.spend(price):
					run.gain_relic(str(item.id))
			"remove":
				if run.deck.size() > 8 and run.spend(price):
					run.deck.erase(str(run.deck[rng.randi_range(0, run.deck.size() - 1)]))
					run.removals_bought += 1

func _fight(run: Run, foe: Dictionary, rng: RandomNumberGenerator, stats: Dictionary) -> bool:
	var combat := Combat.new()
	combat.rng = rng
	var result := {"done": false, "won": false}
	combat.fight_over.connect(func(w): result.done = true; result.won = w)
	combat.setup(run.bag, run.deck, run.hp, run.max_hp, foe, run.relics)

	# бюджет кубиков копится дробно — сколько мешочек успевает восстановить
	var tempo := Run.tempo(run.bag)
	var dice_pool := tempo
	var guard := 0

	# счётчики вырождения на этот бой
	var turn_cards := 0
	var last_turn := combat.turn
	var spends_of := {}         # кубик -> сколько раз потрачен в ЭТОТ ход
	var deck_before := combat.draw_pile.size()
	var reshuffles := 0

	while not result.done and guard < 3000:
		guard += 1
		var playable: Array = []
		for card_id in combat.hand:
			if combat.can_play(card_id):
				playable.append(card_id)

		if playable.is_empty():
			stats.dead_turns += 1
			# «Собраться» стоит здоровья: когда его мало, дешевле просто
			# закончить ход и потерпеть
			if combat.has_cooling_dice() and combat.hp > int(DB.b("regroup_cost", 4)) * 3:
				combat.regroup()
			else:
				combat.end_turn()
			dice_pool = minf(tempo * 2.0, dice_pool + tempo)
			continue

		# ход сменился — закрываем счётчик карт за ход
		if combat.turn != last_turn:
			stats.max_cards_turn = maxi(int(stats.max_cards_turn), turn_cards)
			if turn_cards >= 8:
				stats.engine_turns += 1
			turn_cards = 0
			spends_of.clear()
			last_turn = combat.turn

		var pick: String = playable[rng.randi_range(0, playable.size() - 1)]
		if _greedy:
			# двигатель ищется так: сперва то, что возвращает ход, и только
			# потом то, что наносит урон
			var best := 999
			for cid in playable:
				var w := _engine_weight(cid)
				if w < best:
					best = w
					pick = cid
		var need := int(DB.card(pick).get("dice", 1))
		if dice_pool < need:
			combat.end_turn()
			dice_pool = minf(tempo * 2.0, dice_pool + tempo)
			continue

		var pool := combat.ready_dice_for(pick)
		var chosen: Array = []
		for k in need:
			if pool.is_empty():
				break
			var idx := rng.randi_range(0, pool.size() - 1)
			chosen.append(pool[idx])
			pool.remove_at(idx)
		if chosen.size() < need:
			combat.end_turn()
			dice_pool = minf(tempo * 2.0, dice_pool + tempo)
			continue

		for d in chosen:
			spends_of[d] = int(spends_of.get(d, 0)) + 1
			var n_spent := int(spends_of[d])
			stats.max_die_rolls = maxi(int(stats.max_die_rolls), n_spent)
			if n_spent > 1:
				stats.hot_dice += 1
		combat.play_card(pick, chosen)
		stats.cards += 1
		turn_cards += 1
		dice_pool -= need
		if combat.draw_pile.size() > deck_before:
			reshuffles += 1
		deck_before = combat.draw_pile.size()

		var still := false
		for card_id in combat.hand:
			if combat.can_play(card_id):
				still = true
				break
		if not still and not result.done:
			combat.end_turn()
			dice_pool = minf(tempo * 2.0, dice_pool + tempo)

	stats.fights += 1
	stats.turns += combat.turn
	stats.max_cards_turn = maxi(int(stats.max_cards_turn), turn_cards)
	if turn_cards >= 8:
		stats.engine_turns += 1
	stats.reshuffles += reshuffles
	stats.longest_fight = maxi(int(stats.longest_fight), combat.turn)
	run.hp = combat.hp
	return result.won

## Чем меньше вес, тем раньше жадный бот сыграет карту.
## Возврат кубиков и добор — это то, из чего собирается вечный двигатель,
## поэтому именно их бот пробует в первую очередь.
func _engine_weight(card_id: String) -> int:
	var c := DB.card(card_id)
	for eff in c.get("effects", []):
		var op := str(eff.get("op", ""))
		if op in ["refresh_dice", "refresh_all", "cool_dice", "cool_all", "no_cooldown"]:
			return 0
		if op in ["draw_cards", "discard_draw", "forge_all", "forge_die"]:
			return 1
	return 2

func _event(run: Run, event_id: String, rng: RandomNumberGenerator) -> void:
	var ev := DB.event(event_id)
	var choices: Array = ev.get("choices", [])
	if choices.is_empty():
		return
	var choice: Dictionary = choices[rng.randi_range(0, choices.size() - 1)]
	if choice.has("check"):
		var die: Die = run.bag[rng.randi_range(0, run.bag.size() - 1)]
		var value := rng.randi_range(1, die.sides)
		var branch: Dictionary = choice.get(
			"success" if value >= int(choice.check.get("threshold", 0)) else "failure", {})
		run.apply_effects(branch.get("effects", []), rng)
	else:
		run.apply_effects(choice.get("effects", []), rng)
