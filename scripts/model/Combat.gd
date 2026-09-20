class_name Combat
extends RefCounted
## Вся логика боя. Ничего не знает про экран — только правила.
## Благодаря этому её можно прогонять без графики (см. tools/simulate.gd).

signal logged(text: String, kind: String)      # kind: plain | dmg | block | good | power | enemy
signal foe_damaged(amount: int)
signal player_damaged(amount: int)
signal player_blocked(amount: int)
signal power_triggered()
signal changed()
signal fight_over(player_won: bool)

# --- герой ---
var bag: Array = []            # Array[Die]
var draw_pile: Array = []      # Array[String] (id карт)
var discard_pile: Array = []
var hand: Array = []
var hp: int = 70
var max_hp: int = 70
var block: int = 0
var strength: int = 0
var vulnerable: int = 0        # ходов, пока игрок получает +50%
var weak_turns: int = 0        # ходов, пока удары игрока слабее
var weak_amount: int = 0
var thorns: int = 0            # враг получает столько за каждый свой удар
var block_retained_once: bool = false   # блок переживёт один конец хода
var block_retained: bool = false        # блок не сгорает до конца боя
var exhausted: Array = []      # карты, сгоревшие в этом бою

# --- враг ---
var foe_name: String = ""
var foe_art: String = ""
var foe_hp: int = 0
var foe_max_hp: int = 0
var foe_block: int = 0
var foe_poison: int = 0
var foe_vulnerable: int = 0
var foe_weak_turns: int = 0
var foe_weak_amount: int = 0
var foe_frozen: bool = false
var foe_poison_slow: bool = false      # яд убывает вдвое медленнее («Чума»)
var foe_burn: int = 0                  # ожог: бьёт каждый ход и не слабеет
var foe_strength: int = 0              # прибавка к урону всех его атак
var foe_plated: int = 0                # броня: не сгорает, тает от ударов
var foe_thorns: int = 0                # игрок получает столько за свой удар
var foe_moves: Array = []
var foe_note: String = ""
var foe_next: Dictionary = {}          # действие, объявленное на этот ход
var _foe_last_id: String = ""
var _foe_repeat: int = 0
var _foe_uses: Dictionary = {}         # id -> сколько раз применено
var _foe_forced: String = ""           # замах жёстко задаёт следующее действие

var turn: int = 0
var finished: bool = false

var relics: Relics = Relics.new()   ## реликвии забега: их числа подмешиваются в правила

## Сколько кубиков ещё можно вернуть в строй в этот ход.
##
## Это потолок поверх ВСЕХ источников возврата сразу: карт, откликов стихий,
## реликвий. Без него игра ломается: «Разгон» тратил два кубика и возвращал
## три, то есть каждый розыгрыш был в плюс, и ход не заканчивался никогда.
## Чинить это по одной карте бесполезно — дыру надо закрывать правилом,
## как потолок энергии в Slay the Spire.
var refresh_left: int = 0

## В какой ход свет уже сработал на добор.
## Добор — самый сильный ресурс в колодострое, и отклик света давал его
## столько раз, сколько карт со светлыми кубиками успел разыграть игрок.
## Один добор за ход: дальше свет платит силой, а не картами.
var light_drew_turn: int = -1
var _light_draws_done: int = 0

## Сколько раз каждая карта уже сыграна в этом бою.
## Растущие карты — способ дать колоде «поздний ход»: карта, которая во втором
## розыгрыше сильнее, чем в первом, награждает за длинный бой и делает
## осмысленным решение НЕ играть её сразу.
var _plays: Dictionary = {}

## Правило акта и налог босса. Оба живут в данных и оба действуют весь бой.
##
## Сложность нельзя делать только здоровьем врага: третий акт тогда — это
## первый, но дольше. Правило акта меняет, КАК идёт бой (во втором акте не
## проходит чистый разгон — у всех броня; в третьем нельзя тянуть — враг
## крепчает каждые три хода). Налог босса бьёт по одной конкретной экономике
## игрока, чтобы босс ломал привычный ход игры, а не просто долго умирал.
var act_rule: Dictionary = {}
var foe_tax: Dictionary = {}

var rng := RandomNumberGenerator.new()

# ─────────────────────────────────────────── запуск

func setup(p_bag: Array, p_deck: Array, p_hp: int, p_max_hp: int, foe: Dictionary, p_relics: Relics = null) -> void:
	bag = p_bag
	for d in bag:
		d.cooldown = 0
		d.broken = false
	hp = p_hp
	max_hp = p_max_hp
	if p_relics != null:
		relics = p_relics
	# реликвии, которые срабатывают на входе в бой
	block = relics.sum("combat_start_block")
	strength = relics.sum("combat_start_strength")
	vulnerable = 0
	thorns = relics.sum("combat_start_thorns")
	block_retained_once = false
	block_retained = false
	exhausted = []
	turn = 0
	finished = false

	draw_pile = p_deck.duplicate()
	_shuffle(draw_pile)
	discard_pile = []
	hand = []

	foe_name = str(foe.get("name", "Враг"))
	foe_art = str(foe.get("art", "scavenger"))
	# договоры умеют делать врагов крепче и злее — это их цена
	var hp_bonus := 1.0 + relics.sum("enemy_hp_bonus") / 100.0
	foe_hp = int(round(int(foe.get("hp", 50)) * hp_bonus))
	foe_max_hp = foe_hp
	foe_moves = foe.get("moves", foe.get("pattern", []))
	foe_note = str(foe.get("_", ""))
	foe_block = 0
	foe_poison = 0
	foe_vulnerable = 0
	foe_weak_turns = 0
	foe_weak_amount = 0
	foe_frozen = false
	foe_poison_slow = false
	foe_burn = 0
	foe_strength = relics.sum("enemy_strength")
	foe_plated = 0
	foe_thorns = 0
	_foe_last_id = ""
	_foe_repeat = 0
	_foe_uses = {}
	_foe_forced = str(foe.get("first_move", ""))
	weak_turns = 0
	weak_amount = 0

	act_rule = foe.get("act_rule", {})
	foe_tax = foe.get("tax", {})
	light_drew_turn = -1
	_light_draws_done = 0
	_plays = {}

	_log("Перед тобой: %s" % foe_name, "enemy")
	var plate: int = int(act_rule.get("foe_plated", 0))
	if plate > 0:
		foe_plated += plate
		_log("%s: враг закован в %d брони" % [str(act_rule.get("name", "Правило акта")), plate], "enemy")
	if not foe_tax.is_empty():
		_log("%s. %s" % [str(foe_tax.get("name", "Налог")), str(foe_tax.get("text", ""))], "enemy")
	_choose_next()
	begin_turn()

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t

