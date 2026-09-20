# -*- coding: utf-8 -*-
"""Генератор data/cards.json. Карты описаны здесь, чтобы держать пул
консистентным: редкость, архетип и апгрейд видны рядом."""
import json, collections

C = collections.OrderedDict()

def card(cid, name, element, dice, text, effects, rarity="common",
         archetype="", min_faces=None, exhaust=False, upgrade=None,
         require_element=False):
    d = {"name": name, "element": element, "dice": dice, "rarity": rarity,
         "text": text, "effects": effects}
    if archetype: d["archetype"] = archetype
    if min_faces: d["min_faces"] = min_faces
    if require_element: d["require_element"] = True
    if exhaust: d["exhaust"] = True
    if upgrade: d["upgrade"] = upgrade
    C[cid] = d

def dmg(**kw):   return dict(op="damage", **kw)
def blk(**kw):   return dict(op="block", **kw)

# ─────────────────────────────── БАЗОВЫЕ (стартовая колода, в награду не падают)
card("strike","Удар","fire",1,"Урон = бросок + 2. Огненный кубик: +2. Мощь: + половина граней.",
     [dmg(base=2, per_element=2, pow_faces=0.5)], "basic",
     upgrade={"text":"Урон = бросок + 5. Огненный кубик: +3. Мощь: + половина граней.",
              "effects":[dmg(base=5, per_element=3, pow_faces=0.5)]})
card("guard","Ледяной щит","ice",1,"Блок = бросок + 3. Ледяной кубик: +2. Мощь: + половина граней.",
     [blk(base=3, per_element=2, pow_faces=0.5)], "basic",
     upgrade={"text":"Блок = бросок + 6. Ледяной кубик: +3. Мощь: + половина граней.",
              "effects":[blk(base=6, per_element=3, pow_faces=0.5)]})
card("heavy","Мощный удар","fire",1,"Урон = бросок × 2. Огненный: +4. Мощь: + половина граней.",
     [dmg(roll_mult=2, per_element=4, pow_faces=0.5)], "basic", "burst", min_faces=6,
     upgrade={"text":"Урон = бросок × 2 + 4. Огненный: +4. Мощь: + граней. Годится любой кубик.",
              "min_faces":0,
              "effects":[dmg(roll_mult=2, base=4, per_element=4, pow_faces=1.0)]})
card("breath","Второе дыхание","none",1,"Возвращает в строй самый крупный остывший кубик. Блок = бросок. Мощь: +3.",
     [dict(op="refresh_dice", base=1), blk(base=0, pow_flat=3)], "basic", "tempo",
     upgrade={"text":"Возвращает в строй самый крупный остывший кубик. Блок = бросок + 4. Мощь: ещё +4.",
              "effects":[dict(op="refresh_dice", base=1), blk(base=4, pow_flat=4)]})
# ─────────────────────────────── ОБЫЧНЫЕ — по одному заводиле на каждый архетип
card("jab","Тычок","fire",1,"Урон = бросок + 5.",[dmg(base=5)],"common",
     upgrade={"text":"Урон = бросок + 8.","effects":[dmg(base=8)]})
card("brace","Упор","ice",1,"Блок = бросок + 5.",[blk(base=5)],"common",
     upgrade={"text":"Блок = бросок + 8.","effects":[blk(base=8)]})
card("venom","Ядовитый клинок","nature",1,"Яд = бросок. Природный кубик: +2. Мощь: + четверть граней.",
     [dict(op="poison", per_element=2, pow_faces=0.25)],"common","rot",
     upgrade={"text":"Яд = бросок + 3. Природный кубик: +2. Мощь: + четверть граней.",
              "effects":[dict(op="poison", base=3, per_element=2, pow_faces=0.25)]})
card("spark","Искра","light",1,"Урон = бросок + 1. Добери карту.",
     [dmg(base=1), dict(op="draw_cards", base=1)],"common","tempo",
     upgrade={"text":"Урон = бросок + 3. Добери карту.",
              "effects":[dmg(base=3), dict(op="draw_cards", base=1)]})
card("pebbles","Горсть камней","fire",2,"Урон = сумма + 3.",[dmg(base=3)],"common","swarm",
     upgrade={"text":"Урон = сумма + 6.","effects":[dmg(base=6)]})
card("wall","Стена","ice",2,"Блок = сумма + 4. Каждый ледяной кубик: +2.",
     [blk(base=4, per_element=2)],"common","swarm",
     upgrade={"text":"Блок = сумма + 7. Каждый ледяной кубик: +3.",
              "effects":[blk(base=7, per_element=3)]})
