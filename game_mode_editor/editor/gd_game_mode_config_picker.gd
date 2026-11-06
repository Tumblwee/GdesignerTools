@tool
class_name GDGameModeConfigPicker
extends ConfirmationDialog

## 从已有游戏进程配置中选择，包含当前会话里尚未保存的配置。

class AssetList extends GDLibraryList:
	signal selection_changed

	func _init() -> void:
		super("游戏进程配置", "搜索配置名称或路径")
		item_selected.connect(func(_key: Variant) -> void: selection_changed.emit())
		_tree.empty_clicked.connect(func(_at: Vector2, _button: int) -> void: selection_changed.emit())
		_search.text_changed.connect(func(_text: String) -> void: selection_changed.emit())

	func selected_config() -> GDGameModeConfigRes:
		return _key_of(_tree.get_selected()) as GDGameModeConfigRes


var _list: AssetList = null
var _on_config: Callable = Callable()


func _init() -> void:
	title = "打开游戏进程配置"
	ok_button_text = "打开"
	cancel_button_text = "取消"
	dialog_hide_on_ok = false
	min_size = Vector2i(760, 480)
	_list = AssetList.new()
	_list.set_detail_width(360)
	_list.set_empty_state(GDEditorUi.empty_state("还没有游戏进程配置", "请先点击“新建”创建配置。"))
	_list.selection_changed.connect(func() -> void: get_ok_button().disabled = _list.selected_config() == null)
	_list.item_activated.connect(func(_key: Variant) -> void: _open_selected())
	add_child(_list)
	confirmed.connect(_open_selected)
	get_ok_button().disabled = true


static func open(host: Node, on_config: Callable, opened: Array = []) -> GDGameModeConfigPicker:
	var dialog := GDGameModeConfigPicker.new()
	dialog._on_config = on_config
	var rows: Array = []
	var configs := scan_configs()
	for resource in opened:
		if resource is GDGameModeConfigRes and not configs.has(resource):
			configs.append(resource)
	_sort_configs(configs)
	for config in configs:
		var detail := config.resource_path if not config.resource_path.is_empty() else "尚未保存"
		rows.append({
			"key": config,
			"text": _title_of(config),
			"detail": detail,
			"tooltip": "%s\n%s" % [_title_of(config), detail],
		})
	dialog._list.set_items([{"title": "", "items": rows}])
	GDDialogs._show(host, dialog)
	if not rows.is_empty():
		dialog._list.focus_search()
	return dialog


func _open_selected() -> void:
	var config := _list.selected_config()
	if config == null:
		return
	_on_config.call(config)
	hide()


static func _title_of(config: GDGameModeConfigRes) -> String:
	if not config.display_name.is_empty():
		return config.display_name
	if not config.resource_name.is_empty():
		return config.resource_name
	return config.resource_path.get_file().get_basename() if not config.resource_path.is_empty() else "未命名配置"


## 先检查脚本依赖，避免为列举配置而实例化项目中的所有资源。
static func scan_configs(root: String = "res://") -> Array[GDGameModeConfigRes]:
	var result: Array[GDGameModeConfigRes] = []
	var script_paths := {"res://addons/gdesigner_tools/game_mode_editor/runtime/gd_game_mode_config_res.gd": true}
	var classes := {"GDGameModeConfigRes": true}
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
	_sort_configs(result)
	return result


static func _sort_configs(configs: Array[GDGameModeConfigRes]) -> void:
	configs.sort_custom(func(a: GDGameModeConfigRes, b: GDGameModeConfigRes) -> bool:
		var a_name := _title_of(a)
		var b_name := _title_of(b)
		return a.resource_path.naturalnocasecmp_to(b.resource_path) < 0 if a_name == b_name else a_name.naturalnocasecmp_to(b_name) < 0
	)


static func _scan_directory(path: String, script_paths: Dictionary, result: Array[GDGameModeConfigRes]) -> void:
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
			var config := ResourceLoader.load(resource_path) as GDGameModeConfigRes
			if config != null:
				result.append(config)
	for child in directory.get_directories():
		var child_path := path.path_join(child)
		if child.begins_with(".") or FileAccess.file_exists(child_path.path_join("project.godot")) or FileAccess.file_exists(child_path.path_join(".gdignore")):
			continue
		_scan_directory(child_path, script_paths, result)
