class_name Run
extends RefCounted
## Забег: мешочек, колода, здоровье и положение на карте подземелья.

var bag: Array = []          # Array[Die]
var deck: Array = []         # Array[String]
var hp: int = 0
var max_hp: int = 0
var gold: int = 0
var removals_bought: int = 0
var relics: Relics = Relics.new()
var deck_name: String = ""
var map: DungeonMap
var rng := RandomNumberGenerator.new()

## Печать получена. Экран показывает её сам — печать приходит не за комнату,
## а за состав мешочка, и без объявления игрок просто не заметит, что правила
## изменились.
signal seal_gained(id: String)

static func start(p_bag: Array, seed_value: int = 0, deck_id: String = "") -> Run:
	var r := Run.new()
	if seed_value != 0:
		r.rng.seed = seed_value
	else:
		r.rng.randomize()
	for d in p_bag:
		r.bag.append(d.duplicate_die())
	r.deck = DB.starter_deck(deck_id)
	r.deck_name = deck_id
	r.max_hp = int(DB.b("base_hp", 70)) + Run.spare_hp(p_bag)
	r.hp = r.max_hp
	r.gold = int(DB.b("starting_gold", 60))
	r.map = DungeonMap.generate(r.rng)
	# стартовый мешочек тоже может сразу дать печать — это честно:
	# игрок собрал его сам, значит уже принял решение
	r.check_seals()
	return r

# ── сборка мешочка

static func bag_cost(p_bag: Array) -> int:
	var c := 0
	for d in p_bag:
		c += d.cost()
	return c

static func spare_hp(p_bag: Array) -> int:
	var spare: int = max(0, int(DB.b("budget", 20)) - Run.bag_cost(p_bag))
	return spare * int(DB.b("hp_per_spare_point", 2))

## Среднее число карт, которое мешочек тянет в ход: сумма 1/перезарядка.
static func tempo(p_bag: Array) -> float:
	var t := 0.0
	for d in p_bag:
		t += 1.0 / max(1, d.cooldown_max)
	return t

# ── переходы по карте

func enter(node: Dictionary) -> void:
	map.enter(node)
	for d in bag:
		d.cooldown = 0
		d.broken = false

## Враг для комнаты — вместе с правилом акта, приклеенным к нему.
## Правило едет внутри словаря врага, чтобы бою не пришлось знать про забег:
## модель боя по-прежнему ничего не знает ни о карте, ни об экране.
func enemy_for(node: Dictionary) -> Dictionary:
	var id := str(node.get("enemy", ""))
	if id == "":
		return {}
	var foe := DB.enemy(id).duplicate(true)
	foe["act_rule"] = act_rule()
	return foe

## Правило текущего акта. Первый акт возвращает правило без чисел — это тоже
## содержательный ответ: игрок читает «дополнительных правил нет».
func act_rule() -> Dictionary:
	var rules: Array = DB.b("act_rules", [])
	if rules.is_empty():
		return {}
	var i := clampi(map.act_index if map != null else 0, 0, rules.size() - 1)
	return rules[i]

func heal(amount: int) -> void:
	hp = clampi(hp + amount, 0, max_hp)

# ── реликвии

## Подобрать реликвию. Те свойства, что работают один раз (здоровье, золото),
## применяются прямо здесь; остальные модель спрашивает по ходу дела.
func gain_relic(id: String) -> bool:
	if id == "" or relics.has(id):
		return false
	relics.add(id)
	var r := DB.relic(id)
	var extra_hp := int(r.get("max_hp", 0))
	if extra_hp != 0:
		max_hp += extra_hp
		hp += extra_hp
	var coin := int(r.get("start_gold", 0))
	if coin != 0:
		add_gold(coin)
	return true

func die_slots() -> int:
	return int(DB.b("max_dice", 7)) + relics.sum("extra_die_slot")

