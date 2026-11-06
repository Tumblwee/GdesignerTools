@tool
class_name GDGameModeValidation
extends RefCounted


static func validate(config: GDGameModeConfigRes, runtime: bool = false) -> Dictionary:
	var result := {"ok": true, "errors": [], "warnings": [], "issues": []}
	if config == null:
		_issue(result, "error", "配置为空。")
		return result
	if config.schema_version != 1:
		_issue(result, "error", "不支持的配置版本：%d。" % config.schema_version)
	if config.states.is_empty():
		_issue(result, "error", "配置至少需要一个状态。")
	var keys: Dictionary = {}
	var ids: Dictionary = {}
	var scripts: Dictionary = {}
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9_]+$")
	for state in config.states:
		if state == null:
			_issue(result, "error", "状态引用为空。")
			continue
		var key := String(state.key)
		if pattern.search(key) == null:
			_issue(result, "error", "状态 Key '%s' 只允许非空的 [a-z0-9_]。" % key, key)
		if keys.has(key):
			_issue(result, "error", "状态 Key 重复：%s。" % key, key)
		keys[key] = true
		if state.modules.is_empty():
			_issue(result, "warning", "状态 %s 没有模块（允许）。" % key, key)
		_validate_modules(state.modules, key, runtime, ids, scripts, result)
	if not keys.has(String(config.default_state_key)):
		_issue(result, "error", "默认状态不存在：%s。" % config.default_state_key)
	_validate_modules(config.global_modules, "global", runtime, ids, scripts, result)
	return result


static func _validate_modules(entries: Array[GDGameModuleEntryRes], scope: String, runtime: bool,
		ids: Dictionary, scripts: Dictionary, result: Dictionary) -> void:
	for entry in entries:
		if entry == null:
			_issue(result, "error", "模块条目为空。", scope)
			continue
		var id := entry.module_id
		if id < 1:
			_issue(result, "error", "模块 ID 必须为正整数：%d。" % id, scope, id)
		if ids.has(id):
			_issue(result, "error", "模块 ID 重复：%d。" % id, scope, id)
		ids[id] = true
		var script := entry.module_script
		if script == null:
			_issue(result, "error", "模块 #%d 脚本缺失或加载失败：%s。" % [id, entry.script_path_hint], scope, id)
			continue
		var meta := GDGameModuleMeta.read(script)
		if not meta.is_module:
			_issue(result, "error", "模块 #%d 脚本必须继承 GameModuleBase。" % id, scope, id)
		elif not GDGameModuleMeta.can_construct_without_arguments(script):
			_issue(result, "error", "模块 #%d 的 _init 必须允许无参数调用，请为构造参数提供默认值。" % id, scope, id)
		if runtime and not script.can_instantiate():
			_issue(result, "error", "模块 #%d 脚本不能实例化：%s。" % [id, script.resource_path], scope, id)
		if not meta.category is int or meta.category not in GDCoreTypes.ModuleCategory.values():
			_issue(result, "error", "模块 #%d MODULE_CATEGORY 不是合法枚举。" % id, scope, id)
		elif not meta.category_declared:
			_issue(result, "warning", "模块 #%d 未声明 MODULE_CATEGORY，按 MISC 处理。" % id, scope, id)
		if not meta.tick_enabled is bool or not meta.debug_restartable is bool:
			_issue(result, "error", "模块 #%d TICK_ENABLED / DEBUG_RESTARTABLE 必须为 bool。" % id, scope, id)
		if scripts.has(script):
			_issue(result, "warning", "脚本 %s 使用多次，注意服务键冲突。" % script.resource_path, scope, id)
		scripts[script] = true
		var params_script: Variant = meta.params_script
		if meta.params_declared:
			if not params_script is Script or not ClassDB.is_parent_class(params_script.get_instance_base_type(), "Resource"):
				_issue(result, "error", "模块 #%d PARAMS_SCRIPT 必须是 Resource 脚本。" % id, scope, id)
			else:
				if not GDGameModuleMeta.can_construct_without_arguments(params_script):
					_issue(result, "error", "模块 #%d 参数脚本的 _init 必须允许无参数调用。" % id, scope, id)
				if not params_script.is_tool():
					_issue(result, "warning", "模块 #%d 参数脚本没有 @tool，编辑器中只读。" % id, scope, id)
				if entry.params == null or not GDGameModuleMeta.inherits_script(entry.params.get_script(), params_script):
					_issue(result, "error", "模块 #%d 参数为空或类型与 PARAMS_SCRIPT 不符。" % id, scope, id)
		elif entry.params != null:
			_issue(result, "error", "模块 #%d 未声明 PARAMS_SCRIPT，却配置了参数。" % id, scope, id)


static func _issue(result: Dictionary, severity: String, message: String, state_key: String = "", module_id: int = -1) -> void:
	result["errors" if severity == "error" else "warnings"].append(message)
	result.issues.append({"severity": severity, "message": message, "state_key": state_key, "module_id": module_id})
	if severity == "error":
		result.ok = false


static func preflight_dependencies(path: String) -> Array[String]:
	var missing: Array[String] = []
	_check_dependencies(path, {}, missing)
	return missing


static func _check_dependencies(path: String, visited: Dictionary, missing: Array[String]) -> void:
	if visited.has(path):
		return
	visited[path] = true
	var resolved := path
	if path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(uid):
			resolved = ResourceUID.get_id_path(uid)
	# ResourceLoader.exists() also reports cached resources whose files have
	# since been removed. Imported/exported assets may legitimately use remaps.
	var on_disk := FileAccess.file_exists(resolved) or FileAccess.file_exists(resolved + ".remap") or FileAccess.file_exists(resolved + ".import")
	if path.is_empty() or not on_disk or not ResourceLoader.exists(path):
		if not missing.has(path):
			missing.append(path)
		return
	for dependency in ResourceLoader.get_dependencies(path):
		var parts := String(dependency).split("::")
		var dependency_path: String = parts[parts.size() - 1]
		if parts.size() > 1 and parts[0].begins_with("uid://"):
			var uid := ResourceUID.text_to_id(parts[0])
			if ResourceUID.has_id(uid):
				dependency_path = ResourceUID.get_id_path(uid)
		_check_dependencies(dependency_path, visited, missing)


static func load_checked(path: String, runtime: bool = true) -> Dictionary:
	var missing := preflight_dependencies(path)
	if not missing.is_empty():
		return {"ok": false, "code": "missing_dependency", "message": "缺失依赖：\n" + "\n".join(missing), "config": null}
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is GDGameModeConfigRes:
		return {"ok": false, "code": "validation_failed", "message": "无法加载 GDGameModeConfigRes：%s" % path, "config": null}
	var validation := validate(resource, runtime)
	return {"ok": validation.ok, "code": "ok" if validation.ok else "validation_failed",
		"message": "\n".join(validation.errors), "config": resource, "validation": validation}