func _log(text: String, kind: String = "plain") -> void:
	logged.emit(text, kind)

# ─────────────────────────────────────────── ход игрока

func begin_turn() -> void:
	turn += 1
	if block_retained or block_retained_once:
		block_retained_once = false
	else:
		block = 0
	for d in bag:
		if d.cooldown > 0:
			d.cooldown -= 1
	_log("Ход %d" % turn, "plain")
	refresh_left = int(DB.b("refresh_cap", 2)) + relics.sum("refresh_cap_up")
	light_drew_turn = -1
	_light_draws_done = 0
	# новый ход — новые броски
	for d in bag:
		d.rolled = -1

	var per_turn_block := relics.sum("turn_block")
	if per_turn_block > 0:
		block += per_turn_block
		player_blocked.emit(per_turn_block)
	var toll := relics.sum("turn_self_damage")
	if toll > 0 and turn > 1:
		hp -= toll
		_log("Реликвия берёт своё: −%d" % toll, "dmg")
		player_damaged.emit(toll)

	draw_cards(maxi(1, int(DB.b("hand_size", 5)) + relics.sum("hand_size") \
			+ int(foe_tax.get("hand_size", 0))))
	changed.emit()

func draw_cards(n: int) -> void:
	for i in n:
		if draw_pile.is_empty():
			draw_pile = discard_pile.duplicate()
			discard_pile = []
			_shuffle(draw_pile)
		if draw_pile.is_empty():
			return
		var drawn := str(draw_pile.pop_back())
		hand.append(drawn)
		_on_card_drawn(drawn)

## Проклятия действуют самим фактом попадания в руку — играть их нельзя.
func _on_card_drawn(card_id: String) -> void:
	var c := DB.card(card_id)
	if not bool(c.get("unplayable", false)):
		return
	for eff in c.get("effects", []):
		match str(eff.get("op", "")):
			"rust_on_draw":
				var live: Array = []
				for d in bag:
					if not d.broken:
						live.append(d)
				if not live.is_empty():
					var pick: Die = live[rng.randi_range(0, live.size() - 1)]
					pick.cooldown += int(eff.get("base", 1))
					_log("Ржавчина: %s остывает дольше" % pick.label(), "dmg")
			"hurt_on_draw":
				var n := int(eff.get("base", 0))
				hp -= n
				_log("Груз давит: −%d" % n, "dmg")
				player_damaged.emit(n)

func ready_dice_for(card_id: String) -> Array:
	var c := DB.card(card_id)
	var min_faces := int(c.get("min_faces", 0))
	var needs_element := bool(c.get("require_element", false))
	var elm := str(c.get("element", "none"))
	var out: Array = []
	for d in bag:
		if not d.is_ready():
			continue
		if d.sides < min_faces and not d.has_quirk("hollow"):
			continue
		if needs_element and not d.suits(elm):
			continue
		out.append(d)
	return out

func can_play(card_id: String) -> bool:
	var c := DB.card(card_id)
	if bool(c.get("unplayable", false)):
		return false
	return ready_dice_for(card_id).size() >= int(c.get("dice", 1))

## Бросок кубика. Если кубик уже брошен в этом ходу, возвращается то же
## число: перебросов нет (см. Die.rolled).
## Применить свойства кубика к выпавшему числу.
##
## Это вынесено из roll() отдельной функцией не для красоты. Физический
## бросок в лотке читает верхнюю грань и кладёт её в кубик напрямую, минуя
## roll(), — и все свойства проходили мимо. «Тяжёлый» d12 честно выбрасывал
## единицу, хотя на кубике написано «не бывает ниже трети граней». Теперь
## обе дороги, и виртуальная и настоящая, идут через одно место.
func apply_quirks(d: Die, value: int) -> int:
	var before := value
	# «Кубик мертвеца» и счастливый кубик: единица — не приговор
	if value == 1 and (relics.sum("reroll_ones") > 0 or d.has_quirk("lucky")):
		value = rng.randi_range(1, d.sides)
	# тяжёлый кубик просто не умеет падать совсем низко
	if d.has_quirk("heavy"):
		value = maxi(value, int(ceil(d.sides / 3.0)))
	# свойства с ценой: прибавка к броску всегда чем-то оплачена —
	# перезарядкой (жадный, гулкий), здоровьем (голодный) или потолком (стылый)
	if d.has_quirk("greedy"):
		value += 2
	if d.has_quirk("hungry"):
		value += 3
		hp -= 1
		player_damaged.emit(1)
		_log("Голодный кубик берёт 1 здоровья", "dmg")
	if d.has_quirk("twin"):
		var kin := 0
		for other in bag:
			if other != d and other.is_ready() and other.element == d.element:
				kin += 1
		if kin > 0:
			value += kin
	if d.has_quirk("sharp") and not is_power(value, d.sides, d):
		value = maxi(1, value - 1)
	if d.has_quirk("cold"):
		value = mini(value, maxi(1, int(d.sides / 2)))
	value = clampi(value, 1, d.sides + 6)
	if value != before:
		_log("%s: выпало %d, свойство даёт %d" % [d.label(), before, value], "power")
	return value

## Бросок кубика. Если кубик уже брошен в этом ходу, возвращается то же
## число: перебросов нет (см. Die.rolled).
func roll(d: Die) -> int:
	if d.rolled >= 0:
		return d.rolled
	d.rolled = apply_quirks(d, rng.randi_range(1, d.sides))
	return d.rolled

## Сколько ходов кубик будет остывать. Меньше одного не бывает — иначе
## реликвии на перезарядку ломают весь темп боя.
func _cooldown_for(d: Die) -> int:
	var off := relics.sum("cooldown_off") + relics.sum_for_element("element_cooldown_off", d.element)
	off += relics.cooldown_shift(d.element)
	if d.has_quirk("swift"):
		off += 1
	if d.has_quirk("cold"):
		return 1
	if d.has_quirk("greedy"):
		off -= 1
	if d.has_quirk("loud"):
		off -= 1
	# налог босса на крупные кубики: d20 перестаёт быть бесплатно лучшим
	var tax := 0
	if d.sides >= int(foe_tax.get("big_dice_faces", 99)):
		tax = int(foe_tax.get("big_dice_cooldown", 0))
	return maxi(1, d.cooldown_max - off + tax)