## Мешочек не бездонный.
##
## Раньше кубики просто копились: экран сборки ограничивал мешочек семью
## слотами, а сундуки и лавка дописывали в него сколько угодно. К третьему
## акту готовых кубиков хватало на любую карту в любой ход, и вопрос «чем
## платить» пропадал вместе с игрой. Теперь лимит один и тот же везде, а
## когда мешочек полон — новый кубик не добавляется, а МЕНЯЕТ старый.
func bag_full() -> bool:
	return bag.size() >= die_slots()

func add_die(d: Die) -> bool:
	if bag_full():
		return false
	bag.append(d)
	check_seals()
	return true

## Печати стихий. Проверяются каждый раз, когда мешочек меняется.
##
## Мешочек до сих пор влиял только на текущий бой: три огненных кубика — это
## просто три кубика. Печать превращает состав мешочка в долгую цель забега,
## и это ровно та механика, за которую в Isaac любят «собери три предмета
## одной темы»: награда не за удачу, а за решение.
##
## Возвращает список полученных печатей — экрану есть что показать.
func check_seals() -> Array:
	var gained: Array = []
	var counts := {}
	for d in bag:
		# глубокий кубик считается за два — свойство ровно про печати
		var weight := 2 if d.has_quirk("deep") else 1
		counts[d.element] = int(counts.get(d.element, 0)) + weight
		# призматический кубик считается за любую стихию — он и в бою такой
		if d.has_quirk("prism"):
			for e in DB.relics.get("seals", {}).keys():
				if str(e) != d.element:
					counts[e] = int(counts.get(e, 0)) + 1
	for element in DB.relics.get("seals", {}).keys():
		var id := str(DB.relics["seals"][element])
		if relics.has(id):
			continue
		if int(counts.get(element, 0)) >= int(DB.b("seal_dice", 3)):
			if gain_relic(id):
				gained.append(id)
				seal_gained.emit(id)
	var balance_id := str(DB.relics.get("seal_balance_id", ""))
	if balance_id != "" and not relics.has(balance_id):
		var all_five := true
		for element in DB.relics.get("seals", {}).keys():
			if int(counts.get(element, 0)) < 1:
				all_five = false
				break
		if all_five and gain_relic(balance_id):
			gained.append(balance_id)
			seal_gained.emit(balance_id)
	return gained

func swap_die(old_die: Die, new_die: Die) -> void:
	var idx := bag.find(old_die)
	if idx >= 0:
		bag[idx] = new_die
	else:
		bag.append(new_die)
	check_seals()

func rest_heal() -> int:
	var base := float(DB.b("rest_heal", 0.4))
	var raw := max_hp * base * (1.0 + relics.sum("rest_heal_bonus") / 100.0)
	return int(round(raw * (1.0 - _rest_penalty())))

## Лечение после боя — базовое плюс то, что дают реликвии.
func heal_after_fight() -> int:
	var raw := int(DB.b("heal_between_fights", 18)) + relics.sum("heal_after_fight")
	return int(round(raw * (1.0 - _rest_penalty())))

## Насколько акт урезает лечение. Чем глубже курган, тем дороже каждая ошибка:
## одни только цифры врага не создают напряжения, а вот тающий запас здоровья —
## создаёт, потому что заставляет считать наперёд.
func _rest_penalty() -> float:
	if relics.sum("ignore_rest_penalty") > 0:
		return 0.0
	return clampf(float(act_rule().get("rest_penalty", 0.0)), 0.0, 0.9)

func price_with_discount(price: int) -> int:
	return maxi(1, int(round(price * (1.0 - relics.sum("shop_discount") / 100.0))))

# ── золото и лавка

func add_gold(n: int) -> void:
	gold = max(0, gold + n)

func spend(n: int) -> bool:
	if gold < n:
		return false
	gold -= n
	return true

## Награда золотом за зачищенную комнату.
func gold_for(kind: String, p_rng: RandomNumberGenerator) -> int:
	var table: Dictionary = DB.b("gold", {})
	var span: Array = table.get(kind, [10, 16])
	var base := p_rng.randi_range(int(span[0]), int(span[1]))
	return int(round(base * (1.0 + relics.sum("gold_bonus") / 100.0)))

