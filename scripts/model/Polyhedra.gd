class_name Polyhedra
extends RefCounted
## Строит настоящие многогранники для кубиков: тетраэдр, куб, октаэдр,
## пентагональную бипирамиду (d10), додекаэдр и икосаэдр.
##
## Грани не прописаны вручную — они находятся из вершин перебором троек:
## тройка задаёт грань, если все остальные вершины лежат по одну сторону
## от её плоскости. Для 20 вершин это меньше секунды и работает для любого
## выпуклого тела, так что новый тип кубика достаточно задать точками.

## Размер кубика — одно число на игру и на проверку честности. Если они
## разойдутся, тест начнёт проверять физику, в которую никто не играет.
const DIE_RADIUS := 0.78

const PHI := 1.6180339887

static var _shapes: Dictionary = {}
static var _shapes_loaded: bool = false

## Формы берутся из data/dice_shapes.json, если он есть, иначе — из таблиц ниже.
## В JSON лежат вершины моделей из бесплатного пака: у настоящего d10 форма
## пентагонального трапецоэдра, которую вручную не задать в две строки.
static func vertices(sides: int) -> PackedVector3Array:
	if not _shapes_loaded:
		_shapes_loaded = true
		var path := "res://data/dice_shapes.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				_shapes = parsed.get("shapes", {})
	if _shapes.has(str(sides)):
		var out := PackedVector3Array()
		for v in _shapes[str(sides)]:
			out.append(Vector3(float(v[0]), float(v[1]), float(v[2])))
		return out
	return _builtin_vertices(sides)

static func _builtin_vertices(sides: int) -> PackedVector3Array:
	match sides:
		4:
			return PackedVector3Array([
				Vector3(1, 1, 1), Vector3(1, -1, -1),
				Vector3(-1, 1, -1), Vector3(-1, -1, 1),
			])
		6:
			var cube := PackedVector3Array()
			for x in [-1.0, 1.0]:
				for y in [-1.0, 1.0]:
					for z in [-1.0, 1.0]:
						cube.append(Vector3(x, y, z))
			return cube
		8:
			return PackedVector3Array([
				Vector3(1, 0, 0), Vector3(-1, 0, 0),
				Vector3(0, 1, 0), Vector3(0, -1, 0),
				Vector3(0, 0, 1), Vector3(0, 0, -1),
			])
		10:
			# пентагональная бипирамида: два острия и пятиугольник по экватору
			var bip := PackedVector3Array([Vector3(0, 1.35, 0), Vector3(0, -1.35, 0)])
			for i in 5:
				var a := TAU * i / 5.0
				bip.append(Vector3(cos(a), 0, sin(a)))
			return bip
		12:
			var dod := PackedVector3Array()
			for x in [-1.0, 1.0]:
				for y in [-1.0, 1.0]:
					for z in [-1.0, 1.0]:
						dod.append(Vector3(x, y, z))
			for s1 in [-1.0, 1.0]:
				for s2 in [-1.0, 1.0]:
					dod.append(Vector3(0, s1 / PHI, s2 * PHI))
					dod.append(Vector3(s1 / PHI, s2 * PHI, 0))
					dod.append(Vector3(s1 * PHI, 0, s2 / PHI))
			return dod
		_:
			var ico := PackedVector3Array()
			for s1 in [-1.0, 1.0]:
				for s2 in [-1.0, 1.0]:
					ico.append(Vector3(0, s1, s2 * PHI))
					ico.append(Vector3(s1, s2 * PHI, 0))
					ico.append(Vector3(s1 * PHI, 0, s2))
			return ico

## Грани выпуклой оболочки: массив словарей {normal, vertices (по кругу)}.
##
## Тройка вершин задаёт грань, если все остальные точки лежат по одну сторону
## от её плоскости. Нормаль разворачивается наружу (от центра тела) — иначе
## половина граней теряется из-за случайного порядка вершин в тройке.
static func faces(points: PackedVector3Array) -> Array:
	var eps := 0.0008
	var n := points.size()
	if n < 4:
		return []

	var centroid := Vector3.ZERO
	for p in points:
		centroid += p
	centroid /= float(n)

	var planes: Array = []   # [{normal, d}]
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var a := points[i]
				var normal := (points[j] - a).cross(points[k] - a)
				if normal.length() < eps:
					continue
				normal = normal.normalized()
				var d := normal.dot(a)
				# развернуть наружу: центр тела должен остаться позади плоскости
				if normal.dot(centroid) > d:
					normal = -normal
					d = -d
				var is_face := true
				for m in n:
					if normal.dot(points[m]) > d + eps:
						is_face = false
						break
				if not is_face:
					continue
				var known := false
				for pl in planes:
					if pl.normal.dot(normal) > 0.999 and absf(pl.d - d) < 1e-3:
						known = true
						break
				if not known:
					planes.append({"normal": normal, "d": d})

	var result: Array = []
	for plane in planes:
		var on_plane: Array = []
		for m in n:
			if absf(plane.normal.dot(points[m]) - plane.d) < eps:
				on_plane.append(points[m])
		if on_plane.size() < 3:
			continue
		result.append({
			"normal": plane.normal,
			"vertices": _sort_around(on_plane, plane.normal),
		})
	return result

