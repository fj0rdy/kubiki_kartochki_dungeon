extends Node
## Автозагрузка. Отдаёт иконки из assets/icons по смысловому имени.
##
## Если файла нет — возвращает null, и экран рисует значок символом, как раньше.
## Поэтому проект работает и с иконками, и без них.

const DIR := "res://assets/icons"

var _map: Dictionary = {}        # "attack" -> "crossed-swords"
var _cache: Dictionary = {}      # имя файла -> Texture2D
var _shader: Shader

func _ready() -> void:
	var raw := _load_json("res://data/icons.json")
	_map = raw.get("icons", {})
	_shader = load("res://assets/icon_tint.gdshader")

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func has(concept: String) -> bool:
	return texture(concept) != null

## Текстура по смысловому имени. null, если иконки нет — это нормально.
func texture(concept: String) -> Texture2D:
	var file_name := str(_map.get(concept, ""))
	if file_name == "":
		return null
	if _cache.has(file_name):
		return _cache[file_name]
	var tex: Texture2D = null
	for ext in [".svg", ".png"]:
		var path := "%s/%s%s" % [DIR, file_name, ext]
		if ResourceLoader.exists(path):
			tex = load(path)
			break
	_cache[file_name] = tex
	return tex

## Готовый узел с иконкой нужного цвета и размера.
## Возвращает null, если иконки нет — вызывающий сам решит, чем заменить.
func make(concept: String, px: float, color: Color) -> TextureRect:
	var tex := texture(concept)
	if tex == null:
		return null
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = Vector2(px, px)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _shader:
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("tint", color)
		rect.material = mat
	else:
		rect.modulate = color
	return rect

## Иконка для типа комнаты на карте.
func room(type_name: String) -> String:
	return "room_" + type_name
