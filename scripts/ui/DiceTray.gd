class_name DiceTray
extends Control
## Поле для броска — не коробка на столе, а сам стол.
##
## Раньше лоток был маленьким прямоугольником с латунным бортом, зажатым
## между логом и списком приёмов врага. Но бросок — главное действие в игре,
## и смотреть на него игрок должен туда же, куда смотрит всё остальное время:
## в центр экрана. Борта больше нет, сукно постелено овалом прямо по доске,
## а само поле занимает всю середину между героем и врагом.
##
## Кубик — настоящий RigidBody3D с настоящими гранями и цифрами на них.
## Значение НЕ задаётся заранее: после остановки читается та грань, что легла
## вверх (у d4 — нижняя, как на настоящем четырёхграннике). Честность проверена
## тестом tools/TestDice.tscn — 2400 бросков, хи-квадрат втрое ниже порога.
##
## Сила броска берётся из того, как быстро игрок дёрнул мышью перед отпусканием.

signal die_thrown(die: Die, value: int)
signal drag_cancelled(die: Die)

const DRAG_PLANE_Y := 1.55
const SETTLE_FRAMES := 170       ## потолок ожидания: ~2.8 с при 60 тиках
const MIN_TUMBLE_FRAMES := 26    ## кубик должен успеть перевернуться несколько раз
const MAX_THROW := 5.2
const FOLLOW_SPEED := 16.0       ## как быстро кубик догоняет курсор
const NUDGE_FRAMES := 90         ## ожидание после подталкивания кубика на ребре
const HOLD_SPIN := 7.5           ## скорость вращения в руке, рад/с
const MIN_SPIN_OUT := 7.0        ## обязательный кувырок при отпускании
const MIN_THROW := 1.6           ## обязательная дальность броска

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _bodies: Dictionary = {}          # die.id -> RigidBody3D

var _drag_die: Die = null
var _drag_body: RigidBody3D = null
var _drag_target: Vector3 = Vector3.ZERO
var _drag_basis: Basis = Basis.IDENTITY
var _spin: float = 0.0
var _trail: Array = []                # последние позиции КУБИКА в мире
var _busy: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process_input(false)
	set_physics_process(false)
	_build()
	resized.connect(_sync_viewport)

func _build() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640, 300)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.physics_object_picking = false
	container.add_child(_viewport)

	_world = Node3D.new()
	_viewport.add_child(_world)

	_camera = Camera3D.new()
	# Камера смотрит почти сверху. При виде сбоку на многограннике крупнее всех
	# читается грань, повёрнутая к игроку, а вовсе не та, что легла вверх, —
	# и человек уверенно видит одно число, а игра засчитывает другое. Сверху
	# верхняя грань самая большая, и расхождение исчезает.
	_camera.look_at_from_position(Vector3(0, 10.4, 2.8), Vector3(0, 0.0, -0.4), Vector3.UP)
	_camera.fov = 42
	_world.add_child(_camera)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-56, -32, 0)
	key.light_energy = 1.25
	key.light_color = Color("fff2dc")
	key.shadow_enabled = true
	_world.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16, 138, 0)
	fill.light_energy = 0.32
	fill.light_color = Color("c8a878")
	_world.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("4a3a28")
	e.ambient_light_energy = 0.25
	env.environment = e
	_world.add_child(env)

	# стены выше пола и заметно выше кубика: улететь за борт нельзя
	_add_static_box(Vector3(0, -0.2, 0), Vector3(26.0, 0.4, 12.0), true)
	# стены стоят по краю сукна: кубик не должен укатиться на голое дерево
	_add_static_box(Vector3(0, 2.2, -2.2), Vector3(10.0, 4.8, 0.3), false)
	_add_static_box(Vector3(0, 2.2, 2.2), Vector3(10.0, 4.8, 0.3), false)
	_add_static_box(Vector3(-4.6, 2.2, 0), Vector3(0.3, 4.8, 4.7), false)
	_add_static_box(Vector3(4.6, 2.2, 0), Vector3(0.3, 4.8, 4.7), false)

