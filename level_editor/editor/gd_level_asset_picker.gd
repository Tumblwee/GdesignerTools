@tool
class_name GDLevelAssetPicker
extends ConfirmationDialog

## 以关卡资产为入口，不要求使用者了解资源文件所在目录。

class AssetList extends GDLibraryList:
	signal selection_changed

	func _init() -> void:
		super("关卡资产", "搜索关卡名称或路径")
		item_selected.connect(func(_key: Variant) -> void: selection_changed.emit())
		_tree.empty_clicked.connect(func(_at: Vector2, _button: int) -> void: selection_changed.emit())
		_search.text_changed.connect(func(_text: String) -> void: selection_changed.emit())

	func selected_level() -> GDLevelSceneRes:
		return _key_of(_tree.get_selected()) as GDLevelSceneRes


var _list: AssetList = null
var _on_level: Callable = Callable()


func _init() -> void:
	title = "打开关卡"
	ok_button_text = "打开"
	cancel_button_text = "取消"
	dialog_hide_on_ok = false
	min_size = Vector2i(760, 480)
	_list = AssetList.new()
	_list.set_detail_width(360)
	_list.set_empty_state(GDEditorUi.empty_state("还没有关卡资产", "请先在关卡编辑器中创建并保存关卡。"))
	_list.selection_changed.connect(func() -> void: get_ok_button().disabled = _list.selected_level() == null)
	_list.item_activated.connect(func(_key: Variant) -> void: _open_selected())
	add_child(_list)
	confirmed.connect(_open_selected)
	get_ok_button().disabled = true


static func open(host: Node, on_level: Callable) -> GDLevelAssetPicker:
	var dialog := GDLevelAssetPicker.new()
	dialog._on_level = on_level
	var rows: Array = []
	for level in scan_levels():
		rows.append({
			"key": level,
			"text": _title_of(level),
			"detail": level.resource_path,
			"tooltip": "%s\n%s" % [_title_of(level), level.resource_path],
		})
	dialog._list.set_items([{"title": "", "items": rows}])
	GDDialogs._show(host, dialog)
	if not rows.is_empty():
		dialog._list.focus_search()
	return dialog


func _open_selected() -> void:
	var level := _list.selected_level()
	if level == null:
		return
	_on_level.call(level)
	hide()


static func _title_of(level: GDLevelSceneRes) -> String:
	if not level.display_name.is_empty():
		return level.display_name
	return level.resource_name if not level.resource_name.is_empty() else level.resource_path.get_file().get_basename()


## 先检查脚本依赖，避免为列举关卡而实例化项目中的所有资源。
static func scan_levels(root: String = "res://") -> Array[GDLevelSceneRes]:
	var result: Array[GDLevelSceneRes] = []
	var script_paths := {"res://addons/gdesigner_tools/level_editor/runtime/gd_level_scene_res.gd": true}
	var classes := {"GDLevelSceneRes": true}
	var global_classes := ProjectSettings.get_global_class_list()
	var added := true
	while added:
		added = false
		for entry: Dictionary in global_classes:
			if classes.has(str(entry["base"])) and not classes.has(str(entry["class"])):
				classes[str(entry["class"])] = true
				script_paths[str(entry["path"])] = true
				added = true
	_scan_directory(root, script_paths, result)
	result.sort_custom(func(a: GDLevelSceneRes, b: GDLevelSceneRes) -> bool:
		var a_name := _title_of(a)
		var b_name := _title_of(b)
		return a.resource_path.naturalnocasecmp_to(b.resource_path) < 0 if a_name == b_name else a_name.naturalnocasecmp_to(b_name) < 0
	)
	return result


static func _scan_directory(path: String, script_paths: Dictionary, result: Array[GDLevelSceneRes]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file in directory.get_files():
		if file.begins_with(".") or not file.get_extension().to_lower() in ["tres", "res"]:
			continue
		var resource_path := path.path_join(file)
		var candidate := false
		for dependency in ResourceLoader.get_dependencies(resource_path):
			var script_path := dependency.get_slice("::", 2) if dependency.contains("::") else dependency
			if script_paths.has(script_path):
				candidate = true
				break
		if candidate:
			var level := ResourceLoader.load(resource_path) as GDLevelSceneRes
			if level != null:
				result.append(level)
	for child in directory.get_directories():
		var child_path := path.path_join(child)
		if child.begins_with(".") or FileAccess.file_exists(child_path.path_join("project.godot")) or FileAccess.file_exists(child_path.path_join(".gdignore")):
			continue
		_scan_directory(child_path, script_paths, result)
