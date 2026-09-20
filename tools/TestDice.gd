extends Node
## Проверка честности физического броска: кидаем кубик тысячи раз
## настоящей физикой и смотрим, ровное ли распределение.

## Сколько бросков на кубик. Меняется аргументом запуска: быстрая проверка
## после правки физики и длинный прогон перед сборкой — разные задачи.
var rolls_per_die := 1200

var _world: Node3D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 4242
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			rolls_per_die = int(a)
	print("=== ЧЕСТНОСТЬ ФИЗИЧЕСКОГО БРОСКА ===")
	Engine.max_fps = 0
	for sides in [4, 6, 8, 10, 12, 20]:
		var nums := Polyhedra.face_numbers(sides)
		nums.sort()
		var expected: Array = range(1, sides + 1)
		var numbering_ok: bool = str(nums) == str(expected)
		var hist := await _roll_many(sides, rolls_per_die)
		var chi := _chi_square(hist, sides)
		var lo := 999
		var hi := 0
		var cocked := int(hist.get("cocked", 0))
		for v in range(1, sides + 1):
			var c := int(hist.get(v, 0))
			lo = mini(lo, c)
			hi = maxi(hi, c)
		var mean: float = float(rolls_per_die) / sides
		print("d%-3d нумерация %s   бросков %d   мин %d макс %d (ожидалось ~%.0f)   хи² %.1f (порог %.1f)   на ребро %d" % [
			sides, "ок" if numbering_ok else "СЛОМАНА", rolls_per_die, lo, hi, mean,
			chi, _chi_threshold(sides - 1), cocked])
	get_tree().quit()

func _chi_threshold(df: int) -> float:
	# критическое значение хи-квадрат, p=0.001 — превышение означает перекос
	var table := {3: 16.3, 5: 20.5, 7: 24.3, 9: 27.9, 11: 31.3, 19: 43.8}
	return float(table.get(df, 50.0))

func _chi_square(hist: Dictionary, sides: int) -> float:
	var total := 0
	for v in range(1, sides + 1):
		total += int(hist.get(v, 0))
	if total == 0:
		return 999.0
	var expected := float(total) / sides
	var chi := 0.0
	for v in range(1, sides + 1):
		var diff := float(int(hist.get(v, 0))) - expected
		chi += diff * diff / expected
	return chi

func _roll_many(sides: int, count: int) -> Dictionary:
	_setup_world()
	var hist := {}
	for i in count:
		var result := await _one_roll(sides)
		if result.cocked:
			hist["cocked"] = int(hist.get("cocked", 0)) + 1
		hist[result.value] = int(hist.get(result.value, 0)) + 1
	_world.queue_free()
	return hist

func _setup_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 0.4, 5)
	cs.shape = box
	cs.position = Vector3(0, -0.2, 0)
	floor_body.add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.28
	floor_body.physics_material_override = pm
	_world.add_child(floor_body)
	for spec in [
		{"pos": Vector3(0, 1, -2.3), "size": Vector3(6, 3, 0.3)},
		{"pos": Vector3(0, 1, 2.3), "size": Vector3(6, 3, 0.3)},
		{"pos": Vector3(-2.8, 1, 0), "size": Vector3(0.3, 3, 5)},
		{"pos": Vector3(2.8, 1, 0), "size": Vector3(0.3, 3, 5)},
	]:
		var w := StaticBody3D.new()
		var wcs := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = spec.size
		wcs.shape = wb
		w.add_child(wcs)
		w.position = spec.pos
		_world.add_child(w)

func _one_roll(sides: int) -> Dictionary:
	var body := RigidBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Polyhedra.build_mesh(sides, Polyhedra.DIE_RADIUS)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = Polyhedra.collision_points(sides, Polyhedra.DIE_RADIUS)
	cs.shape = hull
	body.add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.62
	pm.bounce = 0.22
	body.physics_material_override = pm
	body.mass = 0.6
	# те же затухания, что и в игре: тест обязан кидать так же, иначе он
	# проверяет не ту физику, в которую играют
	body.linear_damp = 0.45
	body.angular_damp = 0.9
	body.position = Vector3(_rng.randf_range(-1.0, 1.0), 2.4, _rng.randf_range(-1.0, 1.0))
	body.basis = Polyhedra.random_orientation(_rng)
	_world.add_child(body)
	body.apply_impulse(Vector3(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-2.5, 2.5)))
	# та же нижняя граница кувырка, что в игре: тест обязан проверять ту физику,
	# в которую играют, а не более щедрую
	var torque := Vector3(_rng.randf_range(-2.2, 2.2), _rng.randf_range(-2.2, 2.2), _rng.randf_range(-2.2, 2.2))
	if torque.length() < 7.0:
		var extra := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		torque = (torque + extra * 7.0).limit_length(7.0 * 1.6)
	body.apply_torque_impulse(torque)

	var calm := 0
	var frames := 0
	var cocked := false
	while frames < 400:
		await get_tree().physics_frame
		frames += 1
		if frames < 40:
			continue
		if body.linear_velocity.length() < 0.12 and body.angular_velocity.length() < 0.5:
			calm += 1
			if calm > 6:
				break
		else:
			calm = 0

	var read := Polyhedra.read_face(sides, body.global_transform.basis)
	var tries := 0
	while read.alignment < 0.75 and tries < 3:
		cocked = true
		tries += 1
		body.apply_impulse(Vector3(_rng.randf_range(-1.2, 1.2), 1.6, _rng.randf_range(-1.2, 1.2)))
		body.apply_torque_impulse(Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5)))
		calm = 0
		frames = 0
		while frames < 300:
			await get_tree().physics_frame
			frames += 1
			if body.linear_velocity.length() < 0.12 and body.angular_velocity.length() < 0.5:
				calm += 1
				if calm > 6:
					break
			else:
				calm = 0
		read = Polyhedra.read_face(sides, body.global_transform.basis)

	body.queue_free()
	return {"value": int(read.value), "cocked": cocked}
