extends Node
## Автозагрузка. Читает JSON из data/ и раздаёт остальным скриптам.
## Ничего не считает — только хранит.

var balance: Dictionary = {}
var cards: Dictionary = {}
var enemies: Dictionary = {}
var events: Dictionary = {}
var relics: Dictionary = {}

func _ready() -> void:
	balance = _load("res://data/balance.json")
	cards = _load("res://data/cards.json")
	if cards.has("cards"):
		cards = cards["cards"]
	enemies = _load("res://data/enemies.json")
	events = _load("res://data/events.json")
	relics = _load("res://data/relics.json")

func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Не найден файл данных: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Файл %s — не JSON-объект" % path)
		return {}
	# ключи, начинающиеся с "_", это комментарии для человека
	var clean := {}
	for k in parsed.keys():
		if not str(k).begins_with("_"):
			clean[k] = parsed[k]
	return clean

## --- удобные геттеры ---

func b(key: String, fallback = 0):
	return balance.get(key, fallback)

func die_cost(sides: int) -> int:
	return int(balance.get("dice", {}).get(str(sides), {}).get("cost", 99))

func die_cooldown(sides: int) -> int:
	return int(balance.get("dice", {}).get(str(sides), {}).get("cooldown", 2))

func die_types() -> Array:
	var out: Array = []
	for k in balance.get("dice", {}).keys():
		out.append(int(k))
	out.sort()
	return out

## Порог Мощи: верхняя треть граней. У d4 достижим только максимум.
func power_threshold(sides: int) -> int:
	if sides <= 4:
		return sides
	return int(ceil(sides * float(balance.get("power_threshold_ratio", 0.75))))

func is_power(roll: int, sides: int) -> bool:
	return roll >= power_threshold(sides)

var _card_cache: Dictionary = {}

## Карта по id. Суффикс "+" означает улучшенную версию: блок upgrade
## перекрывает те поля базовой карты, которые в нём перечислены.
func card(id: String) -> Dictionary:
	if _card_cache.has(id):
		return _card_cache[id]
	var upgraded := id.ends_with("+")
	var base_id := id.trim_suffix("+")
	var base: Dictionary = cards.get(base_id, {})
	if base.is_empty():
		return {}
	var result := base
	if upgraded and base.has("upgrade"):
		result = base.duplicate(true)
		for k in base["upgrade"].keys():
			result[k] = base["upgrade"][k]
		result["upgraded"] = true
		result["name"] = str(base.get("name", base_id)) + "+"
	_card_cache[id] = result
	return result

func card_name(id: String) -> String:
	return str(card(id).get("name", id))

func can_upgrade(id: String) -> bool:
	if id.ends_with("+"):
		return false
	return cards.get(id, {}).has("upgrade")

func upgraded_id(id: String) -> String:
	return id if id.ends_with("+") else id + "+"

func is_playable(id: String) -> bool:
	return not bool(card(id).get("unplayable", false))

func rarity(id: String) -> String:
	return str(card(id).get("rarity", "common"))

## Все карты вообще — для галереи и для сборки стартовой колоды.
func card_ids() -> Array:
	var out: Array = cards.keys()
	out.sort()
	return out

## Все карты нужной редкости — из них собираются награды.
func cards_of_rarity(r: String) -> Array:
	var out: Array = []
	for cid in cards.keys():
		if str(cards[cid].get("rarity", "")) == r:
			out.append(cid)
	out.sort()
	return out

func event(id: String) -> Dictionary:
	return events.get(id, {})

func enemy(id: String) -> Dictionary:
	return enemies.get(id, {})

## Стартовая колода по имени. Пустое имя — первая из списка.
func starter_deck(id: String = "") -> Array:
	var decks: Dictionary = balance.get("starter_decks", {})
	if decks.is_empty():
		return balance.get("starter_deck", []).duplicate()
	if id == "" or not decks.has(id):
		id = str(decks.keys()[0])
	return decks[id].get("cards", []).duplicate()

func deck_names() -> Array:
	return balance.get("starter_decks", {}).keys()

func deck_info(id: String) -> Dictionary:
	return balance.get("starter_decks", {}).get(id, {})

## Особое свойство кубика по id. Пустая строка — обычный кубик.
func quirk_of(id: String) -> Dictionary:
	if id == "":
		return {}
	return balance.get("traits", {}).get(id, {})

func quirk_ids() -> Array:
	var out: Array = balance.get("traits", {}).keys()
	out.sort()
	return out

func relic(id: String) -> Dictionary:
	return relics.get(id, {})

func relic_name(id: String) -> String:
	return str(relic(id).get("name", id))