## Доска с овалом сукна. Считается кодом, чтобы не таскать картинку:
## по краям — цвет задника, к центру — тёмно-зелёное сукно с мягкой каймой.
## Сукно: овал на прозрачной подложке.
##
## Вокруг овала пиксели прозрачные, и сквозь них виден общий задник — тот же
## камень и та же виньетка, что на всём экране. Если залить их «похожим»
## деревом, на границе лотка появляется еле заметный прямоугольный шов, и
## поле снова начинает читаться как отдельная плита.
func _felt_texture() -> ImageTexture:
	var w := 416
	var h := 192
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var felt := Color("29301f")          # сукно чуть зеленее и заметно темнее доски
	var thread := Palette.BRASS_DIM      # латунная нить по краю
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for y in h:
		for x in w:
			# нормированное расстояние до центра в координатах эллипса
			var nx := (float(x) / float(w) - 0.5) * 2.0 / 0.40
			var ny := (float(y) / float(h) - 0.5) * 2.0 / 0.44
			var d := sqrt(nx * nx + ny * ny)
			var c := felt
			var a := 1.0
			if d > 1.0:
				if d < 1.016:
					c = thread            # нить тонкая: именно она читается как «сукно постелено»
				elif d < 1.055:
					# кромка под цвет стола: с вырезом растушевать нельзя,
					# поэтому переход прячем в тёмную полосу
					var t: float = (d - 1.016) / 0.039
					c = thread.darkened(0.35).lerp(Color("140f0b"), t)
				else:
					a = 0.0
			var n := rng.randf_range(-0.014, 0.014)
			img.set_pixel(x, y, Color(c.r + n, c.g + n, c.b + n, a))
	return ImageTexture.create_from_image(img)

func _sync_viewport() -> void:
	if _viewport and size.x > 8 and size.y > 8:
		_viewport.size = Vector2i(size)

