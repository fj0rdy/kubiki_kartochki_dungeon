class_name DungeonMap
extends RefCounted
## Процедурное подземелье: три акта, в каждом свой набор врагов и свой босс.
##
## Внутри акта — ветвящийся маршрут. Ряды идут снизу вверх, в каждом ряду
## несколько комнат; из комнаты можно шагнуть только в соединённую с ней.
## Развилка нужна не для красоты: игрок выбирает между «сильнее» (элита,
## лавка) и «безопаснее» (обычный бой, привал), и выбирает с оглядкой на
## здоровье, золото и мешочек.
##
## Длина акта и набор комнат каждый раз разные — два забега не совпадут.

## Веса типов комнат. Меняй здесь, если подземелье кажется слишком
## боевым или наоборот пустым.
const WEIGHTS := {
	"fight": 50,
	"event": 17,
	"elite": 16,
	"shop": 7,
	"treasure": 7,
	"rest": 3,
}

## Комнаты, которые не бой. Две таких подряд по одному маршруту — это провал
## темпа: игрок перестаёт принимать решения и просто идёт вперёд. Поэтому
## после раскладки цепочки разрываются принудительно.
const PEACEFUL := ["event", "shop", "treasure", "rest"]

var acts: Array = []            # [{title, rows, normal, elite, boss}]
var act_index: int = 0
var current_row: int = -1
var current_col: int = -1

var _rng: RandomNumberGenerator

static func generate(rng: RandomNumberGenerator) -> DungeonMap:
	var m := DungeonMap.new()
	m._rng = rng
	var defs: Array = DB.enemies.get("acts", [])
	if defs.is_empty():
		defs = [{
			"title": "Подземелье",
			"rows": [7, 7],
			"normal": DB.enemies.get("normal", []),
			"elite": DB.enemies.get("elite", []),
			"boss": DB.enemies.get("boss", []),
		}]
	for i in defs.size():
		m.acts.append(m._build_act(defs[i], i, rng))
	return m