func _card_price(id: String, p_rng: RandomNumberGenerator) -> int:
	var table: Dictionary = DB.b("prices", {})
	var span: Array = table.get(DB.rarity(id), [50, 60])
	return p_rng.randi_range(int(span[0]), int(span[1]))

## Витрина лавки: три карты, два кубика, чистка колоды и улучшение.
## Цены случайные в узком диапазоне — чтобы лавка не была таблицей.
func shop_stock(p_rng: RandomNumberGenerator) -> Array:
	var stock: Array = []
	var taken: Array = []
	var favour := _favourite_archetype()
	# лавка редкая — витрина чуть шире обычного
	for i in 3:
		var r := _roll_rarity(p_rng, "fight")
		var id := _pick_of_rarity(p_rng, r, taken, favour)
		if id == "":
			continue
		taken.append(id)
		stock.append({"kind": "card", "id": id, "price": price_with_discount(_card_price(id, p_rng))})
	for i in 2:
		# первый кубик обычный и подъёмный, второй — всегда с особым свойством:
		# в лавку ходят именно за тем, чего не выдаст сундук
		var die: Die = die_options(p_rng, 1, 0.0 if i == 0 else 1.0)[0]
		var table: Dictionary = DB.b("prices", {})
		var span: Array = table.get("die", [90, 130])
		var price: int = p_rng.randi_range(int(span[0]), int(span[1])) + die.cost() * 8
		price += int(DB.quirk_of(die.quirk).get("price", 0)) / 2
		stock.append({"kind": "die", "die": die, "price": price_with_discount(price)})
	var base_removal := int(DB.b("removal_price", 70))
	stock.append({"kind": "remove", "price": price_with_discount(base_removal + removals_bought * 20)})
	stock.append({"kind": "upgrade", "price": price_with_discount(int(DB.b("upgrade_price", 95)))})
	if relics.sum("shop_relic") >= 0:
		var rid := relics.roll(p_rng, "uncommon" if p_rng.randf() < 0.6 else "rare")
		if rid != "":
			stock.append({"kind": "relic", "id": rid, "price": price_with_discount(p_rng.randi_range(140, 190))})
	return stock

## ── Награды: карты по редкости
##
## Шанс редкой карты не фиксированный: если редкие давно не выпадали, он растёт.
## Это «анти-невезение» — механика из Slay the Spire, чтобы забег не разваливался
## из-за череды пустых наград. rare_offset копится и обнуляется на редкой карте.
var rare_offset: float = -5.0

const RARITY_ODDS := {
	"fight":    {"common": 60.0, "uncommon": 37.0, "rare": 3.0},
	"elite":    {"common": 50.0, "uncommon": 40.0, "rare": 10.0},
	"treasure": {"common": 45.0, "uncommon": 43.0, "rare": 12.0},
	"boss":     {"common": 0.0,  "uncommon": 0.0,  "rare": 100.0},
}

func _roll_rarity(p_rng: RandomNumberGenerator, kind: String) -> String:
	var odds: Dictionary = RARITY_ODDS.get(kind, RARITY_ODDS["fight"])
	var rare_chance: float = clampf(float(odds["rare"]) + rare_offset, 0.0, 45.0)
	if float(odds["rare"]) >= 100.0:
		rare_chance = 100.0
	var roll := p_rng.randf() * 100.0
	if roll < rare_chance:
		return "rare"
	var uncommon_chance: float = float(odds["uncommon"])
	if roll < rare_chance + uncommon_chance:
		return "uncommon"
	return "common"

## Какой архетип уже собирается в колоде — под него чуть чаще подкидываем карты.
## Без этого набор наград случаен и билд не складывается.
func _favourite_archetype() -> String:
	var counts := {}
	for id in deck:
		var a := str(DB.card(str(id)).get("archetype", ""))
		if a == "":
			continue
		counts[a] = int(counts.get(a, 0)) + 1
	var best := ""
	var best_n := 1
	for a in counts.keys():
		if int(counts[a]) > best_n:
			best_n = int(counts[a])
			best = str(a)
	return best