card("hexweak","Проклятие слабости","dark",1,"Атаки врага слабее на бросок в течение 2 ходов. Тёмный: +2.",
     [dict(op="weaken", per_element=2, turns=2)],"common","rot",
     upgrade={"text":"Атаки врага слабее на бросок в течение 3 ходов. Тёмный: +3.",
              "effects":[dict(op="weaken", per_element=3, turns=3)]})
card("focus","Сосредоточение","nature",1,"Остуди 1 кубик. Природный кубик: ещё 1.",
     [dict(op="cool_dice", base=1, per_element=1)],"common","tempo",
     upgrade={"text":"Остуди 2 кубика. Природный кубик: ещё 1.",
              "effects":[dict(op="cool_dice", base=2, per_element=1)]})
card("attune","Созвучие","fire",1,"Урон = бросок + 2. Огненный кубик: ещё +7.",
     [dmg(base=2, per_element=7)],"common","element",
     upgrade={"text":"Урон = бросок + 4. Огненный кубик: ещё +9.",
              "effects":[dmg(base=4, per_element=9)]})
card("regen","Регенерация","nature",1,"Лечение = бросок + 3. Природный: +3.",
     [dict(op="heal", base=3, per_element=3)],"common",
     upgrade={"text":"Лечение = бросок + 6. Природный: +4.",
              "effects":[dict(op="heal", base=6, per_element=4)]})
card("aim","Точный расчёт","none",1,"Бросок дважды, берётся лучший. Урон = результат + 5.",
     [dict(op="reroll_best_damage", base=5)],"common","burst",
     upgrade={"text":"Бросок дважды, берётся лучший. Урон = результат + 9.",
              "effects":[dict(op="reroll_best_damage", base=9)]})
card("shatter","Раскол","dark",1,"Урон = бросок + 3, игнорирует блок.",
     [dmg(base=3, pierce=True)],"common", min_faces=6,
     upgrade={"text":"Урон = бросок + 6, игнорирует блок.","effects":[dmg(base=6, pierce=True)]})
card("chill","Озноб","ice",1,"Блок = бросок + 2. Яд 3.",
     [blk(base=2), dict(op="poison", base=3)],"common","rot",
     upgrade={"text":"Блок = бросок + 4. Яд 5.",
              "effects":[blk(base=4), dict(op="poison", base=5)]})
card("tally","Пересчёт","none",2,"Блок = сумма. Добери карту.",
     [blk(), dict(op="draw_cards", base=1)],"common","swarm",
     upgrade={"text":"Блок = сумма + 4. Добери карту.",
              "effects":[blk(base=4), dict(op="draw_cards", base=1)]})
card("stoke","Раздуть","fire",1,"Урон = бросок + 2. Этот кубик остынет на ход быстрее.",
     [dmg(base=2), dict(op="cool_paid", base=1)],"common","tempo",
     upgrade={"text":"Урон = бросок + 4. Этот кубик остынет на два хода быстрее.",
              "effects":[dmg(base=4), dict(op="cool_paid", base=2)]})

# ─────────────────────────────── НЕОБЫЧНЫЕ — меняют пропорции
card("volley","Град ударов","fire",2,"Два удара по броску + 2. Огненный кубик: +3 к своему.",
     [dict(op="multi_hit", base=2, per_element=3)],"uncommon","swarm",
     upgrade={"text":"Два удара по броску + 4. Огненный кубик: +4 к своему.",
              "effects":[dict(op="multi_hit", base=4, per_element=4)]})
card("swarm","Ярость мелочи","fire",3,"Урон = сумма + 5 за каждый d4 или d6, игнорирует блок.",
     [dmg(per_small=5, pierce=True)],"uncommon","swarm",
     upgrade={"text":"Урон = сумма + 8 за каждый d4 или d6, игнорирует блок.",
              "effects":[dmg(per_small=8, pierce=True)]})
card("combo","Комбинированный выстрел","none",2,"Урон = сумма + 2. Если сумма ≥ 14: +9.",
     [dmg(base=2, sum_threshold=14, threshold_bonus=9)],"uncommon","burst",
     upgrade={"text":"Урон = сумма + 4. Если сумма ≥ 12: +12.",
              "effects":[dmg(base=4, sum_threshold=12, threshold_bonus=12)]})
card("chain","Цепная молния","light",2,"Урон = сумма + 2. Если сумма ≥ 12: +9 и снимает блок врага.",
     [dmg(base=2, per_element=2, sum_threshold=12, threshold_bonus=9, strip_block_on_threshold=True)],
     "uncommon","burst",
     upgrade={"text":"Урон = сумма + 4. Если сумма ≥ 10: +12 и снимает блок врага.",
              "effects":[dmg(base=4, per_element=2, sum_threshold=10, threshold_bonus=12, strip_block_on_threshold=True)]})