## Порог Мощи с учётом реликвий, которые его опускают.
func is_power(value: int, sides: int, d: Die = null) -> bool:
	var down := relics.sum("power_threshold_down")
	if d != null and d.has_quirk("keen"):
		down += 1
	return value >= DB.power_threshold(sides) - down

## Разыграть карту. dice — выбранные кубики, rolls — уже выпавшие значения
## (экран бросает заранее ради анимации; симуляция бросает тут же).
func play_card(card_id: String, dice: Array, rolls: Array = []) -> void:
	if finished:
		return
	var c := DB.card(card_id)
	if c.is_empty():
		push_error("Неизвестная карта: %s" % card_id)
		return

	if rolls.is_empty():
		for d in dice:
			rolls.append(roll(d))

	var total := 0
	for r in rolls:
		total += int(r)
	var faces := 0
	for d in dice:
		faces += d.sides
	var card_element := str(c.get("element", "none"))
	var matches := 0
	for d in dice:
		if d.suits(card_element):
			matches += 1
	var power := true
	for i in dice.size():
		if not is_power(int(rolls[i]), dice[i].sides, dice[i]):
			power = false
			break

	# кубики уходят на перезарядку; реликвии и свойства могут её изменить.
	# Звонкий кубик при Мощи остаётся в строю — это и есть его смысл.
	for i in dice.size():
		var d: Die = dice[i]
		d.rolled = -1   # кубик потрачен, число с него снимается
		if d.has_quirk("echo") and is_power(int(rolls[i]), d.sides, d):
			_log("%s звенит и остаётся в строю" % d.label(), "power")
			continue
		d.cooldown = _cooldown_for(d)

	var parts: Array = []
	for i in dice.size():
		parts.append("%s:%d" % [dice[i].label(), int(rolls[i])])
	var head := "%s — %s" % [str(c.get("name", card_id)), " + ".join(parts)]
	if dice.size() > 1:
		head += " = %d" % total
	_log(head, "plain")

	if power:
		_log("Мощь!", "power")
		power_triggered.emit()
		var bonus := relics.sum("damage_on_power")
		if bonus > 0:
			_damage_foe(bonus)
		var extra := relics.sum("draw_on_power")
		if extra > 0:
			draw_cards(extra)
			_log("Мощь тянет карту", "good")

	var plays_before := int(_plays.get(card_id, 0))
	_plays[card_id] = plays_before + 1
	var ctx := {
		"dice": dice, "rolls": rolls, "total": total,
		"faces": faces, "matches": matches, "power": power,
		"card_element": str(c.get("element", "none")),
		"plays": plays_before,
	}
	for eff in c.get("effects", []):
		_apply_effect(eff, ctx)

	if matches > 0 and card_element != "none":
		var loud := 0
		for d in dice:
			if d.has_quirk("loud") and d.suits(card_element):
				loud += 1
		_resonate(card_element, matches + loud + relics.sum("resonance_up"))

	var idx := hand.find(card_id)
	if idx >= 0:
		hand.remove_at(idx)
	if bool(c.get("exhaust", false)):
		exhausted.append(card_id)
		_log("«%s» сгорает" % str(c.get("name", card_id)), "plain")
	else:
		discard_pile.append(card_id)

	changed.emit()
	_check_end()

## Что даст карта, если оплатить её этими кубиками — без изменения состояния.
## Нужно, чтобы игрок видел исход ДО оплаты: непоказанные модификаторы —
## главная претензия к интерфейсам подобных игр.
func preview(card_id: String, dice: Array) -> Dictionary:
	var c := DB.card(card_id)
	var effects: Array = c.get("effects", [])
	if effects.is_empty() or dice.is_empty():
		return {}
	var eff: Dictionary = effects[0]
	var op := str(eff.get("op", ""))
	if op in ["refresh_dice", "draw_cards", "break_dice", "freeze_if_power", "refresh_all", "forge_all",
			"refresh_all_except_paid", "cool_all", "cool_paid", "forge_die", "retain_block",
			"retain_block_forever", "poison_persist", "damage_per_ready", "damage_from_block",
			"cool_dice", "amplify_rot", "no_cooldown", "exhaust_dice", "freeze", "discard_draw"]:
		return {}
	var elm := str(c.get("element", "none"))
	var matches := 0
	var faces := 0
	var hi_total := 0
	var lo_rolls: Array = []
	var hi_rolls: Array = []
	for d in dice:
		faces += d.sides
		hi_total += d.sides
		lo_rolls.append(1)
		hi_rolls.append(d.sides)
		if d.element == elm:
			matches += 1
	var base := {"dice": dice, "faces": faces, "matches": matches, "card_element": elm}
	var lo_ctx := base.duplicate()
	lo_ctx.merge({"rolls": lo_rolls, "total": dice.size(), "power": false})
	var hi_ctx := base.duplicate()
	hi_ctx.merge({"rolls": hi_rolls, "total": hi_total, "power": true})
	var lo := _value(eff, lo_ctx)
	var hi := _value(eff, hi_ctx)
	if op in ["damage", "multi_hit", "reroll_best_damage"]:
		lo += strength
		hi += strength
		if foe_vulnerable > 0:
			lo = int(round(lo * float(DB.b("vulnerable_multiplier", 1.5))))
			hi = int(round(hi * float(DB.b("vulnerable_multiplier", 1.5))))
	return {"op": op, "min": maxi(0, lo), "max": maxi(0, hi)}

static func preview_word(op: String) -> String:
	match op:
		"damage", "multi_hit", "reroll_best_damage": return "урон"
		"block": return "блок"
		"poison": return "яд"
		"heal": return "лечение"
		"strength": return "сила"
		"weaken": return "слабость"
	return ""

# ─────────────────────────────────────────── эффекты карт

