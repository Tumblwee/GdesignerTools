@tool
class_name GDActorLibraryPicker
extends ConfirmationDialog

## 以演员库为入口，不要求使用者了解资源文件所在目录。

class AssetList extends GDLibraryList:
	signal selection_changed

	func _init() -> void:
		super("演员库", "搜索演员库名称或路径")
		item_selected.connect(func(_key: Variant) -> void: selection_changed.emit())
		_tree.empty_clicked.connect(func(_at: Vector2, _button: int) -> void: selection_changed.emit())
		_search.text_changed.connect(func(_text: String) -> void: selection_changed.emit())

	func selected_library() -> GDActorLibraryRes:
		return _key_of(_tree.get_selected()) as GDActorLibraryRes


var _list: AssetList = null
var _on_library: Callable = Callable()


func _init() -> void:
	title = "打开演员库"
	ok_button_text = "打开"
	cancel_button_text = "取消"
	dialog_hide_on_ok = false
	min_size = Vector2i(760, 480)
	_list = AssetList.new()
	_list.set_detail_width(360)
	_list.set_empty_state(GDEditorUi.empty_state("还没有演员库", "请先新建并保存演员库。"))
	_list.selection_changed.connect(func() -> void: get_ok_button().disabled = _list.selected_library() == null)
	_list.item_activated.connect(func(_key: Variant) -> void: _open_selected())
	add_child(_list)
	confirmed.connect(_open_selected)
	get_ok_button().disabled = true


static func open(host: Node, on_library: Callable, opened: Array = []) -> GDActorLibraryPicker:
	var dialog := GDActorLibraryPicker.new()
	dialog._on_library = on_library
	var rows: Array = []
	var libraries := scan_libraries()
	for resource in opened:
		if resource is GDActorLibraryRes and not libraries.has(resource):
			libraries.append(resource)
	_sort_libraries(libraries)
	for library in libraries:
		rows.append({
			"key": library,
			"text": _title_of(library),
			"detail": library.resource_path if not library.resource_path.is_empty() else "尚未保存",
			"tooltip": "%s\n%s" % [_title_of(library), library.resource_path],
		})
	dialog._list.set_items([{"title": "", "items": rows}])
	GDDialogs._show(host, dialog)
	if not rows.is_empty():
		dialog._list.focus_search()
	return dialog


func _open_selected() -> void:
	var library := _list.selected_library()
	if library == null:
		return
	_on_library.call(library)
	hide()


static func _title_of(library: GDActorLibraryRes) -> String:
	if not library.display_name.is_empty():
		return library.display_name
	return library.resource_name if not library.resource_name.is_empty() else library.resource_path.get_file().get_basename()


## 先检查脚本依赖，避免为列举演员库而实例化项目中的所有资源。
static func scan_libraries(root: String = "res://") -> Array[GDActorLibraryRes]:
	var result: Array[GDActorLibraryRes] = []
	var script_paths := {"res://addons/gdesigner_tools/actor_editor/runtime/gd_actor_library_res.gd": true}
	var classes := {"GDActorLibraryRes": true}
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
	_sort_libraries(result)
	return result


static func _sort_libraries(libraries: Array[GDActorLibraryRes]) -> void:
	libraries.sort_custom(func(a: GDActorLibraryRes, b: GDActorLibraryRes) -> bool:
		var a_name := _title_of(a)
		var b_name := _title_of(b)
		return a.resource_path.naturalnocasecmp_to(b.resource_path) < 0 if a_name == b_name else a_name.naturalnocasecmp_to(b_name) < 0
	)


static func _scan_directory(path: String, script_paths: Dictionary, result: Array[GDActorLibraryRes]) -> void:
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
			var library := ResourceLoader.load(resource_path) as GDActorLibraryRes
			if library != null:
				result.append(library)
	for child in directory.get_directories():
		var child_path := path.path_join(child)
		if child.begins_with(".") or FileAccess.file_exists(child_path.path_join("project.godot")) or FileAccess.file_exists(child_path.path_join(".gdignore")):
			continue
		_scan_directory(child_path, script_paths, result)
