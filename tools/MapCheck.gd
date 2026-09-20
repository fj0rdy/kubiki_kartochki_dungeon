extends Node
## Проверка генератора: считает цепочки мирных комнат и наличие привала.
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var chains := 0
	var no_rest := 0
	var counts := {}
	for i in 300:
		var m := DungeonMap.generate(rng)
		for a in m.acts:
			var rows: Array = a.rows
			if str(rows[rows.size() - 2][0].type) != "rest":
				no_rest += 1
			# предбоссовый привал — задуманная передышка, он в счёт не идёт
			for r in max(0, rows.size() - 2):
				for node in rows[r]:
					var t := str(node.type)
					counts[t] = int(counts.get(t, 0)) + 1
					if not DungeonMap.PEACEFUL.has(t):
						continue
					if r + 1 >= rows.size() - 2:
						continue
					for c in node.get("next", []):
						var up: Dictionary = rows[r + 1][int(c)]
						if DungeonMap.PEACEFUL.has(str(up.type)):
							chains += 1
	print("цепочек мирных комнат подряд: ", chains)
	print("актов без привала перед боссом: ", no_rest)
	print("комнаты: ", counts)
	get_tree().quit()