func _value(eff: Dictionary, ctx: Dictionary) -> int:
	var v: float = 0.0
	v = ctx.total * float(eff.get("roll_mult", 1))
	# грани только ДОБАВЛЯЮТСЯ к броску и никогда его не заменяют: иначе
	# крупный кубик даёт стабильный урон, и весь выбор «каким платить»
	# схлопывается в «всегда самым большим»
	v += ctx.faces * float(eff.get("faces_mult", 0))
	v += float(eff.get("base", 0))
	v += float(eff.get("per_element", 0)) * ctx.matches
	if eff.has("per_small"):
		var small := 0
		for d in ctx.dice:
			if d.sides <= 6:
				small += 1
		v += float(eff.get("per_small", 0)) * small
	if eff.has("missing_hp"):
		v += float(max_hp - hp) * float(eff.get("missing_hp", 0))
	if eff.has("per_play"):
		v += float(eff.get("per_play", 0)) * float(ctx.get("plays", 0))
	if eff.has("per_hand"):
		v += float(eff.get("per_hand", 0)) * maxi(0, hand.size() - 1)
	if eff.has("plus_burn"):
		v += foe_burn * float(eff.get("burn_mult", 1.0))
		# ожог не слабеет сам, поэтому карта, которая бьёт на весь ожог,
		# обязана его тратить — иначе накопление ничего не стоит
		var burn_spend := float(eff.get("spend_burn", 0.0))
		if burn_spend > 0.0:
			foe_burn = int(foe_burn * (1.0 - burn_spend))
	if eff.has("plus_poison"):
		v += foe_poison * float(eff.get("poison_mult", 1.0))
		# накопленный яд теперь имеет цену: карта, которая бьёт на весь яд
		# и не тратит его, превращает накопление в бесплатный множитель
		var burn_share := float(eff.get("spend_poison", 0.0))
		if burn_share > 0.0:
			foe_poison = int(foe_poison * (1.0 - burn_share))
	if ctx.power:
		for d in ctx.dice:
			if d.has_quirk("sharp"):
				v += 4
		v += ctx.faces * float(eff.get("pow_faces", 0))
		v += float(eff.get("pow_flat", 0))
		if eff.has("pow_mult"):
			v *= float(eff.get("pow_mult", 1))
	if eff.has("sum_threshold") and ctx.total >= int(eff.get("sum_threshold", 999)):
		v += float(eff.get("threshold_bonus", 0))
	if eff.has("min"):
		v = max(v, float(eff.get("min", 0)))
	return int(round(v))

## Счётные эффекты — «сколько кубиков вернуть», «сколько карт добрать» —
## считаются БЕЗ броска. Иначе число, написанное на карте, ничего не значит:
## всю работу делает ограничитель, а игрок не понимает, что он купил.
func _count(eff: Dictionary, ctx: Dictionary) -> int:
	var v := float(eff.get("base", 0))
	v += float(eff.get("per_element", 0)) * ctx.matches
	if eff.has("per_small"):
		var small := 0
		for d in ctx.dice:
			if d.sides <= 6:
				small += 1
		v += float(eff.get("per_small", 0)) * small
	if ctx.power:
		v += float(eff.get("pow_flat", 0))
	return int(round(v))