func _build_act(def: Dictionary, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var span: Array = def.get("rows", [7, 7])
	var length: int = rng.randi_range(int(span[0]), int(span[-1]))
	var normals: Array = def.get("normal", [])
	var elites: Array = def.get("elite", [])
	var bosses: Array = def.get("boss", [])
	var events: Array = DB.events.get("list", [])

	# длина = рядовые комнаты + привал + босс
	var body: int = maxi(3, length - 2)
	var built: Array = []

	for r in body:
		var count := 1
		if r == 0:
			count = 2
		else:
			count = rng.randi_range(2, 3)
		var row: Array = []
		for c in count:
			var node := {
				"row": r, "col": c, "act": index,
				"type": "fight", "next": [], "visited": false,
			}
			_assign_type(node, r, body, index, rng, normals, elites, events)
			row.append(node)
		built.append(row)

	built.append([{
		"row": body, "col": 0, "act": index,
		"type": "rest", "next": [], "visited": false,
	}])
	var boss_id := ""
	if bosses.size() > 0:
		boss_id = str(bosses[rng.randi_range(0, bosses.size() - 1)])
	built.append([{
		"row": body + 1, "col": 0, "act": index,
		"type": "boss", "enemy": boss_id, "next": [], "visited": false,
	}])

	var act := {
		"title": str(def.get("title", "Подземелье")),
		"rows": built,
		"normal": normals,
		"elite": elites,
	}
	_connect(built, rng)
	# предбоссовый привал и сам босс правке не подлежат: привал перед боссом
	# обязателен, иначе последний бой упирается в остатки здоровья
	_break_peace_chains(built, normals, rng, body)
	return act

## Разорвать цепочки мирных комнат.
##
## Веса раскладываются по каждой комнате отдельно, и генератор время от
## времени выдаёт маршрут «событие → лавка → сундук» без единого боя. Тут
## это чинится после соединения рядов: если в комнату ведут только мирные
## комнаты, она сама становится боем. Так по любому пути между двумя мирными
## комнатами всегда стоит бой.
func _break_peace_chains(grid: Array, normals: Array, rng: RandomNumberGenerator, body: int) -> void:
	for r in range(1, body):
		for node in grid[r]:
			if not PEACEFUL.has(str(node.type)):
				continue
			# достаточно ОДНОГО мирного родителя: иначе останется маршрут,
			# на котором игрок проходит две мирные комнаты подряд, даже если
			# у комнаты есть и боевой вход
			var peaceful_parent := false
			for prev in grid[r - 1]:
				if not prev.next.has(int(node.col)):
					continue
				if PEACEFUL.has(str(prev.type)):
					peaceful_parent = true
					break
			if peaceful_parent:
				node.type = "fight"
				node.enemy = _pick(normals, rng)
				node.erase("event")

	# и ещё: в каждом ряду должен быть хотя бы один бой, иначе ряд
	# проходится не глядя
	for r in range(1, body):
		var fight_here := false
		for node in grid[r]:
			if not PEACEFUL.has(str(node.type)):
				fight_here = true
				break
		if fight_here:
			continue
		var victim: Dictionary = grid[r][rng.randi_range(0, grid[r].size() - 1)]
		victim.type = "fight"
		victim.enemy = _pick(normals, rng)
		victim.erase("event")

## Правила размещения. Без них генератор ставит элиту на первый ряд
## и три лавки подряд — маршрут перестаёт быть выбором.
func _assign_type(node: Dictionary, r: int, body: int, act: int,
		rng: RandomNumberGenerator, normals: Array, elites: Array, events: Array) -> void:
	var pool := {}
	for k in WEIGHTS.keys():
		pool[k] = int(WEIGHTS[k])
	# первый ряд акта — всегда бой: игрок сразу видит, с кем имеет дело
	if r == 0:
		node.type = "fight"
		node.enemy = _pick(normals, rng)
		return
	# элита не раньше третьего ряда и не в первом акте на старте
	if r < 2 or (act == 0 and r < 3):
		pool.erase("elite")
	# привал сразу после старта бесполезен
	if r < 2:
		pool.erase("rest")
	# перед предбоссовым привалом лишний привал не нужен
	if r >= body - 1:
		pool.erase("rest")
	if events.is_empty():
		pool.erase("event")

	var total := 0
	for k in pool.keys():
		total += int(pool[k])
	var roll: int = rng.randi_range(1, maxi(1, total))
	var chosen := "fight"
	for k in pool.keys():
		roll -= int(pool[k])
		if roll <= 0:
			chosen = str(k)
			break

	node.type = chosen
	match chosen:
		"fight":
			node.enemy = _pick(normals, rng)
		"elite":
			node.enemy = _pick(elites, rng)
		"event":
			node.event = _pick(events, rng)

func _pick(arr: Array, rng: RandomNumberGenerator) -> String:
	if arr.is_empty():
		return ""
	return str(arr[rng.randi_range(0, arr.size() - 1)])

## Соединяем соседние ряды так, чтобы в каждую комнату вёл хотя бы один путь.
func _connect(grid: Array, rng: RandomNumberGenerator) -> void:
	for r in range(grid.size() - 1):
		var here: Array = grid[r]
		var above: Array = grid[r + 1]
		for node in here:
			var target := int(round(float(node.col) * (above.size() - 1) / maxf(1.0, here.size() - 1)))
			var links := {}
			links[clampi(target, 0, above.size() - 1)] = true
			if above.size() > 1 and rng.randf() < 0.45:
				var step: int = 1 if rng.randf() < 0.5 else -1
				links[clampi(target + step, 0, above.size() - 1)] = true
			node.next = links.keys()
			node.next.sort()
		for c in above.size():
			var reachable := false
			for node in here:
				if node.next.has(c):
					reachable = true
					break
			if not reachable:
				var nearest: Dictionary = here[0]
				var best := 99
				for node in here:
					var dist: int = absi(int(round(float(node.col) * (above.size() - 1) / maxf(1.0, here.size() - 1))) - c)
					if dist < best:
						best = dist
						nearest = node
				nearest.next.append(c)
				nearest.next.sort()

# ── доступ

var rows: Array:
	get:
		if acts.is_empty():
			return []
		return acts[act_index]["rows"]

func act_title() -> String:
	if acts.is_empty():
		return ""
	return str(acts[act_index].title)

func started() -> bool:
	return current_row >= 0

## Комнаты, доступные для следующего шага.
func available() -> Array:
	if acts.is_empty():
		return []
	if not started():
		return rows[0].duplicate()
	if current_row >= rows.size() - 1:
		return []
	var node: Dictionary = rows[current_row][current_col]
	var out: Array = []
	for c in node.next:
		out.append(rows[current_row + 1][c])
	return out

func enter(node: Dictionary) -> void:
	current_row = int(node.row)
	current_col = int(node.col)
	node.visited = true

func current() -> Dictionary:
	if not started():
		return {}
	return rows[current_row][current_col]

## Босс акта повержен — начинается следующий акт.
func act_cleared() -> bool:
	return started() and current_row >= rows.size() - 1

func last_act() -> bool:
	return act_index >= acts.size() - 1

func advance_act() -> bool:
	if last_act():
		return false
	act_index += 1
	current_row = -1
	current_col = -1
	return true

func finished() -> bool:
	return act_cleared() and last_act()

func progress_text() -> String:
	if acts.is_empty():
		return ""
	return "акт %d · %s · %d/%d" % [
		act_index + 1, act_title(), max(1, current_row + 1), rows.size()]

static func type_title(t: String) -> String:
	match t:
		"fight": return "Бой"
		"elite": return "Элита"
		"event": return "Событие"
		"rest": return "Привал"
		"treasure": return "Сокровище"
		"shop": return "Лавка"
		"boss": return "Босс"
	return t

static func type_color(t: String) -> Color:
	match t:
		"fight": return Color("c0442c")
		"elite": return Color("e0533a")
		"event": return Color("9b6bc4")
		"rest": return Color("5fae6b")
		"treasure": return Color("d4a04a")
		"shop": return Color("6fb0c8")
		"boss": return Color("e8c65a")
	return Color("8b8092")
