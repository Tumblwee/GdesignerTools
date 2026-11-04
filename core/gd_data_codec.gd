@tool
class_name GDDataCodec
extends RefCounted

## Reflective codec: graph of inner-class Resources <-> plain data (Dictionary / Array / primitives).
##
## Why: Godot cannot serialize a Resource whose script is an inner class (it writes an empty GDScript
## sub_resource and reloads a bare, script-less Resource). Owners keep such objects in plain vars and persist
## them through one stored getter/setter property, so save / load / Resource.duplicate need no extra step:
##   @export_storage var codec_data: Dictionary:
##       get: return codec().encode({...})
##       set(value): ... codec().decode(value) ...
## Registered object -> {"$type": "<inner class name>", field: value...}, fields equal to the class default omitted.
## Everything else (Texture2D, PackedScene, top-level script Resources, saved files) stays native.

const TYPE_KEY := "$type"

## on_unknown.call(type_name, data) replaces an object whose "$type" is not registered.
var on_unknown: Callable = Callable()

var _script_by_name: Dictionary = {} # StringName -> GDScript
var _name_by_script: Dictionary = {} # GDScript -> StringName
var _defaults: Dictionary = {} # GDScript -> {field: encoded default}

## hosts: scripts whose inner classes (script constants) are the data classes, e.g. [GDGuideAtoms, GDGuideData].
func _init(hosts: Array) -> void:
	for host in hosts:
		var constants: Dictionary = host.get_script_constant_map()
		for type_name in constants:
			var script = constants[type_name]
			if script is GDScript and ClassDB.is_parent_class(script.get_instance_base_type(), &"Resource"):
				_script_by_name[type_name] = script
				_name_by_script[script] = type_name

func is_registered(value: Variant) -> bool:
	return value is Resource and _name_by_script.has(value.get_script()) \
		and (value.resource_path.is_empty() or value.resource_path.contains("::"))

func encode(value: Variant) -> Variant:
	if value is Array:
		return value.map(encode)
	if value is Dictionary:
		return _map_values(value, encode)
	if not is_registered(value):
		return value
	var script: GDScript = value.get_script()
	var out := {TYPE_KEY: String(_name_by_script[script])}
	var defaults := _defaults_of(script)
	for field in defaults:
		var encoded: Variant = encode(value.get(field))
		if typeof(encoded) != typeof(defaults[field]) or encoded != defaults[field]:
			out[field] = encoded
	return out

func decode(data: Variant) -> Variant:
	if data is Array:
		return data.map(decode)
	if not data is Dictionary:
		return data
	if not data.has(TYPE_KEY):
		return _map_values(data, decode)
	var type_name := StringName(str(data[TYPE_KEY]))
	if not _script_by_name.has(type_name):
		if on_unknown.is_valid():
			return on_unknown.call(String(type_name), data)
		push_warning("GDDataCodec: unknown type '%s' dropped" % type_name)
		return null
	var script: GDScript = _script_by_name[type_name]
	var obj: Resource = script.new()
	var fields := _defaults_of(script)
	for field in data:
		if not fields.has(field):
			continue # unknown field (renamed / removed): ignored
		var value: Variant = decode(data[field])
		var current: Variant = obj.get(field)
		if (current is Array or current is Dictionary) and typeof(current) == typeof(value):
			current.assign(value) # keeps the element type of typed collections
		else:
			obj.set(field, value)
	return obj

## Stored script fields of a class with their encoded default values (cached; one fresh instance per class).
func _defaults_of(script: GDScript) -> Dictionary:
	if not _defaults.has(script):
		var fresh: Object = script.new()
		var fields := {}
		for prop in fresh.get_property_list():
			if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and prop["usage"] & PROPERTY_USAGE_STORAGE:
				fields[prop["name"]] = null
		_defaults[script] = fields # cached before encoding so self-referencing defaults terminate
		for field in fields:
			fields[field] = encode(fresh.get(field))
	return _defaults[script]

static func _map_values(dict: Dictionary, fn: Callable) -> Dictionary:
	var out := {}
	for key in dict:
		out[key] = fn.call(dict[key])
	return out