func _apply_effect(eff: Dictionary, ctx: Dictionary) -> void:
	var op := str(eff.get("op", ""))
	match op:
		"damage":
			if eff.get("strip_block_on_threshold", false) \
			   and ctx.total >= int(eff.get("sum_threshold", 999)):
				foe_block = 0
				_log("Блок врага сорван", "block")
			_damage_foe(_value(eff, ctx), eff)

		"multi_hit":
			# каждый кубик бьёт отдельно — свой бонус за стихию у каждого удара
			for i in ctx.dice.size():
				var die: Die = ctx.dice[i]
				var one := {
					"dice": [die], "rolls": [ctx.rolls[i]],
					"total": int(ctx.rolls[i]), "faces": die.sides,
					"matches": 1 if die.element == str(ctx.card_element) else 0,
					"power": is_power(int(ctx.rolls[i]), die.sides, die),
					"card_element": ctx.card_element,
				}
				_damage_foe(_value(eff, one), eff)

		"roll_twice_sum":
			var again := rng.randi_range(1, ctx.dice[0].sides)
			_log("Второй бросок: %d" % again, "plain")
			var both := ctx.duplicate()
			both.total = int(ctx.rolls[0]) + again
			both.power = is_power(again, ctx.dice[0].sides, ctx.dice[0]) or ctx.power
			_damage_foe(_value(eff, both), eff)

		"reroll_best_damage":
			var second := roll(ctx.dice[0])
			var best: int = max(int(ctx.rolls[0]), second)
			_log("Переброс: %d и %d → %d" % [int(ctx.rolls[0]), second, best], "plain")
			var alt := ctx.duplicate()
			alt.total = best
			alt.power = is_power(best, ctx.dice[0].sides, ctx.dice[0])
			_damage_foe(_value(eff, alt), eff)

		"damage_per_ready":
			var ready_count := 0
			for d in bag:
				if d.is_ready():
					ready_count += 1
			_log("Готовых кубиков: %d" % ready_count, "plain")
			_damage_foe(int(eff.get("base", 0)) * ready_count, eff)

		"damage_from_block":
			# доля блока, а не броска: share, чтобы не путать с roll_mult
			var share := float(eff.get("share", eff.get("roll_mult", 0.5)))
			_damage_foe(int(round(block * share)) + int(eff.get("base", 0)), eff)

		"block":
			var n := _value(eff, ctx) + relics.sum("block_bonus")
			block += n
			_log("+%d блока" % n, "block")
			player_blocked.emit(n)

		"retain_block":
			block_retained_once = true
			_log("Блок продержится ещё ход", "block")

		"retain_block_forever":
			block_retained = true
			_log("Блок больше не сгорает", "block")

		"thorns":
			var t := _value(eff, ctx)
			thorns += t
			_log("Шипы +%d" % t, "good")

		"poison":
			var n2 := _value(eff, ctx) + relics.sum("poison_bonus")
			foe_poison += n2
			_log("Яд +%d" % n2, "good")

		"burn":
			var nb := _value(eff, ctx)
			foe_burn += nb
			_log("Ожог +%d (не слабеет), всего %d" % [nb, foe_burn], "good")

		"cool_dice":
			# «остудить» — это про кубики, и живёт в природе
			var nc := _cool_dice(_count(eff, ctx))
			if nc > 0:
				_log("Перезарядка ускорена на %d" % nc, "good")
			elif has_cooling_dice():
				_log("Возврат на этот ход исчерпан — кубики остынут сами", "plain")
			else:
				_log("Остужать нечего: все кубики в строю", "plain")

		"amplify_rot":
			# усиление порчи — почерк тьмы: не наносит урон сама, а делает
			# больнее то, что уже висит на враге
			var grown := _amplify_rot(_count(eff, ctx))
			if grown > 0:
				_log("Порча разрастается: +%d" % grown, "good")
			else:
				_log("Усиливать нечего: на враге нет ни яда, ни ожога", "plain")

		"no_cooldown":
			# правило «кубик уходит на перезарядку» — самое жёсткое в игре.
			# Карта, которая его отменяет, обязана быть редкой и одноразовой.
			for d in ctx.dice:
				d.cooldown = 0
				_log("%s остаётся в строю" % d.label(), "good")

		"exhaust_dice":
			# обратная сделка: выложиться сейчас и остаться без мешочка
			for d in bag:
				if d.cooldown <= 0 and not d.broken:
					d.cooldown = _cooldown_for(d)
			_log("Мешочек выложился весь", "dmg")

		"freeze":
			foe_frozen = true
			_log("Враг скован льдом — пропустит ход", "block")

		"discard_draw":
			var had := hand.size()
			var keep := str(eff.get("keep", ""))
			var dropped := 0
			for i in range(hand.size() - 1, -1, -1):
				if str(hand[i]) == keep:
					continue
				discard_pile.append(hand[i])
				hand.remove_at(i)
				dropped += 1
			var take := dropped + int(eff.get("base", 1))
			draw_cards(take)
			_log("Сброшено %d, добрано %d" % [dropped, take], "block")

		"poison_persist":
			foe_poison_slow = true
			_log("Яд теперь убывает вдвое медленнее", "good")

		"heal":
			var n3 := _value(eff, ctx)
			hp = min(max_hp, hp + n3)
			_log("+%d здоровья" % n3, "good")

		"self_damage":
			var n4 := int(eff.get("base", 0))
			hp -= n4
			_log("Отдача: −%d" % n4, "dmg")
			player_damaged.emit(n4)

		"punish_min_roll":
			var is_min := true
			for r in ctx.rolls:
				if int(r) != 1:
					is_min = false
					break
			if is_min:
				var n5 := int(eff.get("base", 0))
				hp -= n5
				_log("Ставка не зашла: −%d" % n5, "dmg")
				player_damaged.emit(n5)

		"strength":
			var n6 := _value(eff, ctx)
			strength += n6
			_log("Сила +%d" % n6, "power")

		"vulnerable":
			foe_vulnerable += int(eff.get("turns", 1))
			_log("Уязвимость %d х." % int(eff.get("turns", 1)), "dmg")

		"weaken":
			var amount := _value(eff, ctx)
			foe_weak_amount = max(foe_weak_amount, amount)
			foe_weak_turns = max(foe_weak_turns, int(eff.get("turns", 2)))
			_log("Слабость −%d на %d х." % [amount, int(eff.get("turns", 2))], "good")

		"freeze_if_power":
			if ctx.power:
				foe_frozen = true
				_log("Враг скован льдом", "block")

		"break_dice":
			for d in ctx.dice:
				d.broken = true
				_log("%s сломан" % d.label(), "dmg")

		"refresh_dice":
			# ПРАВИЛО: карта не возвращает больше кубиков, чем потратила.
			# Иначе розыгрыш выходит в плюс и появляется вечный двигатель.
			var count := mini(_count(eff, ctx), ctx.dice.size())
			if count > 0:
				_refresh_dice(count)

		"refresh_all", "refresh_all_except_paid":
			# «Вернуть всё» больше нет: любой массовый возврат идёт через
			# тот же потолок хода, что и остальные
			_refresh_dice(refresh_left)

		"forge_all":
			# перезарядка сокращается навсегда — это не возврат в строй,
			# поэтому потолок хода тут ни при чём
			var n9 := int(eff.get("base", 1))
			for d in bag:
				d.cooldown_max = maxi(1, d.cooldown_max - n9)
			_log("Все кубики теперь остывают на %d ход быстрее" % n9, "good")

		"cool_all":
			var n7 := int(eff.get("base", 1))
			var touched := 0
			for d in bag:
				if d.cooldown > 0 and touched < refresh_left:
					d.cooldown = max(0, d.cooldown - n7)
					touched += 1
			refresh_left -= touched
			if touched > 0:
				_log("Перезарядка −%d у %d кубиков" % [n7, touched], "good")
			elif has_cooling_dice():
				_log("Возврат на этот ход исчерпан", "plain")
			else:
				_log("Возвращать нечего: все кубики в строю", "plain")

		"cool_paid":
			# положительное значение ускоряет, отрицательное — задерживает
			var n8 := int(eff.get("base", 1))
			for d in ctx.dice:
				d.cooldown = max(0, d.cooldown - n8)
			if n8 > 0:
				_log("Оплаченный кубик остынет быстрее", "good")
			else:
				_log("Оплаченный кубик остынет дольше", "dmg")

		"forge_die":
			# единственный эффект, который переживает бой
			var n9 := int(eff.get("base", 1))
			for d in ctx.dice:
				d.cooldown_max = max(1, d.cooldown_max - n9)
				d.cooldown = min(d.cooldown, d.cooldown_max)
				_log("%s перекован: перезарядка теперь %d" % [d.label(), d.cooldown_max], "power")

		"draw_cards":
			var n10 := int(eff.get("base", 0))
			if n10 > 0:
				draw_cards(n10)
				_log("Добор %d" % n10, "block")

		"rust_on_draw", "hurt_on_draw":
			pass   # срабатывают при взятии в руку, не при розыгрыше

		_:
			push_warning("Неизвестный эффект: %s" % op)

