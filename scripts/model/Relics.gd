class_name Relics
extends RefCounted
## Реликвии забега. Держит список подобранных и умеет сложить их свойства.
##
## Устройство нарочно тупое: реликвия — это набор чисел, а не программа.
## Модель нигде не спрашивает «есть ли у меня Кровавик», она спрашивает
## «сколько всего heal_on_kill». Поэтому новая реликвия добавляется правкой
## JSON, а не кода, и две реликвии с одним свойством складываются сами.

var ids: Array = []

## Сколько боёв реликвия ещё работает. Заводится только у тех, у кого в
## данных есть uses. Временная реликвия — способ дать сильный эффект без
## того, чтобы он определял весь оставшийся забег: она чинит текущую беду
## и уходит, а не превращается в постоянную прибавку.
var charges: Dictionary = {}

func add(id: String) -> void:
	if id == "" or ids.has(id):
		return
	ids.append(id)
	var uses := int(DB.relic(id).get("uses", 0))
	if uses > 0:
		charges[id] = uses

## Реликвия работает? Постоянная — всегда, временная — пока есть заряды.
func alive(id: String) -> bool:
	if not charges.has(id):
		return true
	return int(charges[id]) > 0

## Списать по заряду после боя. Возвращает те, что истёрлись именно сейчас —
## игроку надо сказать, что правило перестало действовать.
func spend_uses() -> Array:
	var spent: Array = []
	for id in charges.keys():
		if int(charges[id]) > 0:
			charges[id] = int(charges[id]) - 1
			if int(charges[id]) == 0:
				spent.append(id)
	return spent

func uses_left(id: String) -> int:
	return int(charges.get(id, -1))

func has(id: String) -> bool:
	return ids.has(id)

## Сумма одноимённого свойства по всем реликвиям.
func sum(key: String) -> int:
	var total := 0
	for id in ids:
		if not alive(str(id)):
			continue
		total += int(DB.relic(str(id)).get(key, 0))
	return total

## То же, но свойство считается только у реликвий нужной стихии.
func sum_for_element(key: String, element: String) -> int:
	var total := 0
	for id in ids:
		if not alive(str(id)):
			continue
		var r := DB.relic(str(id))
		if str(r.get("element", "")) == element:
			total += int(r.get(key, 0))
	return total

## Сдвиг перезарядки от заветов: одна пара стихий греется быстрее, другая
## медленнее. Заветы — единственная реликвия, которая делает выбор стихий
## в мешочке необратимым, поэтому и цена у них в той же валюте.
func cooldown_shift(element: String) -> int:
	var shift := 0
	for id in ids:
		if not alive(str(id)):
			continue
		var r := DB.relic(str(id))
		if element in r.get("pair_fast", []):
			shift += 1
		if element in r.get("pair_slow", []):
			shift -= 1
	return shift

func names() -> Array:
	var out: Array = []
	for id in ids:
		out.append(str(DB.relic(str(id)).get("name", id)))
	return out

## Случайная реликвия нужного уровня, которой ещё нет.
## Уровни: common | uncommon | rare | boss.
func roll(rng: RandomNumberGenerator, tier: String) -> String:
	var pool: Array = []
	for id in DB.relics.get("pools", {}).get(tier, []):
		if not has(str(id)):
			pool.append(str(id))
	if pool.is_empty():
		return ""
	return str(pool[rng.randi_range(0, pool.size() - 1)])

## Несколько разных реликвий одного уровня — для выбора из трёх.
func roll_many(rng: RandomNumberGenerator, tier: String, count: int) -> Array:
	var pool: Array = []
	for id in DB.relics.get("pools", {}).get(tier, []):
		if not has(str(id)):
			pool.append(str(id))
	var out: Array = []
	for i in count:
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		out.append(pool[idx])
		pool.remove_at(idx)
	return out

## Что дать за зачищенную комнату: элита в первом акте — попроще,
## дальше по забегу — вкуснее.
func roll_for_room(rng: RandomNumberGenerator, kind: String, act: int) -> String:
	var tier := "common"
	match kind:
		"boss":
			tier = "boss"
		"elite":
			tier = "rare" if act >= 2 else ("uncommon" if act >= 1 else "common")
		_:
			tier = "common" if rng.randf() < 0.6 else "uncommon"
	var id := roll(rng, tier)
	if id == "":
		for fallback in ["uncommon", "common", "rare", "boss"]:
			id = roll(rng, fallback)
			if id != "":
				break
	return id
