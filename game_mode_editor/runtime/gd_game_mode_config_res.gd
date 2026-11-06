@tool
class_name GDGameModeConfigRes
extends Resource

@export var schema_version: int = 1
@export var display_name: String = "GameMode_Default"
@export var default_state_key: StringName = &"login"
@export var global_modules: Array[GDGameModuleEntryRes] = []
@export var states: Array[GDGameStateBindingRes] = []
@export var next_module_id: int = 1
@export var tick_when_paused: bool = false
@export var global_graph_position: Vector2 = Vector2(40, 40)


func allocate_module_id() -> int:
	# Also repair a stale counter from an asset edited outside this page.
	for entry in all_modules():
		if entry != null:
			next_module_id = maxi(next_module_id, entry.module_id + 1)
	var result := next_module_id
	next_module_id += 1
	return result


func all_modules() -> Array[GDGameModuleEntryRes]:
	var result: Array[GDGameModuleEntryRes] = []
	result.append_array(global_modules)
	for state in states:
		if state != null:
			result.append_array(state.modules)
	return result


func find_state(key: StringName) -> GDGameStateBindingRes:
	for state in states:
		if state != null and state.key == key:
			return state
	return null


func find_module(id: int) -> GDGameModuleEntryRes:
	for entry in all_modules():
		if entry != null and entry.module_id == id:
			return entry
	return null


func prepare_save() -> void:
	for entry in all_modules():
		if entry != null:
			entry.prepare_save()


func runtime_digest() -> String:
	var encoded_states: Array = []
	for state in states:
		encoded_states.append(null if state == null else [String(state.key), state.display_name, _encode_modules(state.modules)])
	# UI positions and the ID allocator have no effect on running instances.
	return JSON.stringify([schema_version, display_name, String(default_state_key), tick_when_paused,
		_encode_modules(global_modules), encoded_states]).sha256_text()


static func _encode_modules(entries: Array[GDGameModuleEntryRes]) -> Array:
	var result: Array = []
	for entry in entries:
		result.append(null if entry == null else [entry.module_id, entry.display_name,
			entry.script_path(), _encode_value(entry.params, [], true)])
	return result


static func _encode_value(value: Variant, ancestors: Array, inline_resource: bool = false) -> Variant:
	if value == null:
		return null
	if value is Resource:
		if value is Script:
			return ["script", value.resource_path]
		var path: String = value.resource_path
		if not inline_resource and not path.is_empty() and not path.contains("::"):
			return ["resource", path]
		var cycle := _ancestor_index(value, ancestors)
		if cycle >= 0:
			return ["cycle", cycle]
		var next: Array = ancestors.duplicate()
		next.append(value)
		var names: Array[String] = []
		for property in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE and property.name not in ["resource_path", "resource_name", "resource_local_to_scene"]:
				names.append(String(property.name))
		names.sort()
		var fields: Array = []
		for name in names:
			fields.append([name, _encode_value(value.get(name), next)])
		return ["inline", fields]
	if value is Array:
		var cycle := _ancestor_index(value, ancestors)
		if cycle >= 0:
			return ["cycle", cycle]
		var next: Array = ancestors.duplicate()
		next.append(value)
		var items: Array = []
		for item in value:
			items.append(_encode_value(item, next))
		return ["array", items]
	if value is Dictionary:
		var cycle := _ancestor_index(value, ancestors)
		if cycle >= 0:
			return ["cycle", cycle]
		var next: Array = ancestors.duplicate()
		next.append(value)
		var pairs: Array = []
		for key in value:
			pairs.append([_encode_value(key, next), _encode_value(value[key], next)])
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return JSON.stringify(a[0]) < JSON.stringify(b[0]))
		return ["dictionary", pairs]
	# Preserve types (including StringName, vectors, colors and packed arrays).
	return [typeof(value), var_to_str(value)]


static func _ancestor_index(value: Variant, ancestors: Array) -> int:
	for index in ancestors.size():
		# Array/Dictionary equality compares contents recursively. Cycle detection
		# must compare identities, including when distinct containers look alike.
		if is_same(value, ancestors[index]):
			return index
	return -1