## Отклик стихии. Совпал элемент карты и кубика — стихия делает своё,
## и у каждой оно СВОЁ, а не «плюс немного урона».
##
##   огонь   — ожог: урон, который не надо кидать заново
##   лёд     — враг бьёт слабее
##   природа — кубики: остудить, а если нечего — лечение
##   свет    — карты: один добор за ход, дальше сила
##   тьма    — усиление яда и ожога ценой своего здоровья
##
## Два правила, без которых механика не работает.
## 1. Отклик никогда не бывает пустым: если основная работа невозможна,
##    стихия платит запасным способом. Пустой отклик хуже слабого — игрок
##    один раз видит «ничего не произошло» и перестаёт замечать механику.
##    Ровно на это жаловались тьма и природа.
## 2. У каждой стихии есть потолок. Свет добирает раз в ход, тьма усиливает
##    порчу не больше чем на 4 за совпадение, возврат кубиков идёт через
##    общий потолок хода. Иначе одна стихия скупает всю экономику.
##
## matched — сколько кубиков совпало: два огненных жгут вдвое сильнее.
func _resonate(element: String, matched: int) -> void:
	match element:
		"fire":
			foe_burn += matched
			_log("Отклик огня: ожог +%d (не слабеет), всего %d" % [matched, foe_burn], "good")
		"ice":
			var chill := 2 * matched
			foe_weak_amount = max(foe_weak_amount, chill)
			foe_weak_turns = max(foe_weak_turns, 2)
			_log("Отклик льда: враг бьёт слабее на %d" % chill, "block")
		"nature":
			var cooled := _cool_dice(matched)
			if cooled > 0:
				_log("Отклик природы: перезарядка ускорена на %d" % cooled, "good")
			else:
				# Остудить не вышло по одной из двух причин, и путать их нельзя:
				# «нечего» — все кубики и так в строю, «потолок» — за этот ход
				# уже вернули сколько положено. Игрок видел кубики в остывании
				# и читал «остужать нечего» — игра выглядела сломанной.
				var mend := 3 * matched
				hp = mini(max_hp, hp + mend)
				if has_cooling_dice():
					_log("Отклик природы: возврат на этот ход исчерпан, +%d здоровья" % mend, "good")
				else:
					_log("Отклик природы: остужать нечего, +%d здоровья" % mend, "good")
		"light":
			var allowed := 1 + relics.sum("light_draws")
			if _light_draws_done >= allowed:
				strength += 1
				_log("Отклик света: доборы на этот ход кончились, сила +1", "power")
			else:
				_light_draws_done += 1
				light_drew_turn = turn
				draw_cards(1)
				_log("Отклик света: добор карты", "good")
		"dark":
			var grown := _amplify_rot(matched)
			if grown > 0:
				_log("Отклик тьмы: яд и ожог +%d, ты теряешь 2" % grown, "good")
			else:
				foe_vulnerable += 1
				_log("Отклик тьмы: врагу нечего усиливать — уязвимость на ход, ты теряешь 2", "dmg")
			if relics.sum("dark_free") <= 0:
				hp -= 2
				player_damaged.emit(2)
	changed.emit()

## Усилить всё, что уже гниёт на враге, наполовину.
## Потолок нужен обязательно: без него каждое срабатывание умножает яд на
## полтора, и три тёмных карты подряд превращают 10 яда в 34.
func _amplify_rot(amount: int) -> int:
	var cap := 4 * maxi(1, amount)
	var grown := 0
	if foe_poison > 0:
		var add := mini(cap, maxi(1, int(round(foe_poison * 0.5))))
		foe_poison += add
		grown += add
	if foe_burn > 0:
		var addb := mini(cap, maxi(1, int(round(foe_burn * 0.5))))
		foe_burn += addb
		grown += addb
	return grown

## Снять по одному ходу перезарядки с самых «холодных» кубиков.
func _cool_dice(times: int) -> int:
	times = mini(times, refresh_left)
	var done := 0
	for i in times:
		var target: Die = null
		for d in bag:
			if d.broken or d.cooldown <= 0:
				continue
			if target == null or d.cooldown < target.cooldown:
				target = d
		if target == null:
			break
		target.cooldown -= 1
		refresh_left -= 1
		done += 1
	return done

## Вернуть в строй до count кубиков, но не больше, чем позволяет потолок хода.
func _refresh_dice(count: int) -> void:
	count = mini(count, refresh_left)
	if count <= 0:
		if has_cooling_dice():
			_log("Возврат на этот ход исчерпан (потолок %d за ход)" % int(DB.b("refresh_cap", 2)), "plain")
		else:
			_log("Возвращать нечего: все кубики в строю", "plain")
		return
	var cooling: Array = []
	for d in bag:
		if not d.broken and d.cooldown > 0:
			cooling.append(d)
	cooling.sort_custom(func(a, b): return a.sides > b.sides)
	var names: Array = []
	for i in min(count, cooling.size()):
		cooling[i].cooldown = 0
		names.append(cooling[i].label())
		refresh_left -= 1
	if names.is_empty():
		_log("Все кубики и так готовы", "plain")
	else:
		_log("В строю снова: %s" % ", ".join(names), "good")

# ─────────────────────────────────────────── урон

func _damage_foe(amount: int, opts: Dictionary = {}) -> void:
	var pierce := bool(opts.get("pierce", false))
	var dmg: int = max(0, amount + strength + relics.sum("damage_bonus") - weak_amount)
	if foe_vulnerable > 0:
		dmg = int(round(dmg * float(DB.b("vulnerable_multiplier", 1.5))))
	if not pierce and foe_block > 0:
		var absorbed: int = min(foe_block, dmg)
		foe_block -= absorbed
		dmg -= absorbed
		if absorbed > 0:
			_log("Блок врага поглотил %d" % absorbed, "block")
	# броня работает как блок, но не сгорает в конце хода: её надо пробить
	if not pierce and foe_plated > 0 and dmg > 0:
		var stopped: int = min(foe_plated, dmg)
		dmg -= stopped
		foe_plated -= stopped
		_log("Броня выдержала %d (осталось %d)" % [stopped, foe_plated], "block")
	foe_hp -= dmg
	if dmg > 0 and foe_thorns > 0:
		hp -= foe_thorns
		_log("Шипы врага: −%d" % foe_thorns, "dmg")
		player_damaged.emit(foe_thorns)
	_log("Урон %d" % dmg, "dmg")
	foe_damaged.emit(dmg)
	if opts.has("lifesteal") and dmg > 0:
		var back := int(round(dmg * float(opts.get("lifesteal", 0.0))))
		if back > 0:
			hp = min(max_hp, hp + back)
			_log("Вытянуто здоровья: +%d" % back, "good")

func _hit_player(base: int, lifesteal: int = 0) -> void:
	var dmg: int = max(0, base + foe_strength - foe_weak_amount)
	if vulnerable > 0:
		dmg = int(round(dmg * float(DB.b("vulnerable_multiplier", 1.5))))
	var absorbed: int = min(block, dmg)
	block -= absorbed
	dmg -= absorbed
	hp -= dmg
	if absorbed > 0:
		_log("%s бьёт: блок съел %d, ты теряешь %d" % [foe_name, absorbed, dmg], "dmg")
	else:
		_log("%s бьёт на %d" % [foe_name, dmg], "dmg")
	player_damaged.emit(dmg)
	if lifesteal > 0 and dmg > 0:
		foe_hp = min(foe_max_hp, foe_hp + lifesteal)
		_log("%s забирает себе %d здоровья" % [foe_name, lifesteal], "enemy")
	if thorns > 0:
		foe_hp -= thorns
		_log("Шипы отвечают на %d" % thorns, "good")
		foe_damaged.emit(thorns)

# ─────────────────────────────────────────── конец хода и ход врага

func end_turn() -> void:
	if finished:
		return
	_discard_hand()
	_enemy_turn()