## Упорядочить вершины грани по кругу — иначе треугольники выйдут внахлёст.
static func _sort_around(verts: Array, normal: Vector3) -> Array:
	var center := Vector3.ZERO
	for v in verts:
		center += v
	center /= float(verts.size())
	var axis_u: Vector3 = (verts[0] - center).normalized()
	var axis_v := normal.cross(axis_u).normalized()
	var with_angle: Array = []
	for v in verts:
		var offset: Vector3 = v - center
		with_angle.append({"v": v, "a": atan2(offset.dot(axis_v), offset.dot(axis_u))})
	with_angle.sort_custom(func(x, y): return x.a < y.a)
	var out: Array = []
	for entry in with_angle:
		out.append(entry.v)
	return out

## Меш с плоскими нормалями — грани читаются как грани, а не как шар.
static func build_mesh(sides: int, radius: float = 0.5) -> ArrayMesh:
	var points := vertices(sides)
	var scale_factor := 0.0
	for p in points:
		scale_factor = maxf(scale_factor, p.length())
	var norm := radius / maxf(scale_factor, 0.0001)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces(points):
		var fverts: Array = face.vertices
		st.set_normal(face.normal)
		for t in range(1, fverts.size() - 1):
			for v in [fverts[0], fverts[t], fverts[t + 1]]:
				st.set_normal(face.normal)
				st.add_vertex(v * norm)
	st.index()
	return st.commit()

## Точки для коллизии — тот же набор вершин, отмасштабированный.
static func collision_points(sides: int, radius: float = 0.5) -> PackedVector3Array:
	var points := vertices(sides)
	var scale_factor := 0.0
	for p in points:
		scale_factor = maxf(scale_factor, p.length())
	var norm := radius / maxf(scale_factor, 0.0001)
	var out := PackedVector3Array()
	for p in points:
		out.append(p * norm)
	return out

## ── Нумерация граней и чтение выпавшего значения ──────────────────
##
## Чтобы бросок был настоящим, число должно читаться с той грани, что легла
## вверх, а не назначаться заранее. Для этого граням нужны номера.

## Номера граней в том же порядке, что и faces(). У тел с центральной
## симметрией противоположные грани дают в сумме sides+1 — как на настоящем
## кубике. У тетраэдра и бипирамиды таких пар нет, там номера идут подряд.
static func face_numbers(sides: int) -> Array:
	var f := faces(vertices(sides))
	var n := f.size()
	var numbers: Array = []
	numbers.resize(n)
	numbers.fill(0)

	var next := 1
	for i in n:
		if numbers[i] != 0:
			continue
		# ищем противоположную грань
		var opposite := -1
		for j in range(i + 1, n):
			if numbers[j] == 0 and f[i].normal.dot(f[j].normal) < -0.985:
				opposite = j
				break
		numbers[i] = next
		if opposite >= 0:
			numbers[opposite] = n + 1 - next
		next += 1
		while next <= n and numbers.has(next):
			next += 1
	# подстраховка: если что-то осталось нулём, дозаполняем
	var used := {}
	for v in numbers:
		if v > 0:
			used[v] = true
	var free_numbers: Array = []
	for v in range(1, n + 1):
		if not used.has(v):
			free_numbers.append(v)
	for i in n:
		if numbers[i] == 0:
			numbers[i] = free_numbers.pop_front()
	return numbers

## Центры граней — туда вешаются цифры.
static func face_centers(sides: int, radius: float = 0.5) -> Array:
	var points := vertices(sides)
	var scale_factor := 0.0
	for p in points:
		scale_factor = maxf(scale_factor, p.length())
	var norm := radius / maxf(scale_factor, 0.0001)
	var out: Array = []
	for face in faces(points):
		var c := Vector3.ZERO
		for v in face.vertices:
			c += v
		c /= float(face.vertices.size())
		out.append({"center": c * norm, "normal": face.normal})
	return out

## Какая грань смотрит вверх после остановки.
## Возвращает {value, alignment, index}: alignment близко к 1 — кубик лёг ровно,
## меньше 0.75 — встал на ребро, бросок надо перекатить.
##
## У тетраэдра верхней грани нет (сверху всегда вершина), поэтому читаем нижнюю —
## так же, как читают настоящий d4.
static func read_face(sides: int, basis: Basis) -> Dictionary:
	var target := Vector3.DOWN if sides == 4 else Vector3.UP
	var f := faces(vertices(sides))
	var numbers := face_numbers(sides)
	var best := -2.0
	var best_index := 0
	for i in f.size():
		var world_normal: Vector3 = (basis * f[i].normal).normalized()
		var d := world_normal.dot(target)
		if d > best:
			best = d
			best_index = i
	return {"value": int(numbers[best_index]), "alignment": best, "index": best_index}

## Равномерно случайный разворот в пространстве.
##
## Три случайных угла Эйлера — НЕ равномерное распределение по ориентациям:
## они сгущаются у полюсов. У многогранного кубика это размывается кувырком,
## а у d4, который почти не катится, перекос доживает до результата и портит
## распределение. Здесь используется метод Шумейка — случайный кватернион,
## равномерный по SO(3).
static func random_orientation(rng: RandomNumberGenerator) -> Basis:
	var u1 := rng.randf()
	var u2 := rng.randf()
	var u3 := rng.randf()
	var a := sqrt(1.0 - u1)
	var b := sqrt(u1)
	return Basis(Quaternion(
		a * sin(TAU * u2),
		a * cos(TAU * u2),
		b * sin(TAU * u3),
		b * cos(TAU * u3)).normalized())