func _add_static_box(pos: Vector3, box_size: Vector3, visible_floor: bool) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	cs.shape = shape
	body.add_child(cs)
	if visible_floor:
		# Плоскость, а не коробка: у BoxMesh развёртка раскладывает шесть
		# граней по одной текстуре, и нарисованный овал попадал на верх куском
		# из угла. У PlaneMesh развёртка честная — весь рисунок ложится на пол.
		var mi := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(box_size.x, box_size.z)
		mi.mesh = mesh
		mi.position = Vector3(0, box_size.y * 0.5 + 0.001, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _felt_texture()
		mat.roughness = 1.0
		# Вырез по альфе, а НЕ смешивание.
		#
		# Со смешиванием сукно попадает в прозрачный проход, который рисуется
		# после непрозрачных тел и не пишет глубину, — и кубик оказывался
		# закрашен сукном поверх, будто провалился в стол. Вырез рисует сукно
		# в обычном проходе: глубина работает, кубик лежит НА сукне.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mi.material_override = mat
		body.add_child(mi)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.26
	body.physics_material_override = pm
	body.position = pos
	_world.add_child(body)

# ─────────────────────────────────────────── кубик как объект

func _make_body(die: Die) -> RigidBody3D:
	var body := RigidBody3D.new()
	var tint := Palette.element_color(die.element)
	var radius := Polyhedra.DIE_RADIUS

	var mi := MeshInstance3D.new()
	mi.mesh = Polyhedra.build_mesh(die.sides, radius)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint.darkened(0.15)
	mat.roughness = 0.32
	mat.metallic = 0.3
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.3
	mi.material_override = mat
	body.add_child(mi)

	# цифры прямо на гранях — чтобы результат читался с кубика, а не рядом с ним
	var numbers := Polyhedra.face_numbers(die.sides)
	var centers := Polyhedra.face_centers(die.sides, radius)
	var labels: Array = []
	for i in centers.size():
		var lbl := Label3D.new()
		lbl.text = str(numbers[i])
		lbl.font_size = 96
		# чем больше граней, тем меньше каждая: у d20 цифры прежнего размера
		# налезали друг на друга и превращались в кашу
		lbl.pixel_size = 0.0042 * clampf(sqrt(8.0 / float(die.sides)), 0.55, 1.15)
		lbl.modulate = Color("fff0d8")
		lbl.outline_size = 18
		lbl.outline_modulate = Color(0, 0, 0, 0.85)
		lbl.no_depth_test = false
		lbl.double_sided = false
		lbl.position = centers[i].center + centers[i].normal * 0.012
		body.add_child(lbl)
		var target: Vector3 = lbl.position - centers[i].normal
		var up := Vector3.UP
		if absf(centers[i].normal.dot(Vector3.UP)) > 0.95:
			up = Vector3.FORWARD
		lbl.look_at_from_position(lbl.position, target, up)
		labels.append(lbl)
	body.set_meta("labels", labels)
	var cs := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = Polyhedra.collision_points(die.sides, radius)
	cs.shape = hull
	body.add_child(cs)

	var pm := PhysicsMaterial.new()
	pm.friction = 0.62
	pm.bounce = 0.22
	body.physics_material_override = pm
	body.mass = 0.6
	body.continuous_cd = true
	# затухание: без него кубик катается по сукну секунды три, и ход
	# упирается в ожидание. С ним он останавливается примерно за секунду
	body.linear_damp = 0.45
	body.angular_damp = 0.9
	return body

# ─────────────────────────────────────────── перетаскивание

func is_busy() -> bool:
	return _busy or _drag_die != null

## Игрок взял кубик из мешочка — он появляется в лотке и висит на курсоре.
func grab(die: Die, screen_pos: Vector2) -> void:
	if _busy or _drag_die != null:
		return
	_drag_die = die
	_drag_body = _make_body(die)
	_drag_body.freeze = true
	_drag_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_drag_body.position = _plane_point(screen_pos)
	_drag_target = _drag_body.position
	var orient_rng := RandomNumberGenerator.new()
	orient_rng.randomize()
	# стартовый разворот — равномерный по SO(3). Именно он, а не сила броска,
	# отвечает за честность: см. Polyhedra.random_orientation
	_drag_basis = Polyhedra.random_orientation(orient_rng)
	_drag_body.basis = _drag_basis
	_spin = 0.0
	_world.add_child(_drag_body)
	_trail = [{"p": _drag_body.position, "t": Time.get_ticks_msec() / 1000.0}]
	set_process_input(true)
	set_physics_process(true)

## Бросок без перетаскивания: кубик появляется у края лотка и сразу летит.
##
## Тащить каждый кубик рукой красиво ровно первые полчаса. Дальше это
## становится работой — на это и пожаловались после плейтеста. Ручной бросок
## остаётся для тех, кому он нравится, а клик делает то же самое: те же
## случайный разворот и порог кувырка, то есть та же честность.
func toss(die: Die) -> void:
	if _busy or _drag_die != null:
		return
	var body := _make_body(die)
	var orient_rng := RandomNumberGenerator.new()
	orient_rng.randomize()
	body.basis = Polyhedra.random_orientation(orient_rng)
	body.position = Vector3(randf_range(-4.0, -3.2), randf_range(2.0, 2.4), randf_range(-0.7, 0.7))
	body.freeze = false
	_world.add_child(body)
	_bodies[die.id] = body
	var velocity := Vector3(randf_range(3.4, 5.0), 0.0, randf_range(-1.3, 1.3))
	body.apply_impulse(velocity * 0.5 + Vector3(0, -0.35, 0))
	var roll_axis := Vector3(-velocity.z, 0.0, velocity.x) * 0.55
	var torque := roll_axis + Vector3(
		randf_range(-1.1, 1.1), randf_range(-1.6, 1.6), randf_range(-1.1, 1.1))
	if torque.length() < MIN_SPIN_OUT:
		var extra := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		torque = (torque + extra * MIN_SPIN_OUT).limit_length(MIN_SPIN_OUT * 1.6)
	body.apply_torque_impulse(torque)
	_busy = true
	_settle_and_read(die, body)

func _input(event: InputEvent) -> void:
	if _drag_die == null:
		return
	if event is InputEventMouseMotion:
		# мышь только задаёт цель. Раньше кубик телепортировался на каждое
		# событие мыши, и при 144 Гц это выглядело как дёрганье: физика-то
		# идёт 60 раз в секунду. Теперь он догоняет цель в физическом такте.
		_drag_target = _plane_point(get_local_mouse_position())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_drag()
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_drag()
		accept_event()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_release()

## Кубик догоняет курсор и ровно крутится вокруг одной оси.
## След пишется по фактическому положению кубика, а не курсора: бросок должен
## получиться такой, каким игрок его видел, а не каким дёрнул мышью.
func _physics_process(delta: float) -> void:
	if _drag_body == null or not is_instance_valid(_drag_body):
		set_physics_process(false)
		return
	var follow: float = 1.0 - pow(0.5, delta * FOLLOW_SPEED * 0.5)
	_drag_body.position = _drag_body.position.lerp(_drag_target, follow)
	# Кубик в руке крутится быстро и вокруг уплывающей оси. Раньше он вращался
	# медленно вокруг постоянной оси — грани шли предсказуемым кругом, и можно
	# было дождаться нужной цифры и аккуратно «положить» кубик на неё.
	# Теперь выцелить грань нельзя: ось уходит, а скорость такая, что за кадр
	# кубик проворачивается почти на четверть оборота.
	_spin += delta
	var axis := Vector3(
		sin(_spin * 0.9) * 0.6 + 0.35,
		1.0,
		cos(_spin * 0.7) * 0.6 + 0.2).normalized()
	_drag_body.basis = _drag_basis * Basis(axis, _spin * HOLD_SPIN)
	_trail.append({"p": _drag_body.position, "t": Time.get_ticks_msec() / 1000.0})
	if _trail.size() > 6:
		_trail.pop_front()

## Передумал — кубик возвращается в мешочек нетронутым.
## Правая кнопка, Esc или отпускание далеко за пределами лотка.
func cancel_drag() -> void:
	if _drag_die == null:
		return
	set_process_input(false)
	set_physics_process(false)
	var die := _drag_die
	_drag_die = null
	if is_instance_valid(_drag_body):
		_drag_body.queue_free()
	_drag_body = null
	drag_cancelled.emit(die)

func _release() -> void:
	set_process_input(false)
	set_physics_process(false)
	var die := _drag_die
	var body := _drag_body
	_drag_die = null
	_drag_body = null
	if body == null:
		return

	# Отпустил у самого лотка или просто ткнул — кубик летит на стол, замах
	# задаём сами: работают оба способа, и «размахнуться мышью», и «щёлкнуть».
	# А вот утащил далеко в сторону — значит, передумал.
	var rect := get_global_rect().grow(90.0)
	if not rect.has_point(get_global_mouse_position()):
		body.queue_free()
		_bodies.erase(die.id)
		drag_cancelled.emit(die)
		return
	var velocity := _swipe_velocity()
	if not get_global_rect().has_point(get_global_mouse_position()):
		body.position = Vector3(randf_range(-4.0, -3.2), 2.1, randf_range(-0.6, 0.6))
		velocity = Vector3(randf_range(3.4, 4.8), 0, randf_range(-1.0, 1.0))
	body.freeze = false
	_bodies[die.id] = body
	# нижний порог броска: совсем положить кубик на стол нельзя, он всегда
	# отправляется в полёт хотя бы немного
	if velocity.length() < MIN_THROW:
		velocity = (velocity + Vector3(randf_range(-0.7, 0.7), 0, -1.0)).normalized() * MIN_THROW
	body.apply_impulse(velocity * 0.5 + Vector3(0, -0.35, 0))
	# кувырок берётся из направления броска: кубик катится туда, куда его
	# кинули. Раньше торк был чистой случайностью в ±5 — кубик закручивался
	# одинаково бешено что от лёгкого касания, что от размаха, и бросок
	# переставал ощущаться как свой.
	var roll_axis := Vector3(-velocity.z, 0.0, velocity.x) * 0.55
	var torque := roll_axis + Vector3(
		randf_range(-1.1, 1.1), randf_range(-1.6, 1.6), randf_range(-1.1, 1.1))
	# и нижний порог кувырка: как бы бережно игрок ни отпустил, кубик обязан
	# несколько раз перевернуться. Иначе он ложится той гранью, что была сверху
	if torque.length() < MIN_SPIN_OUT:
		var extra := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		torque = (torque + extra * MIN_SPIN_OUT).limit_length(MIN_SPIN_OUT * 1.6)
	body.apply_torque_impulse(torque)
	_busy = true
	_settle_and_read(die, body)

## Скорость взмаха мышью перед отпусканием — она и задаёт силу броска.
func _swipe_velocity() -> Vector3:
	if _trail.size() < 2:
		return Vector3(randf_range(-1.0, 1.0), 0, -1.4)
	var last: Dictionary = _trail[-1]
	var first: Dictionary = _trail[0]
	var dt: float = maxf(0.016, float(last.t) - float(first.t))
	var v: Vector3 = (last.p - first.p) / dt
	if v.length() < 1.0:
		# игрок просто отпустил кубик — лёгкий подкид, чтобы он всё же покатился
		v = Vector3(randf_range(-1.0, 1.0), 0, -1.6)
	return v.limit_length(MAX_THROW)

func _settle_and_read(die: Die, body: RigidBody3D) -> void:
	var calm := 0
	var frames := 0
	while frames < SETTLE_FRAMES:
		await get_tree().physics_frame
		frames += 1
		if not is_instance_valid(body):
			_busy = false
			return
		if frames < MIN_TUMBLE_FRAMES:
			continue
		if body.linear_velocity.length() < 0.14 and body.angular_velocity.length() < 0.55:
			calm += 1
			if calm > 7:
				break
		else:
			calm = 0

	var read := Polyhedra.read_face(die.sides, body.global_transform.basis)
	var tries := 0
	while read.alignment < 0.75 and tries < 2 and is_instance_valid(body):
		# кубик встал на ребро — подталкиваем, как это делают за столом
		tries += 1
		body.apply_impulse(Vector3(randf_range(-1.0, 1.0), 1.5, randf_range(-1.0, 1.0)))
		body.apply_torque_impulse(Vector3(randf_range(-1.4, 1.4), randf_range(-1.4, 1.4), randf_range(-1.4, 1.4)))
		calm = 0
		frames = 0
		while frames < NUDGE_FRAMES:
			await get_tree().physics_frame
			frames += 1
			if not is_instance_valid(body):
				_busy = false
				return
			if body.linear_velocity.length() < 0.14 and body.angular_velocity.length() < 0.55:
				calm += 1
				if calm > 7:
					break
			else:
				calm = 0
		read = Polyhedra.read_face(die.sides, body.global_transform.basis)

	_show_result(body, int(read.get("index", -1)))
	_busy = false
	die_thrown.emit(die, int(read.value))

## Показать, какую именно грань засчитали.
##
## На многограннике игрок видит сразу несколько чисел и не обязан угадывать,
## какое из них «верхнее». Поэтому остальные гасим, а засчитанное разгораем
## и слегка увеличиваем — спорить становится не с чем.
func _show_result(body: RigidBody3D, index: int) -> void:
	if not is_instance_valid(body) or index < 0:
		return
	var labels = body.get_meta("labels", [])
	for i in labels.size():
		var lbl: Label3D = labels[i]
		if not is_instance_valid(lbl):
			continue
		if i == index:
			lbl.modulate = Palette.CANDLE
			lbl.outline_modulate = Color(0.1, 0.05, 0.0, 0.95)
			var t := create_tween()
			t.tween_property(lbl, "scale", Vector3(1.35, 1.35, 1.35), 0.18)
			t.tween_property(lbl, "scale", Vector3(1.15, 1.15, 1.15), 0.12)
		else:
			lbl.modulate = Color(1, 1, 1, 0.18)

func _plane_point(local_pos: Vector2) -> Vector3:
	if _camera == null or size.x < 1:
		return Vector3(0, DRAG_PLANE_Y, 0)
	var scale_v := Vector2(_viewport.size) / size
	var vp_pos := local_pos * scale_v
	var origin := _camera.project_ray_origin(vp_pos)
	var dir := _camera.project_ray_normal(vp_pos)
	var plane := Plane(Vector3.UP, DRAG_PLANE_Y)
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return Vector3(0, DRAG_PLANE_Y, 0)
	var p: Vector3 = hit
	return Vector3(clampf(p.x, -2.4, 2.4), DRAG_PLANE_Y, clampf(p.z, -1.4, 1.4))

func clear_all() -> void:
	for id in _bodies.keys():
		var b = _bodies[id]
		if is_instance_valid(b):
			b.queue_free()
	_bodies.clear()
	if is_instance_valid(_drag_body):
		_drag_body.queue_free()
	_drag_body = null
	_drag_die = null
	_busy = false
	set_process_input(false)