card("icearrow","Ледяная стрела","ice",1,"Урон = бросок + 3. Мощь: враг пропускает следующую атаку.",
     [dmg(base=3, per_element=2), dict(op="freeze_if_power")],"uncommon",
     upgrade={"text":"Урон = бросок + 6. Мощь: враг пропускает следующую атаку.",
              "effects":[dmg(base=6, per_element=2), dict(op="freeze_if_power")]})
card("typhoon","Тайфун","ice",1,"Урон = бросок × 2, игнорирует блок. Ты теряешь 5 здоровья.",
     [dmg(roll_mult=2, per_element=2, pierce=True), dict(op="self_damage", base=5)],
     "uncommon","burst", min_faces=10,
     upgrade={"text":"Урон = бросок × 2, игнорирует блок. Ты теряешь 2 здоровья.",
              "effects":[dmg(roll_mult=2, per_element=2, pierce=True), dict(op="self_damage", base=2)]})
card("bless","Благословение","light",1,"Сила + бросок ÷ 3 (мин. 1) до конца боя. Светлый: +1.",
     [dict(op="strength", roll_mult=0.3333, min=1, per_element=1)],"uncommon",
     upgrade={"text":"Сила + бросок ÷ 2 (мин. 2) до конца боя. Светлый: +1.",
              "effects":[dict(op="strength", roll_mult=0.5, min=2, per_element=1)]})
card("pierce","Пробой","dark",1,"Урон = бросок + 4, игнорирует блок. Уязвимость 2 хода.",
     [dmg(base=4, per_element=2, pierce=True), dict(op="vulnerable", turns=2)],
     "uncommon","rot", min_faces=8,
     upgrade={"text":"Урон = бросок + 6, игнорирует блок. Уязвимость 3 хода. Годится d6+.",
              "min_faces":6,
              "effects":[dmg(base=6, per_element=2, pierce=True), dict(op="vulnerable", turns=3)]})
card("hurry","Спешка","light",1,"Добери 3 карты.",
     [dict(op="draw_cards", base=3)],"uncommon","tempo",
     upgrade={"text":"Добери 3 карты. Мощь: сила +2.",
              "effects":[dict(op="draw_cards", base=3), dict(op="strength", base=0, pow_flat=2)]})
card("sacrifice","Жертва","dark",1,"Урон = бросок + граней, игнорирует блок. Кубик ломается до конца боя.",
     [dmg(faces_mult=1.0, pierce=True), dict(op="break_dice")],"uncommon","burst",
     upgrade={"text":"Урон = бросок × 2 + граней, игнорирует блок. Кубик ломается до конца боя.",
              "effects":[dmg(roll_mult=2, faces_mult=1.0, pierce=True), dict(op="break_dice")]})
card("cascade","Каскад","nature",2,"Урон = сумма. Верни в строй один остывший кубик.",
     [dmg(), dict(op="refresh_dice", base=1)],"uncommon","tempo",
     upgrade={"text":"Урон = сумма + 4. Верни в строй два остывших кубика.",
              "effects":[dmg(base=4), dict(op="refresh_dice", base=2)]})
card("bulwark","Оплот","ice",1,"Блок = бросок × 2.",[blk(roll_mult=2, per_element=2)],
     "uncommon","burst", min_faces=8,
     upgrade={"text":"Блок = бросок × 2 + 5. Годится d6+.","min_faces":6,
              "effects":[blk(roll_mult=2, base=5, per_element=2)]})
card("rot","Гниль","nature",1,"Яд = бросок + 4. Мощь: яд удваивается.",
     [dict(op="poison", base=4, per_element=2, pow_mult=2.0)],"uncommon","rot",
     upgrade={"text":"Яд = бросок + 7. Мощь: яд удваивается.",
              "effects":[dict(op="poison", base=7, per_element=2, pow_mult=2.0)]})
card("siphon","Вытяжка","dark",1,"Урон = бросок + 2. Лечит на половину нанесённого.",
     [dmg(base=2, per_element=2, lifesteal=0.5)],"uncommon",
     upgrade={"text":"Урон = бросок + 5. Лечит на половину нанесённого.",
              "effects":[dmg(base=5, per_element=2, lifesteal=0.5)]})
card("flurry","Вихрь","fire",3,"Три удара по броску + 1.",
     [dict(op="multi_hit", base=1, per_element=2)],"uncommon","swarm",
     upgrade={"text":"Три удара по броску + 3.",
              "effects":[dict(op="multi_hit", base=3, per_element=2)]})
card("overload","Перегрузка","fire",1,"Урон = бросок × 2 + 3. Кубик остывает на ход дольше.",
     [dmg(roll_mult=2, base=3), dict(op="cool_paid", base=-1)],"uncommon","burst",
     upgrade={"text":"Урон = бросок × 2 + 7. Кубик остывает на ход дольше.",
              "effects":[dmg(roll_mult=2, base=7), dict(op="cool_paid", base=-1)]})
