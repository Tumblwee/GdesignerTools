@tool
class_name GDGameModuleCreatorDialog
extends ConfirmationDialog

## 生成业务模块脚本，再由页面把脚本绑定到右键选择的节点。
const DEFAULT_DIRECTORY := "res://scripts/game_mdl"
const MODULE_SOURCE := """extends GDGameFramework.GameModuleBase

const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.MISC
const TICK_ENABLED := true
const DEBUG_RESTARTABLE := false


func on_construct(_ctx: GDGameFramework.GameModeContext) -> void:
	pass


func on_begin_play(_ctx: GDGameFramework.GameModeContext) -> void:
	pass


func on_update(_dt: float) -> void:
	pass


func on_dispose() -> void:
	pass
"""

var _name_edit: LineEdit
var _path_edit: LineEdit
var _error_label: Label
var _directory := DEFAULT_DIRECTORY
var _on_created: Callable


func _init() -> void:
	title = "新建模块"
	ok_button_text = "创建"
	cancel_button_text = "取消"
	dialog_hide_on_ok = false
	min_size = Vector2i(600, 0)
	var form := GDForm.new()
	add_child(form)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "例如 LoginModule"
	_name_edit.text_changed.connect(func(_value: String) -> void: _refresh_validation())
	register_text_enter(_name_edit)
	form.row("模块名称", _name_edit)
	var location := HBoxContainer.new()
	_path_edit = LineEdit.new()
	_path_edit.editable = false
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	location.add_child(_path_edit)
	var choose := GDEditorUi.tool_button(&"Folder", "自定义代码位置", _choose_directory)
	choose.focus_mode = Control.FOCUS_ALL
	location.add_child(choose)
	form.row("代码位置", location)
	_error_label = form.note("", &"danger")
	_error_label.visible = false
	confirmed.connect(_create)
	_refresh_validation(false)


static func open(host: Node, on_created: Callable, scope_title: String = "") -> GDGameModuleCreatorDialog:
	var dialog := GDGameModuleCreatorDialog.new()
	dialog._on_created = on_created
	if not scope_title.is_empty():
		dialog.title = "新建模块 · " + scope_title
	GDDialogs._show(host, dialog)
	dialog._name_edit.grab_focus()
	return dialog


func _choose_directory() -> void:
	var picker := FileDialog.new()
	picker.title = "选择模块代码位置"
	picker.access = FileDialog.ACCESS_RESOURCES
	picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	picker.size = Vector2i(760, 520)
	var existing := _directory
	while existing != "res://" and not DirAccess.dir_exists_absolute(existing):
		existing = existing.get_base_dir()
	picker.current_dir = existing
	picker.dir_selected.connect(func(path: String) -> void:
		_directory = path
		_refresh_validation()
	)
	GDDialogs._show(self, picker)


func _refresh_validation(show_error: bool = true) -> void:
	var module_name := _name_edit.text.strip_edges()
	_path_edit.text = _directory.path_join(module_name + ".gd") if not module_name.is_empty() else _directory
	_path_edit.tooltip_text = _path_edit.text
	var message := validation_error(module_name, _directory)
	get_ok_button().disabled = not message.is_empty()
	_error_label.text = message
	_error_label.visible = show_error and not message.is_empty()


func _create() -> void:
	var result := create_script(_name_edit.text.strip_edges(), _directory)
	if not result.ok:
		_error_label.text = result.error
		_error_label.visible = true
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_on_created.call(result.script)
	hide()


static func validation_error(module_name: String, directory: String) -> String:
	if module_name.is_empty():
		return "请输入模块名称。"
	if module_name != module_name.validate_filename() or module_name in [".", ".."] or module_name.ends_with(".") or module_name.ends_with(" "):
		return "模块名称不能包含路径分隔符或文件名特殊字符。"
	if module_name.to_lower().ends_with(".gd"):
		return "模块名称不需要填写 .gd 后缀。"
	var reserved := module_name.get_slice(".", 0).to_upper()
	if reserved in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]:
		return "该名称是系统保留文件名，请换一个名称。"
	if not directory.begins_with("res://") or "\\" in directory:
		return "请选择当前项目中的代码文件夹。"
	for part in directory.trim_prefix("res://").split("/", false):
		if part in [".", ".."] or part != part.validate_filename():
			return "代码位置必须是当前项目中的有效文件夹。"
	var path := directory.path_join(module_name + ".gd")
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path) or ResourceLoader.has_cached(path):
		return "此位置已存在同名脚本，请修改名称或选择其他位置。"
	return ""


static func create_script(module_name: String, directory: String) -> Dictionary:
	var message := validation_error(module_name, directory)
	if not message.is_empty():
		return {"ok": false, "error": message}
	var script := GDScript.new()
	script.source_code = MODULE_SOURCE
	var error := script.reload()
	if error != OK:
		return {"ok": false, "error": "模块模板无法编译：" + error_string(error)}
	error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return {"ok": false, "error": "无法创建代码文件夹：" + error_string(error)}
	var path := directory.path_join(module_name + ".gd")
	error = ResourceSaver.save(script, path)
	if error != OK:
		return {"ok": false, "error": "无法保存模块脚本：" + error_string(error)}
	# GDScript 保存器不保证设置 resource_path；成功后登记路径和缓存身份。
	if script.resource_path != path:
		script.take_over_path(path)
	return {"ok": true, "script": script, "path": path}
