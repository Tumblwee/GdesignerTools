@tool
class_name GDGameModuleEntryRes
extends Resource

## Resource already owns the `script` property. Keep the module's script in a
## separate property so assigning a module never changes this resource's type.
@export var module_id: int = 0
@export var display_name: String = "模块"
@export var module_script: Script
@export var script_path_hint: String = ""
@export var params: Resource


func script_path() -> String:
	return module_script.resource_path if module_script != null else script_path_hint


func prepare_save() -> void:
	if module_script != null:
		script_path_hint = module_script.resource_path


func set_module_script(value: Script) -> void:
	var old_params_script: Variant = GDGameModuleMeta.read(module_script).get("params_script")
	var new_params_script: Variant = GDGameModuleMeta.read(value).get("params_script")
	module_script = value
	if value != null:
		script_path_hint = value.resource_path
	if old_params_script != new_params_script:
		params = null
		if new_params_script is Script and ClassDB.is_parent_class(new_params_script.get_instance_base_type(), "Resource") \
				and new_params_script.can_instantiate() and GDGameModuleMeta.can_construct_without_arguments(new_params_script):
			var instance: Variant = new_params_script.new()
			if instance is Resource:
				params = instance