card("patience","Терпение","ice",1,"Блок = бросок + 3. Блок не сгорает в конце хода.",
     [blk(base=3, per_element=2), dict(op="retain_block")],"uncommon",
     upgrade={"text":"Блок = бросок + 6. Блок не сгорает в конце хода.",
              "effects":[blk(base=6, per_element=2), dict(op="retain_block")]})
card("thorns","Шипы","nature",1,"Шипы = бросок ÷ 2 (мин. 2) до конца боя.",
     [dict(op="thorns", roll_mult=0.5, min=2, per_element=1)],"uncommon","rot",
     upgrade={"text":"Шипы = бросок (мин. 3) до конца боя.",
              "effects":[dict(op="thorns", roll_mult=1.0, min=3, per_element=1)]})
card("drain","Иссушение","dark",1,"Яд = бросок ÷ 2. Атаки врага слабее на бросок ÷ 2 (2 хода).",
     [dict(op="poison", roll_mult=0.5, min=1), dict(op="weaken", roll_mult=0.5, min=1, turns=2)],
     "uncommon","rot",
     upgrade={"text":"Яд = бросок. Атаки врага слабее на бросок ÷ 2 (3 хода).",
              "effects":[dict(op="poison", roll_mult=1.0, min=1), dict(op="weaken", roll_mult=0.5, min=1, turns=3)]})
card("sparkstorm","Град искр","light",3,"Урон = сумма. Добери 2 карты.",
     [dmg(), dict(op="draw_cards", base=2)],"uncommon","tempo",
     upgrade={"text":"Урон = сумма + 5. Добери 2 карты.",
              "effects":[dmg(base=5), dict(op="draw_cards", base=2)]})
card("mirror","Отражение","ice",2,"Блок = сумма + 2. Урон = половина этого блока.",
     [blk(base=2, per_element=2), dict(op="damage_from_block", roll_mult=0.5)],"uncommon",
     upgrade={"text":"Блок = сумма + 5. Урон = половина этого блока.",
              "effects":[blk(base=5, per_element=2), dict(op="damage_from_block", roll_mult=0.5)]})

# — стихийный архетип: карты, которые принимают только свою стихию
card("emberlink","Огненная связь","fire",2,"Принимает только огненные кубики. Урон = сумма + 12.",
     [dmg(base=12)],"uncommon","element", require_element=True,
     upgrade={"text":"Принимает только огненные кубики. Урон = сумма + 18.",
              "effects":[dmg(base=18)]})
card("frostbond","Ледяной обет","ice",2,"Принимает только ледяные кубики. Блок = сумма + 12.",
     [blk(base=12)],"uncommon","element", require_element=True,
     upgrade={"text":"Принимает только ледяные кубики. Блок = сумма + 18.",
              "effects":[blk(base=18)]})
card("bloom","Цветение","nature",1,"Принимает только природные кубики. Яд = бросок + 5. Лечение 6.",
     [dict(op="poison", base=5), dict(op="heal", base=6)],"uncommon","element", require_element=True,
     upgrade={"text":"Принимает только природные кубики. Яд = бросок + 8. Лечение 10.",
              "effects":[dict(op="poison", base=8), dict(op="heal", base=10)]})
card("covenant","Завет","light",1,"Принимает только светлые кубики. Урон = бросок × 3, игнорирует блок.",
     [dmg(roll_mult=3, pierce=True)],"rare","element", require_element=True,
     upgrade={"text":"Принимает только светлые кубики. Урон = бросок × 4, игнорирует блок.",
              "effects":[dmg(roll_mult=4, pierce=True)]})
card("eclipse","Затмение","dark",2,"Принимает только тёмные кубики. Урон = сумма × 2. Уязвимость 3 хода.",
     [dmg(roll_mult=2, pierce=True), dict(op="vulnerable", turns=3)],"rare","element", require_element=True,
     upgrade={"text":"Принимает только тёмные кубики. Урон = сумма × 3. Уязвимость 3 хода.",
              "effects":[dmg(roll_mult=3, pierce=True), dict(op="vulnerable", turns=3)]})

# ─────────────────────────────── РЕДКИЕ — меняют правило
card("avalanche","Лавина","ice",3,"Блок = сумма × 2.",[blk(roll_mult=2, per_element=2)],
     "rare","swarm",
     upgrade={"text":"Блок = сумма × 2 + 8.","effects":[blk(roll_mult=2, base=8, per_element=2)]})
card("apex","Вершина","fire",1,"Урон = бросок × 2 + половина граней, игнорирует блок. Годится d8+.",
     [dmg(roll_mult=2, faces_mult=0.5, pierce=True)],"rare","burst", min_faces=8,
     upgrade={"text":"Урон = бросок × 2 + граней, игнорирует блок. Годится d8+.",
              "effects":[dmg(roll_mult=2, faces_mult=1.0, pierce=True)]})