func _pick_of_rarity(p_rng: RandomNumberGenerator, r: String, taken: Array, favour: String) -> String:
	var pool: Array = []
	for cid in DB.cards_of_rarity(r):
		if taken.has(cid):
			continue
		pool.append(cid)
	if pool.is_empty():
		return ""
	# карты «своего» архетипа кладём в мешок дважды — вдвое выше шанс
	var weighted: Array = []
	for cid in pool:
		weighted.append(cid)
		if favour != "" and str(DB.card(cid).get("archetype", "")) == favour:
			weighted.append(cid)
	return str(weighted[p_rng.randi_range(0, weighted.size() - 1)])

## kind: fight | elite | treasure | boss
func reward_options(p_rng: RandomNumberGenerator, count: int = 3, kind: String = "fight") -> Array:
	var favour := _favourite_archetype()
	var out: Array = []
	var got_rare := false
	for i in count:
		var r := _roll_rarity(p_rng, kind)
		var pick := _pick_of_rarity(p_rng, r, out, favour)
		if pick == "":
			for fallback in ["uncommon", "common", "rare"]:
				pick = _pick_of_rarity(p_rng, fallback, out, favour)
				if pick != "":
					break
		if pick == "":
			break
		if DB.rarity(pick) == "rare":
			got_rare = true
		out.append(pick)
	if kind != "boss":
		if got_rare:
			rare_offset = -5.0
		else:
			rare_offset = minf(rare_offset + 1.0, 40.0)
	return out

## Случайная карта нужной редкости — для событий и лавки.
func random_card(p_rng: RandomNumberGenerator, r: String = "") -> String:
	if r == "":
		r = ["common", "common", "uncommon", "uncommon", "rare"][p_rng.randi_range(0, 4)]
	return _pick_of_rarity(p_rng, r, [], _favourite_archetype())

## Проклятие в колоду — события и часть врагов подкидывают их.
var curses_taken: int = 0

func add_curse(p_rng: RandomNumberGenerator) -> String:
	var cap := relics.sum("curse_cap")
	if cap > 0 and curses_taken >= cap:
		return ""
	var curses := DB.cards_of_rarity("curse")
	if curses.is_empty():
		return ""
	curses_taken += 1
	var id := str(curses[p_rng.randi_range(0, curses.size() - 1)])
	deck.append(id)
	return id

## Карты колоды, которые можно улучшить.
func upgradable() -> Array:
	var out: Array = []
	for id in deck:
		if DB.can_upgrade(str(id)):
			out.append(str(id))
	return out

func upgrade_card(id: String) -> bool:
	var idx := deck.find(id)
	if idx < 0:
		return false
	deck[idx] = DB.upgraded_id(id)
	return true

## Награда за акт: три ОСОБЫХ кубика на выбор, по одному разу за акт.
##
## Обычные кубики отличаются только числом граней, и мешочек к третьему акту
## перестаёт быть интересным. Особые кубики — единственное, что меняет сам
## бросок, поэтому их нельзя оставлять на волю случая: за каждый пройденный
## акт игрок обязан получить один.
func act_die_options(p_rng: RandomNumberGenerator, count: int = 3) -> Array:
	return die_options(p_rng, count, 1.0)

## Кубики на выбор. quirk_chance — с какой вероятностью кубик будет особым;
## чем глубже забег, тем чаще попадаются необычные.
func die_options(p_rng: RandomNumberGenerator, count: int = 3, quirk_chance: float = -1.0) -> Array:
	var types := DB.die_types()
	var elements: Array = []
	for k in Palette.ELEMENTS.keys():
		if k != "none":
			elements.append(k)
	if quirk_chance < 0.0:
		# Особые кубики раздавались из каждого сундука, и «особый» перестало
		# что-то значить. Теперь гарантированный кубик даёт трофей акта, а
		# случайные попадаются редко — так у награды снова есть вес.
		quirk_chance = 0.08 + 0.06 * float(map.act_index if map != null else 0)
	var quirks := DB.quirk_ids()
	var out: Array = []
	for i in count:
		var sides: int = types[p_rng.randi_range(0, types.size() - 1)]
		var elm: String = str(elements[p_rng.randi_range(0, elements.size() - 1)])
		var q := ""
		if not quirks.is_empty() and p_rng.randf() < quirk_chance:
			q = str(quirks[p_rng.randi_range(0, quirks.size() - 1)])
		out.append(Die.make(sides, elm, q))
	return out

