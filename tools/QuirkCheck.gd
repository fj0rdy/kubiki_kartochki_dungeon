extends Node
## Проверка: свойства кубиков применяются к БРОСКУ, а не только к описанию.

func _ready() -> void:
	var c := Combat.new()
	c.rng.seed = 777
	var bag: Array = []
	for spec in [[12, "fire", "heavy"], [6, "ice", "greedy"], [20, "dark", "cold"], [8, "light", ""]]:
		bag.append(Die.make(int(spec[0]), str(spec[1]), str(spec[2])))
	c.setup(bag, ["strike"], 70, 70, {"name": "Тест", "hp": 999, "moves": []})
	var lo := {}
	for d in c.bag:
		var worst := 999
		var best := 0
		for i in 400:
			d.rolled = -1
			var v := c.apply_quirks(d, c.rng.randi_range(1, d.sides))
			worst = mini(worst, v)
			best = maxi(best, v)
		print("d%-3d %-8s минимум %2d, максимум %2d" % [d.sides, d.quirk if d.quirk != "" else "обычный", worst, best])
	get_tree().quit()