card("swarmlord","Повелитель мелочи","fire",3,"Урон = 7 за каждый готовый кубик в мешочке, игнорирует блок.",
     [dict(op="damage_per_ready", base=7, pierce=True)],"rare","swarm",
     upgrade={"text":"Урон = 10 за каждый готовый кубик в мешочке, игнорирует блок.",
              "effects":[dict(op="damage_per_ready", base=10, pierce=True)]})
card("unwind","Раскрутка","nature",1,"До конца боя все твои кубики остывают на ход быстрее. Карта сгорает.",
     [dict(op="forge_all", base=1)],"rare","tempo", exhaust=True,
     upgrade={"text":"До конца боя все твои кубики остывают на ход быстрее. Добери 2 карты. Карта сгорает.",
              "effects":[dict(op="forge_all", base=1), dict(op="draw_cards", base=2)]})
card("plague","Чума","nature",1,"Яд = бросок × 2. Дальше яд убывает вдвое медленнее.",
     [dict(op="poison", roll_mult=2, per_element=2), dict(op="poison_persist")],"rare","rot",
     upgrade={"text":"Яд = бросок × 3. Дальше яд убывает вдвое медленнее.",
              "effects":[dict(op="poison", roll_mult=3, per_element=2), dict(op="poison_persist")]})
card("resonance","Резонанс","fire",2,"Урон = сумма + 10 за каждый огненный кубик.",
     [dmg(per_element=10)],"rare","element",
     upgrade={"text":"Урон = сумма + 14 за каждый огненный кубик.",
              "effects":[dmg(per_element=14)]})
card("fortress","Крепость","ice",1,"Блок = бросок. Блок не сгорает до конца боя. Карта сгорает.",
     [blk(per_element=2), dict(op="retain_block_forever")],"rare", exhaust=True,
     upgrade={"text":"Блок = бросок + 8. Блок не сгорает до конца боя. Карта сгорает.",
              "effects":[blk(base=8, per_element=2), dict(op="retain_block_forever")]})
card("gamble","Азарт","dark",1,"Урон = бросок × 3. Если выпал минимум — теряешь 12 здоровья.",
     [dmg(roll_mult=3), dict(op="punish_min_roll", base=12)],"rare","burst",
     upgrade={"text":"Урон = бросок × 3 + 4. Если выпал минимум — теряешь 6 здоровья.",
              "effects":[dmg(roll_mult=3, base=4), dict(op="punish_min_roll", base=6)]})
card("forge","Горн","none",1,"Этот кубик навсегда остывает на ход быстрее. Карта сгорает.",
     [dict(op="forge_die")],"rare","tempo", exhaust=True,
     upgrade={"text":"Этот кубик навсегда остывает на два хода быстрее. Карта сгорает.",
              "effects":[dict(op="forge_die", base=2)]})
card("bloodpact","Кровавый договор","dark",1,"Урон = бросок + недостающее здоровье ÷ 3, игнорирует блок.",
     [dmg(missing_hp=0.3333, pierce=True)],"rare","burst",
     upgrade={"text":"Урон = бросок + недостающее здоровье ÷ 2, игнорирует блок.",
              "effects":[dmg(missing_hp=0.5, pierce=True)]})
card("harvest","Жатва","dark",2,"Урон = сумма + текущий яд врага. Половина яда тратится.",
     [dmg(plus_poison=True, spend_poison=0.5)],"rare","rot",
     upgrade={"text":"Урон = сумма + текущий яд врага × 2. Половина яда тратится.",
              "effects":[dmg(plus_poison=True, poison_mult=2.0, spend_poison=0.5)]})
# «Верни в строй ВСЕ кубики» ломало бой: можно придержать два кубика под эту
# карту, слить всю руку, а потом сыграть ещё одну целиком. Возврат ограничен
# числом — карта осталась сильной, но перестала быть отдельным ходом.
# Возврат кубиков — это темп, а не ресурс: карта не должна возвращать
# больше, чем стоит сама, иначе ход становится бесконечным.
card("tempo","Разгон","nature",2,"Верни в строй до двух остывших кубиков. Добери карту.",
     [dict(op="refresh_dice", base=2), dict(op="draw_cards", base=1)],"rare","tempo",
     upgrade={"text":"Верни в строй до двух остывших кубиков. Добери 2 карты.",
              "effects":[dict(op="refresh_dice", base=2), dict(op="draw_cards", base=2)]})
# ─────────────────────────── УСИЛИТЕЛИ СТИХИЙ
# Пары «заводила → выплата». Заводила сам по себе слабый, но кладёт на врага
# то, чем выплата потом бьёт. Это и есть причина собирать колоду одной стихии,
# а не брать каждую карту с самым большим числом.

