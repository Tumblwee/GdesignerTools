@tool
class_name GDGameModuleMeta
extends RefCounted


static func read(script: Script) -> Dictionary:
	var constants: Dictionary = {}
	var cursor := script
	while cursor != null:
		for key in cursor.get_script_constant_map():
			if not constants.has(key):
				constants[key] = cursor.get_script_constant_map()[key]
		cursor = cursor.get_base_script()
	return {
		"category": constants.get("MODULE_CATEGORY", GDCoreTypes.ModuleCategory.MISC),
		"category_declared": constants.has("MODULE_CATEGORY"),
		"params_script": constants.get("PARAMS_SCRIPT", null),
		"params_declared": constants.has("PARAMS_SCRIPT"),
		"tick_enabled": constants.get("TICK_ENABLED", true),
		"debug_restartable": constants.get("DEBUG_RESTARTABLE", false),
		"is_module": inherits_script(script, GDGameFramework.GameModuleBase),
		"valid_module": inherits_script(script, GDGameFramework.GameModuleBase),
	}


static func inherits_script(script: Script, expected: Script) -> bool:
	if script == null or expected == null:
		return false
	var cursor := script
	while cursor != null:
		if cursor == expected:
			return true
		cursor = cursor.get_base_script()
	return false


## 模块工厂以无参 new() 创建实例；只检查最近的构造函数，不能执行业务代码来探测。
static func can_construct_without_arguments(script: Script) -> bool:
	if script == null:
		return false
	for method: Dictionary in script.get_script_method_list():
		if str(method.get("name", "")) == "_init":
			return method.get("args", []).size() <= method.get("default_args", []).size()
	return true
