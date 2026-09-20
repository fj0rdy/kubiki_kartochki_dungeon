class_name Die
extends RefCounted
## Один кубик в мешочке. Не тратится насовсем — уходит на перезарядку.

var id: int = 0
var sides: int = 6
var element: String = "fire"
var cooldown_max: int = 2
var cooldown: int = 0      ## сколько ходов ещё остывает; 0 = готов
var broken: bool = false   ## сломан до конца боя (карта «Жертва»)
var quirk: String = ""     ## особое свойство кубика: lucky, prism, heavy, swift, echo, keen
## Что выпало на этом кубике в текущем ходу. −1 значит «ещё не бросали».
##
## Бросок закреплён за КУБИКОМ, а не за картой. Раньше отмена карты
## возвращала кубик нетронутым, и его можно было перебрасывать, пока не
## выпадет нужное. Теперь выпавшее число живёт до конца хода: передумал —
## кубик вернулся с тем же самым числом. Решение «какой картой оплатить
## этот бросок» осталось, переброс исчез.
var rolled: int = -1

static var _seq: int = 0

static func make(p_sides: int, p_element: String, p_quirk: String = "") -> Die:
	var d := Die.new()
	_seq += 1
	d.id = _seq
	d.sides = p_sides
	d.element = p_element
	d.quirk = p_quirk
	d.cooldown_max = DB.die_cooldown(p_sides)
	return d

func duplicate_die() -> Die:
	var d := Die.new()
	d.id = id
	d.sides = sides
	d.element = element
	d.quirk = quirk
	d.rolled = rolled
	d.cooldown_max = cooldown_max
	d.cooldown = cooldown
	d.broken = broken
	return d

func is_ready() -> bool:
	return not broken and cooldown <= 0

## Кубик уже брошен в этом ходу и держит своё число.
func is_locked() -> bool:
	return rolled >= 0

func cost() -> int:
	return DB.die_cost(sides)

func power_threshold() -> int:
	return DB.power_threshold(sides)

func label() -> String:
	return "d%d" % sides

## Подходит ли кубик под стихию карты. Призматический подходит под любую —
## в этом весь смысл редкого кубика: он включает отклик всегда.
func suits(card_element: String) -> bool:
	if card_element == "none":
		return false
	if quirk == "prism":
		return true
	return element == card_element

func has_quirk(q: String) -> bool:
	return quirk == q

func quirk_name() -> String:
	return str(DB.quirk_of(quirk).get("name", ""))

func quirk_text() -> String:
	return str(DB.quirk_of(quirk).get("text", ""))

## Полное имя для списков: «d10 звонкий».
func full_label() -> String:
	var t := quirk_name()
	return label() if t == "" else "%s %s" % [label(), t]