card("kindling","Растопка","fire",1,"Ожог +3. Огненный кубик: ещё +2. Ожог не слабеет.",
     [dict(op="burn", roll_mult=0, base=3, per_element=2)],"common","burn",
     upgrade={"text":"Ожог +5. Огненный кубик: ещё +3. Ожог не слабеет.",
              "effects":[dict(op="burn", roll_mult=0, base=5, per_element=3)]})
card("pyre","Костёр","fire",2,"Урон = сумма + 3 + ожог врага × 2. Половина ожога гаснет.",
     [dmg(base=3, plus_burn=True, burn_mult=2.0, spend_burn=0.5)],"uncommon","burn",
     upgrade={"text":"Урон = сумма + 5 + ожог врага × 3. Половина ожога гаснет.",
              "effects":[dmg(base=5, plus_burn=True, burn_mult=3.0, spend_burn=0.5)]})
card("hoarfrost","Иней","ice",1,"Блок = бросок + 2. Ледяной кубик: враг бьёт слабее на 3 (2 хода).",
     [blk(base=2), dict(op="weaken", roll_mult=0, base=0, per_element=3, turns=2)],"common",
     upgrade={"text":"Блок = бросок + 5. Ледяной кубик: враг бьёт слабее на 4 (2 хода).",
              "effects":[blk(base=5), dict(op="weaken", roll_mult=0, base=0, per_element=4, turns=2)]})
card("shardfall","Осколкопад","ice",1,"Урон = твой блок + 4. Блок остаётся.",
     [dict(op="damage_from_block", share=1.0, base=4)],"uncommon","element",
     upgrade={"text":"Урон = твой блок + 8. Блок остаётся.",
              "effects":[dict(op="damage_from_block", share=1.0, base=8)]})
card("graft","Прививка","nature",1,"Остуди 1 кубик. Лечение = бросок ÷ 2 (мин. 2).",
     [dict(op="cool_dice", base=1), dict(op="heal", roll_mult=0.5, min=2)],"common","tempo",
     upgrade={"text":"Остуди 1 кубик. Лечение = бросок (мин. 4).",
              "effects":[dict(op="cool_dice", base=1), dict(op="heal", min=4)]})
card("overgrowth","Разрастание","nature",2,"Урон = 5 за каждый готовый кубик в мешочке. Остуди 1 кубик.",
     [dict(op="damage_per_ready", base=5), dict(op="cool_dice", base=1)],"uncommon","swarm",
     upgrade={"text":"Урон = 7 за каждый готовый кубик в мешочке. Остуди 2 кубика.",
              "effects":[dict(op="damage_per_ready", base=7), dict(op="cool_dice", base=2)]})
card("revelation","Откровение","light",1,"Урон = бросок + 2 за каждую карту в руке.",
     [dmg(per_hand=2)],"common","hand",
     upgrade={"text":"Урон = бросок + 3 за каждую карту в руке.",
              "effects":[dmg(per_hand=3)]})
card("litany","Литания","light",2,"Сила +2. Добери карту.",
     [dict(op="strength", roll_mult=0, base=2), dict(op="draw_cards", base=1)],"uncommon","hand",
     upgrade={"text":"Сила +3. Добери 2 карты.",
              "effects":[dict(op="strength", roll_mult=0, base=3), dict(op="draw_cards", base=2)]})
card("offering","Подношение","dark",1,"Потеряй 3 здоровья. Яд = бросок + 5. Тёмный кубик: ещё +2.",
     [dict(op="self_damage", roll_mult=0, base=3), dict(op="poison", base=5, per_element=2)],"common","rot",
     upgrade={"text":"Потеряй 3 здоровья. Яд = бросок + 8. Тёмный кубик: ещё +3.",
              "effects":[dict(op="self_damage", roll_mult=0, base=3), dict(op="poison", base=8, per_element=3)]})
card("famine","Голод","dark",2,"Яд и ожог врага усиливаются наполовину. Урон = сумма + 4.",
     [dict(op="amplify_rot", base=1, per_element=1), dmg(base=4)],"uncommon","rot",
     upgrade={"text":"Яд и ожог врага усиливаются наполовину, дважды. Урон = сумма + 4.",
              "effects":[dict(op="amplify_rot", base=2, per_element=1), dmg(base=4)]})

# ─────────────────────────── ВЫПЛАТЫ ЗА МЕЛОЧЬ
# d20 подорожал, и рой мелких кубиков должен иметь свой потолок, а не быть
# «бедной версией одного большого». Эти карты платят за количество, а не за
# размер: положить в них d20 бессмысленно.

