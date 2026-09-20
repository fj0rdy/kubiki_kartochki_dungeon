extends Node
## Автозагрузка. Единственное место, где заданы цвета, шрифты и размеры.
## Хочешь перекрасить игру — правь здесь.
##
## Направление — «мрачный манускрипт»: подземелье написано чернилами по кости.
## Отсюда правило, которого стоит держаться: тёмное — это камень и кожа,
## светлое — бумага. Карта светлая и читается как лист, интерфейс вокруг
## тёмный и уходит в тень. Насыщенный цвет допускается только там, где он
## что-то значит: стихия, редкость, кровь, латунь.

# ── тёмная сторона: камень, кожа, тень
const GROUND      := Color("14100c")   ## самый дальний фон
const GROUND_2    := Color("1d1712")   ## врезки и ниши
const PANEL       := Color("241c15")   ## панели
const RAISED      := Color("2f2519")   ## приподнятые панели
const EDGE        := Color("59452e")   ## заметный край
const EDGE_SOFT   := Color("3a2d1f")   ## еле видный край

# ── светлая сторона: текст на тёмном
const BONE        := Color("f0e6d2")
const BONE_DIM    := Color("bdab8d")
const MUTED       := Color("8d7b60")

# ── бумага: карты, свитки, всё, что «лист»
const PARCHMENT   := Color("e6d9b8")   ## лицо карты
const PARCHMENT_2 := Color("d5c39c")   ## тень на бумаге, окно иллюстрации
const INK         := Color("241a12")   ## текст по бумаге
const INK_DIM     := Color("5c4732")   ## второстепенный текст по бумаге
const WAX         := Color("8f2f22")   ## сургуч печати

# ── акценты
const BRASS       := Color("d8ab55")
const BRASS_DIM   := Color("8f6a2e")
const BLOOD       := Color("b03a26")
const HEAL        := Color("7aa257")
const CANDLE      := Color("ffcf8a")   ## свет свечи, блики

const ELEMENTS := {
	"fire":   { "name": "Огонь",   "color": Color("c4552b") },
	"ice":    { "name": "Лёд",     "color": Color("4e8bb0") },
	"nature": { "name": "Природа", "color": Color("6f9c58") },
	"light":  { "name": "Свет",    "color": Color("d8ab55") },
	"dark":   { "name": "Тьма",    "color": Color("7f5f9e") },
	"none":   { "name": "—",       "color": Color("8d7b60") },
}

## Что делает стихия, когда кубик совпал со стихией карты. Тексты живут
## здесь, потому что их показывают в трёх местах: на кубике, на карте и на
## экране сборки — и расходиться они не должны.
const RESONANCE := {
	"fire":   "Ожог: враг горит каждый ход, и ожог не слабеет.",
	"ice":    "Стужа: враг бьёт слабее несколько ходов.",
	"nature": "Побег: кубик остывает быстрее. Остужать нечего — лечит на 3.",
	"light":  "Озарение: добираешь карту. Второй раз за ход — сила +1.",
	"dark":   "Порча: яд и ожог врага растут наполовину. Ты теряешь 2 здоровья.",
}

## Одно слово для плашки на карте — там на предложение нет места.
const RESONANCE_SHORT := {
	"fire": "ожог", "ice": "стужа", "nature": "побег",
	"light": "озарение", "dark": "порча",
}

## Роль стихии в билде и её цена. Показывается на экране сборки: игрок должен
## понимать, что берёт, ДО того как соберёт мешочек из одних светлых кубиков.
## Слабость здесь не менее важна, чем сила: стихия без слабости — не выбор.
const ELEMENT_ROLE := {
	"fire":   { "job": "Убивает быстрее всех: прямой урон и ожог.",
				"cost": "Ничего не защищает и не лечит. Затянулся бой — нечем держаться." },
	"ice":    { "job": "Держит удар: блок, слабость, заморозка.",
				"cost": "Почти не бьёт. В одиночку бой не заканчивает." },
	"nature": { "job": "Кормит кубиками: возврат в строй, остывание, лечение.",
				"cost": "Сама почти не наносит урона. Даёт сыграть другим." },
	"light":  { "job": "Кормит картами: добор, сила, выплаты за руку.",
				"cost": "Добор — раз в ход. Ни блока, ни лечения." },
	"dark":   { "job": "Усиливает: пробивает блок, растит яд и ожог.",
				"cost": "Каждый раз платишь здоровьем." },
}

func element_job(id: String) -> String:
	return str(ELEMENT_ROLE.get(id, {}).get("job", ""))

func element_cost(id: String) -> String:
	return str(ELEMENT_ROLE.get(id, {}).get("cost", ""))

func resonance_short(id: String) -> String:
	return str(RESONANCE_SHORT.get(id, ""))

func resonance(id: String) -> String:
	return str(RESONANCE.get(id, ""))

## Цвет редкости: по нему карта узнаётся с одного взгляда, не читая текст.
const RARITY := {
	"basic":    { "name": "базовая",   "color": Color("7a6a52") },
	"common":   { "name": "обычная",   "color": Color("9d8c6f") },
	"uncommon": { "name": "необычная", "color": Color("4e8bb0") },
	"rare":     { "name": "редкая",    "color": Color("d8ab55") },
	"curse":    { "name": "проклятие", "color": Color("8f4a6a") },
}

func rarity_color(id: String) -> Color:
	return RARITY.get(id, RARITY["common"]).color

func rarity_name(id: String) -> String:
	return str(RARITY.get(id, RARITY["common"]).name)

func element_color(id: String) -> Color:
	return ELEMENTS.get(id, ELEMENTS["none"]).color

func element_name(id: String) -> String:
	return str(ELEMENTS.get(id, ELEMENTS["none"]).name)

## Рамка-панель нужного цвета. Используется везде, где есть «карточка» или «кубик».
func box(fill: Color, border: Color, border_width: int = 1, radius: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