## «Собраться» — не бесплатная кнопка, а выход из положения «нечем ходить».
##
## Раньше это был обычный конец хода плюс подарок: перезарядка ускорялась, а
## взамен не терялось ничего. Нажимать её всегда было выгоднее, чем «Конец
## хода», и выбор из двух кнопок оказывался ненастоящим.
##
## Первая попытка чинить это сжигала блок и открывала под удар — но била
## ровно в тот момент, ради которого кнопка и существует: когда играть нечем.
## Наказывать за невезение неправильно. Поэтому цена стала простой и
## одинаковой в любой ситуации: немного здоровья. Один раз за бой это дёшево,
## каждый ход — заметно.
func regroup() -> void:
	if finished:
		return
	var relief := int(DB.b("regroup_relief", 2))
	var toll := int(DB.b("regroup_cost", 4))
	for d in bag:
		if d.cooldown > 0:
			d.cooldown = max(0, d.cooldown - relief)
	_log("Собрался: перезарядка −%d хода всем кубикам, ценой %d здоровья" % [relief, toll], "good")
	if toll > 0:
		hp -= toll
		player_damaged.emit(toll)
	_discard_hand()
	if _check_end():
		return
	_enemy_turn()

func has_cooling_dice() -> bool:
	for d in bag:
		if d.cooldown > 0:
			return true
	return false

func _discard_hand() -> void:
	for c in hand:
		discard_pile.append(c)
	hand = []

## ─────────────────────────────────────── выбор действия врага
##
## Круг действий по списку читался за два хода и превращал бой в пасьянс.
## Теперь враг каждый ход выбирает действие случайно по весам, но с рамками:
##   · первый ход всегда задан заранее — начало боя предсказуемо;
##   · одно и то же действие нельзя повторять больше max_repeat раз подряд;
##   · часть действий открывается только по здоровью, ходу или один раз за бой;
##   · «замах» через then жёстко назначает следующее действие.
## Выбранное действие объявляется ЗАРАНЕЕ и висит над врагом весь ход игрока.

func _move_by_id(mid: String) -> Dictionary:
	for m in foe_moves:
		if str(m.get("id", "")) == mid:
			return m
	return {}

func _move_allowed(m: Dictionary, ignore_repeat: bool) -> bool:
	var mid := str(m.get("id", ""))
	if int(m.get("weight", 0)) <= 0:
		return false
	if bool(m.get("once", false)) and int(_foe_uses.get(mid, 0)) > 0:
		return false
	if m.has("min_turn") and turn < int(m.min_turn):
		return false
	if m.has("if_hp_below") and float(foe_hp) > float(foe_max_hp) * float(m.if_hp_below):
		return false
	if not ignore_repeat and mid == _foe_last_id and _foe_repeat >= int(m.get("max_repeat", 2)):
		return false
	return true

func _pick_move() -> Dictionary:
	if foe_moves.is_empty():
		return {}
	if _foe_forced != "":
		var forced := _move_by_id(_foe_forced)
		_foe_forced = ""
		if not forced.is_empty():
			return forced
	for ignore_repeat in [false, true]:
		var pool: Array = []
		var total := 0
		for m in foe_moves:
			if _move_allowed(m, ignore_repeat):
				pool.append(m)
				total += int(m.get("weight", 0))
		if total <= 0:
			continue
		var roll := rng.randi_range(1, total)
		for m in pool:
			roll -= int(m.get("weight", 0))
			if roll <= 0:
				return m
	return foe_moves[0]

func _choose_next() -> void:
	foe_next = _pick_move()

## Действие с уже посчитанными числами: сюда входят сила врага, накопленный
## разгон (scale) и уязвимость игрока. Игрок видит ровно то, что прилетит.
func resolved_action(act: Dictionary = {}) -> Dictionary:
	if act.is_empty():
		act = foe_next
	if act.is_empty():
		return {}
	var mid := str(act.get("id", ""))
	var out := act.duplicate(true)
	var uses := int(_foe_uses.get(mid, 0))
	if act.has("damage"):
		var base: int = int(act.damage) + int(act.get("scale", 0)) * uses
		var each: int = max(0, base + foe_strength - foe_weak_amount)
		if vulnerable > 0:
			each = int(round(each * float(DB.b("vulnerable_multiplier", 1.5))))
		out["damage_each"] = each
		out["damage_total"] = each * int(act.get("times", 1))
		out["raw_damage"] = base
	return out

## Строка намерения, собранная из чисел, а не написанная руками:
## «Удар 12», «Удар 8 × 3 = 24», «Броня 10 · сила +2».
func intent_text(act: Dictionary = {}) -> String:
	var r := resolved_action(act)
	if r.is_empty():
		return "выжидает"
	if str(r.get("label_override", "")) != "":
		return str(r.label_override)
	var parts: Array = []
	if r.has("damage"):
		var times := int(r.get("times", 1))
		if times > 1:
			parts.append("Удар %d × %d = %d" % [int(r.damage_each), times, int(r.damage_total)])
		else:
			parts.append("Удар %d" % int(r.damage_each))
	if r.has("block"):
		parts.append("блок %d" % int(r.block))
	if r.has("plated"):
		parts.append("броня %d" % int(r.plated))
	if r.has("self_heal"):
		parts.append("лечение %d" % int(r.self_heal))
	if r.has("lifesteal"):
		parts.append("вампиризм %d" % int(r.lifesteal))
	if r.has("gain_strength"):
		parts.append("сила +%d" % int(r.gain_strength))
	if r.has("thorns"):
		parts.append("шипы %d" % int(r.thorns))
	if r.has("vulnerable"):
		parts.append("уязвимость %d х." % int(r.vulnerable))
	if r.has("weak"):
		parts.append("слабость −%d (%d х.)" % [int(r.weak), int(r.get("weak_turns", 2))])
	if r.has("rust"):
		parts.append("ржавчина +%d" % int(r.rust))
	if r.has("lock"):
		parts.append("заклинит кубик")
	if r.has("curse"):
		parts.append("проклятие в колоду")
	if parts.is_empty():
		return "выжидает"
	var head: String = str(parts[0])
	if parts.size() == 1:
		return head
	var rest: Array = parts.slice(1)
	return head + " · " + " · ".join(rest)

## Сколько урона прилетит, если ничего не делать — для подсветки блока.
func incoming_damage() -> int:
	var r := resolved_action()
	return int(r.get("damage_total", 0))