card("tithe","Десятина","fire",2,"Урон = сумма + 4 за каждый d4 или d6.",
     [dmg(per_small=4)],"common","swarm",
     upgrade={"text":"Урон = сумма + 6 за каждый d4 или d6.",
              "effects":[dmg(per_small=6)]})
card("handful","Горсть","nature",3,"Остуди 1 кубик за каждый d4 или d6. Урон = сумма.",
     [dict(op="cool_dice", base=0, per_small=1), dmg()],"uncommon","swarm",
     upgrade={"text":"Остуди 1 кубик за каждый d4 или d6. Урон = сумма + 5.",
              "effects":[dict(op="cool_dice", base=0, per_small=1), dmg(base=5)]})

# ─────────────────────────── РАСТУЩИЕ КАРТЫ
# Второй розыгрыш за бой сильнее первого. Это даёт колоде «поздний ход»:
# появляется смысл не выкладывать карту сразу, а держать её под длинный бой —
# и появляется причина уменьшать колоду, чтобы карта успела прийти дважды.

card("swell","Нарастающий удар","fire",1,"Урон = бросок + 3. Каждый следующий раз за бой: ещё +4.",
     [dmg(base=3, per_play=4)],"common",
     upgrade={"text":"Урон = бросок + 5. Каждый следующий раз за бой: ещё +6.",
              "effects":[dmg(base=5, per_play=6)]})
card("snowball","Снежный ком","ice",1,"Блок = бросок + 3. Каждый следующий раз за бой: ещё +4.",
     [blk(base=3, per_play=4)],"common",
     upgrade={"text":"Блок = бросок + 5. Каждый следующий раз за бой: ещё +6.",
              "effects":[blk(base=5, per_play=6)]})
card("creep","Ползучая гниль","nature",1,"Яд = бросок ÷ 2 + 2. Каждый следующий раз за бой: ещё +3.",
     [dict(op="poison", roll_mult=0.5, base=2, per_play=3)],"uncommon","rot",
     upgrade={"text":"Яд = бросок ÷ 2 + 4. Каждый следующий раз за бой: ещё +4.",
              "effects":[dict(op="poison", roll_mult=0.5, base=4, per_play=4)]})
card("dirge","Погребальная песнь","dark",2,"Урон = сумма + 2, игнорирует блок. Каждый следующий раз за бой: ещё +5.",
     [dmg(base=2, per_play=5, pierce=True)],"uncommon","burst",
     upgrade={"text":"Урон = сумма + 5, игнорирует блок. Каждый следующий раз за бой: ещё +7.",
              "effects":[dmg(base=5, per_play=7, pierce=True)]})
card("liturgy","Литания часов","light",1,"Сила +1. Добери карту. Каждый следующий раз за бой: сила ещё +1.",
     [dict(op="strength", roll_mult=0, base=1, per_play=1), dict(op="draw_cards", base=1)],"uncommon","hand",
     upgrade={"text":"Сила +2. Добери карту. Каждый следующий раз за бой: сила ещё +2.",
              "effects":[dict(op="strength", roll_mult=0, base=2, per_play=2), dict(op="draw_cards", base=1)]})
card("memorial","Костёр памяти","fire",2,"Ожог +4. Каждый следующий раз за бой: ещё +4.",
     [dict(op="burn", roll_mult=0, base=4, per_play=4)],"rare","burn",
     upgrade={"text":"Ожог +6. Каждый следующий раз за бой: ещё +6.",
              "effects":[dict(op="burn", roll_mult=0, base=6, per_play=6)]})

# ─────────────────────────── КАРТЫ, КОТОРЫЕ ЛОМАЮТ ПРАВИЛО
# У каждой игры есть правила, которые игрок принимает как данность. Карта,
# которая одно такое правило отменяет, запоминается сильнее любых цифр —
# поэтому все они редкие, и почти все сгорают.

card("eternal","Вечный кубик","nature",1,"Оплаченный кубик не уходит на перезарядку. Карта сгорает.",
     [dict(op="no_cooldown")],"rare","tempo", exhaust=True,
     upgrade={"text":"Оплаченный кубик не уходит на перезарядку. Добери карту. Карта сгорает.",
              "effects":[dict(op="no_cooldown"), dict(op="draw_cards", base=1)]})
card("allin","Ва-банк","fire",3,"Урон = сумма × 2. Весь мешочек уходит на перезарядку.",
     [dmg(roll_mult=2), dict(op="exhaust_dice")],"rare","burst",
     upgrade={"text":"Урон = сумма × 2 + 8. Весь мешочек уходит на перезарядку.",
              "effects":[dmg(roll_mult=2, base=8), dict(op="exhaust_dice")]})
card("reprieve","Отсрочка","ice",2,"Блок = сумма. Враг пропускает следующий ход. Карта сгорает.",
     [blk(), dict(op="freeze")],"rare", exhaust=True,
     upgrade={"text":"Блок = сумма + 6. Враг пропускает следующий ход. Карта сгорает.",
              "effects":[blk(base=6), dict(op="freeze")]})