# ── эффекты событий

## Применяет список эффектов и возвращает строки для показа игроку.
func apply_effects(effects: Array, p_rng: RandomNumberGenerator) -> Array:
	var lines: Array = []
	for eff in effects:
		match str(eff.get("op", "")):
			"heal":
				var n := int(eff.get("amount", 0))
				heal(n)
				lines.append("+%d здоровья" % n)
			"damage":
				var d := int(eff.get("amount", 0))
				hp = max(0, hp - d)
				lines.append("−%d здоровья" % d)
			"max_hp":
				var m := int(eff.get("amount", 0))
				max_hp = max(10, max_hp + m)
				hp = min(hp, max_hp)
				if m >= 0:
					lines.append("+%d к максимуму здоровья" % m)
				else:
					lines.append("%d к максимуму здоровья" % m)
			"add_card":
				var id := str(eff.get("id", ""))
				if id == "":
					id = random_card(p_rng, str(eff.get("rarity", "")))
				if id == "":
					continue
				deck.append(id)
				lines.append("В колоду: «%s»" % DB.card_name(id))
			"gold":
				var g := int(eff.get("amount", 0))
				if g >= 0:
					add_gold(g)
					lines.append("+%d золота" % g)
				else:
					var paid: int = min(gold, -g)
					gold -= paid
					lines.append("−%d золота" % paid)
			"add_curse":
				var cid := add_curse(p_rng)
				if cid != "":
					lines.append("В колоду легло проклятие: «%s»" % DB.card_name(cid))
			"upgrade_card":
				var up_list := upgradable()
				if up_list.is_empty():
					lines.append("Улучшать нечего")
				else:
					var target := str(up_list[p_rng.randi_range(0, up_list.size() - 1)])
					upgrade_card(target)
					lines.append("Карта улучшена: «%s»" % DB.card_name(DB.upgraded_id(target)))
			"remove_card":
				var removed := _remove_most_common()
				if removed != "":
					lines.append("Из колоды убрана «%s»" % DB.card_name(removed))
				else:
					lines.append("Убирать нечего")
			"add_die":
				var die := Die.make(int(eff.get("sides", 6)), str(eff.get("element", "fire")))
				bag.append(die)
				lines.append("В мешочек: %s (%s)" % [die.label(), Palette.element_name(die.element)])
			"lose_die":
				var lost := _remove_smallest_die()
				if lost != "":
					lines.append("Из мешочка ушёл %s" % lost)
			"upgrade_die":
				var up := _upgrade_slowest_die()
				if up != "":
					lines.append("%s теперь возвращается быстрее" % up)
				else:
					lines.append("Все кубики и так быстрые")
	return lines

func _remove_most_common() -> String:
	var counts := {}
	for id in deck:
		counts[id] = int(counts.get(id, 0)) + 1
	var best := ""
	var best_n := 1
	for id in counts.keys():
		if int(counts[id]) > best_n:
			best_n = int(counts[id])
			best = str(id)
	if best == "":
		return ""
	deck.erase(best)
	return best

func _remove_smallest_die() -> String:
	if bag.size() <= 2:
		return ""
	var smallest: Die = bag[0]
	for d in bag:
		if d.sides < smallest.sides:
			smallest = d
	var label := smallest.label()
	bag.erase(smallest)
	return label

func _upgrade_slowest_die() -> String:
	var target: Die = null
	for d in bag:
		if d.cooldown_max <= 1:
			continue
		if target == null or d.cooldown_max > target.cooldown_max:
			target = d
	if target == null:
		return ""
	target.cooldown_max -= 1
	return target.label()