## Все действия врага — показываются в панели «что он умеет».
func move_book() -> Array:
	var out: Array = []
	for m in foe_moves:
		if int(m.get("weight", 0)) <= 0 and not m.has("then"):
			# добивающий удар после замаха — покажем его вместе с замахом
			pass
		out.append({"move": m, "text": intent_text(m), "kind": str(m.get("kind", "aggro"))})
	return out

## Совместимость со старым кодом экрана.
func current_action() -> Dictionary:
	return foe_next

func upcoming_actions(n: int) -> Array:
	return [foe_next]

func _enemy_turn() -> void:
	var act := foe_next
	var mid := str(act.get("id", ""))
	var resolved := resolved_action(act)
	_foe_uses[mid] = int(_foe_uses.get(mid, 0)) + 1
	if mid == _foe_last_id:
		_foe_repeat += 1
	else:
		_foe_last_id = mid
		_foe_repeat = 1
	foe_block = 0

	if foe_frozen:
		foe_frozen = false
		_log("%s скован льдом и пропускает ход" % foe_name, "block")
	else:
		if act.has("gain_strength"):
			foe_strength += int(act.gain_strength)
			_log("%s наливается силой: +%d к урону" % [foe_name, int(act.gain_strength)], "enemy")
		if act.has("block"):
			foe_block += int(act.block)
			_log("%s: блок %d" % [foe_name, int(act.block)], "block")
		if act.has("plated"):
			foe_plated += int(act.plated)
			_log("%s наращивает броню %d" % [foe_name, int(act.plated)], "block")
		if act.has("thorns"):
			foe_thorns += int(act.thorns)
			_log("%s ощетинился: шипы %d" % [foe_name, int(act.thorns)], "enemy")
		if act.has("self_heal"):
			foe_hp = min(foe_max_hp, foe_hp + int(act.self_heal))
			_log("%s лечится на %d" % [foe_name, int(act.self_heal)], "enemy")
		if act.has("rust"):
			for d in bag:
				if not d.broken:
					d.cooldown += int(act.rust)
			_log("Ржавая печать: +%d ход перезарядки всем кубикам" % int(act.rust), "dmg")
		if act.has("lock"):
			_lock_die(int(act.lock))
		if act.has("curse"):
			_curse_into_deck(str(act.curse))
		if act.has("damage"):
			var each: int = int(resolved.get("raw_damage", act.damage))
			var steal := int(act.get("lifesteal", 0))
			for i in int(act.get("times", 1)):
				if hp <= 0:
					break
				_hit_player(each, steal)
		if act.has("vulnerable"):
			vulnerable += int(act.vulnerable)
			_log("На тебе уязвимость %d х." % int(act.vulnerable), "dmg")
		if act.has("weak"):
			weak_amount = max(weak_amount, int(act.weak))
			weak_turns = max(weak_turns, int(act.get("weak_turns", 2)))
			_log("Слабость: твои удары −%d на %d х." % [weak_amount, weak_turns], "dmg")
		if act.has("then"):
			_foe_forced = str(act.then)

	# Налог «Вторая кожа»: под порогом здоровья босс перестаёт чувствовать
	# порчу. Билд на яде обязан иметь второй способ добивать — иначе он
	# доводит босса до половины и упирается в стену.
	var rot_works := true
	var immune_below := float(foe_tax.get("rot_immune_below", 0.0))
	if immune_below > 0.0 and foe_max_hp > 0 and float(foe_hp) / float(foe_max_hp) <= immune_below:
		rot_works = false
		if foe_burn > 0 or foe_poison > 0:
			_log("%s: порча не берёт" % str(foe_tax.get("name", "Налог")), "enemy")

	if foe_burn > 0 and rot_works:
		var burn_hit := foe_burn + relics.sum("burn_bonus")
		foe_hp -= burn_hit
		_log("Ожог жжёт на %d" % burn_hit, "good")
		foe_damaged.emit(burn_hit)
	if foe_poison > 0 and rot_works:
		foe_hp -= foe_poison
		_log("Яд наносит %d" % foe_poison, "good")
		foe_damaged.emit(foe_poison)
		# Яд раньше можно было заморозить навсегда, и он копился без потолка:
		# 46 яда на боссе со 138 здоровья — это бой, выигранный без единой атаки.
		# Теперь «Чума» его лишь замедляет.
	if foe_poison > 0:
		if foe_poison_slow:
			if turn % 2 == 0:
				foe_poison -= 1
		else:
			foe_poison -= 1
	# Правило третьего акта: тянуть бой больше нельзя. Это единственная
	# честная защита от «непробиваемого» билда — он всё ещё непробиваемый,
	# просто теперь у него есть срок.
	var ramp: int = int(act_rule.get("ramp_turns", 0))
	if ramp > 0 and turn > 0 and turn % ramp == 0:
		var gain: int = int(act_rule.get("ramp_strength", 1))
		foe_strength += gain
		_log("%s: враг наливается силой +%d" % [str(act_rule.get("name", "Правило акта")), gain], "enemy")

	if foe_vulnerable > 0:
		foe_vulnerable -= 1
	if foe_weak_turns > 0:
		foe_weak_turns -= 1
		if foe_weak_turns == 0:
			foe_weak_amount = 0
	if vulnerable > 0:
		vulnerable -= 1
	if weak_turns > 0:
		weak_turns -= 1
		if weak_turns == 0:
			weak_amount = 0

	changed.emit()
	if _check_end():
		return
	_choose_next()
	begin_turn()

## Заклинить кубик: самый крупный уходит в долгую перезарядку.
func _lock_die(extra: int) -> void:
	var target: Die = null
	for d in bag:
		if d.broken:
			continue
		if target == null or d.sides > target.sides:
			target = d
	if target == null:
		return
	target.cooldown += max(1, extra) + target.cooldown_max
	_log("Цепь на %s: он вернётся нескоро" % target.label(), "dmg")

## Проклятие врага падает прямо в колоду добора этого боя.
func _curse_into_deck(curse_id: String) -> void:
	if curse_id == "":
		return
	draw_pile.insert(rng.randi_range(0, draw_pile.size()), curse_id)
	_log("В колоду подброшено проклятие: «%s»" % DB.card_name(curse_id), "dmg")

func _check_end() -> bool:
	if finished:
		return true
	if foe_hp <= 0:
		var spoils := relics.sum("heal_on_kill")
		if spoils > 0:
			hp = min(max_hp, hp + spoils)
			_log("Реликвия пьёт за победу: +%d" % spoils, "good")
		finished = true
		fight_over.emit(true)
		return true
	if hp <= 0:
		finished = true
		fight_over.emit(false)
		return true
	return false