card("barter","Мена","dark",1,"Сбрось всю руку и добери на одну карту больше. Ты теряешь 2 здоровья.",
     [dict(op="self_damage", roll_mult=0, base=2), dict(op="discard_draw", base=1, keep="barter")],"rare","hand",
     upgrade={"text":"Сбрось всю руку и добери на две карты больше. Ты теряешь 2 здоровья.",
              "effects":[dict(op="self_damage", roll_mult=0, base=2), dict(op="discard_draw", base=2, keep="barter")]})
card("twicecast","Двойной бросок","none",1,"Брось кубик второй раз. Урон = сумма обоих бросков + 4.",
     [dict(op="roll_twice_sum", base=4)],"rare","burst",
     upgrade={"text":"Брось кубик второй раз. Урон = сумма обоих бросков + 9.",
              "effects":[dict(op="roll_twice_sum", base=9)]})
card("reckoning","Расплата","dark",1,"Урон = бросок + недостающее здоровье ÷ 2, игнорирует блок. Ты теряешь 4. Карта сгорает.",
     [dmg(missing_hp=0.5, pierce=True), dict(op="self_damage", roll_mult=0, base=4)],"rare","burst", exhaust=True,
     upgrade={"text":"Урон = бросок + недостающее здоровье, игнорирует блок. Ты теряешь 4. Карта сгорает.",
              "effects":[dmg(missing_hp=1.0, pierce=True), dict(op="self_damage", roll_mult=0, base=4)]})

# ─────────────────────────────── ПРОКЛЯТИЯ — только из событий и от врагов
def curse(cid, name, text, effects=None):
    C[cid] = {"name": name, "element": "dark", "dice": 0, "rarity": "curse",
              "text": text, "unplayable": True, "effects": effects or []}
curse("jam","Заклинило","Нельзя разыграть. Занимает место в руке.")
curse("rust","Ржавчина","Нельзя разыграть. Приходя в руку, добавляет ход перезарядки случайному кубику.",
      [dict(op="rust_on_draw", base=1)])
curse("doubt","Сомнение","Нельзя разыграть. Пока в руке, весь твой блок слабее на 3.")
curse("weight","Груз","Нельзя разыграть. Приходя в руку, отнимает 2 здоровья.",
      [dict(op="hurt_on_draw", base=2)])

out = collections.OrderedDict()
out["_"] = "КАРТЫ. rarity: basic (стартовые, в награду не падают) | common | uncommon | rare | curse."
out["_archetype"] = "swarm — много мелких кубиков, burst — крупные, element — совпадение стихии, tempo — перезарядка, rot — яд и порча. Нужен чтобы следить, что у каждого стиля есть и заводилы, и выплаты."
out["_upgrade"] = "Блок upgrade перекрывает перечисленные в нём поля улучшенной версии. Улучшить карту можно на привале."
out["_fields"] = {
    "roll_mult":"умножить бросок (сумму) на это, по умолчанию 1",
    "faces_mult":"прибавить число граней × это (бросок при этом никуда не девается)",
    "base":"плоская прибавка",
    "per_element":"прибавка за каждый кубик, чья стихия совпала со стихией карты",
    "per_small":"прибавка за каждый d4 или d6",
    "pow_faces":"при Мощи прибавить граней × это",
    "pow_flat":"при Мощи прибавить столько",
    "pow_mult":"при Мощи умножить итог на это",
    "min":"итог не меньше этого",
    "sum_threshold":"если сумма броска не меньше — сработает threshold_bonus",
    "threshold_bonus":"прибавка при достижении порога",
    "pierce":"true — игнорирует блок врага",
    "lifesteal":"доля нанесённого урона возвращается здоровьем",
    "missing_hp":"прибавить недостающее здоровье × это",
    "plus_poison":"прибавить текущий яд врага",
    "strip_block_on_threshold":"при достижении порога снять блок врага",
    "require_element":"карта принимает только кубики своей стихии",
}
out["_rule"] = ("ПРАВИЛО: бросок обязан входить в любую формулу урона и блока. "
    "Эффект, который считается только по граням, делает крупный кубик стабильным — "
    "и весь выбор «каким кубиком платить» схлопывается в «всегда самым большим».")
out["_resonance"] = ("Отклик стихии срабатывает сам, когда стихия кубика совпала со стихией карты, "
    "и в тексте карты его писать не надо: огонь жжёт, лёд студит, природа ускоряет перезарядку, "
    "свет даёт добор, тьма делает врага уязвимым ценой здоровья. Тексты живут в Palette.RESONANCE.")
out["cards"] = C
json.dump(out, open("data/cards.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("карт:", len(C))
