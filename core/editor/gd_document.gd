@tool
class_name GDDocument
extends RefCounted

## 一份正在编辑的资产：撤销栈、脏标记、保存。
##
## 页面只做两件事：改模型，然后调 commit("改了什么")。视图统一响应 changed 信号刷新。
##
## 快照是一张“对象 -> 字段值”的表，而不是深拷贝。撤销时把字段写回原对象，
## 所以对象身份不变：选中项不会失效，外部 .tres 的 resource_path 也不会丢。

signal changed
signal state_changed

const MAX_HISTORY := 128
const MERGE_WINDOW_MS := 700
static var _tracked_resources: Array[WeakRef] = []
static var _saving_paths: Dictionary = {}

var resource: Resource
## 撤销 / 重做写回模型之后调用，用于同步模型之外的状态（例如场景节点）。
var on_restored: Callable = Callable()

var _history: Array[Dictionary] = []
var _cursor: int = 0
var _saved_cursor: int = 0
var _last_commit_ms: int = 0

var dirty: bool:
	get:
		return _cursor != _saved_cursor

var can_undo: bool:
	get:
		return _cursor > 0

var can_redo: bool:
	get:
		return _cursor < _history.size() - 1

var undo_label: String:
	get:
		return str(_history[_cursor]["label"]) if can_undo else ""

var redo_label: String:
	get:
		return str(_history[_cursor + 1]["label"]) if can_redo else ""


func _init(p_resource: Resource) -> void:
	resource = p_resource
	_track_resource(resource)
	_history.append(_entry(""))


## merge = true：短时间内同名提交合并成一步，拖动和滚轮不会刷爆撤销栈。
func commit(label: String, merge: bool = false) -> void:
	var now := Time.get_ticks_msec()
	var mergeable := (
		merge and can_undo and not can_redo
		and undo_label == label
		and now - _last_commit_ms <= MERGE_WINDOW_MS
	)
	_last_commit_ms = now
	if mergeable:
		_history[_cursor] = _entry(label)
		if _saved_cursor == _cursor:
			_saved_cursor = -1
	else:
		_history.resize(_cursor + 1)
		if _saved_cursor > _cursor:
			_saved_cursor = -1
		_history.append(_entry(label))
		_cursor += 1
		_trim()
	changed.emit()
	state_changed.emit()


func undo() -> bool:
	return can_undo and _move_to(_cursor - 1)


func redo() -> bool:
	return can_redo and _move_to(_cursor + 1)


func mark_unsaved() -> void:
	_saved_cursor = -1
	state_changed.emit()


func mark_saved() -> void:
	_saved_cursor = _cursor
	state_changed.emit()


## 同一路径只允许当前持有它的资源写回。覆盖其它文件必须由另存为显式授权。
## 已被其它资源加载的路径始终拒绝，避免 take_over_path 抢走其它文档的路径。
func can_save(path: String = "", allow_overwrite: bool = false) -> Error:
	var target := normalized_path(path if not path.is_empty() else resource.resource_path)
	if target.is_empty():
		return ERR_FILE_BAD_PATH
	var target_key := path_key(target)
	if _saving_paths.has(target_key):
		return ERR_BUSY
	for reference in _tracked_resources.duplicate():
		var other := reference.get_ref() as Resource
		if other == null:
			_tracked_resources.erase(reference)
		elif other != resource and not other.resource_path.is_empty() and path_key(other.resource_path) == target_key:
			return ERR_ALREADY_EXISTS
	if ResourceLoader.has_cached(target) and ResourceLoader.load(target) != resource:
		return ERR_ALREADY_EXISTS
	var same_path := not resource.resource_path.is_empty() and path_key(resource.resource_path) == path_key(target)
	if not same_path and FileAccess.file_exists(target) and not allow_overwrite:
		return ERR_ALREADY_EXISTS
	return OK


func owns_path(path: String) -> bool:
	var target := normalized_path(path)
	return not resource.resource_path.is_empty() and path_key(resource.resource_path) == path_key(target) \
		and can_save(target, true) == OK


func save(path: String = "", allow_overwrite: bool = false) -> Error:
	var target := normalized_path(path if not path.is_empty() else resource.resource_path)
	var check := can_save(target, allow_overwrite)
	if check != OK:
		if resource.resource_path.is_empty():
			mark_unsaved()
		return check
	var directory_error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if directory_error != OK:
		return directory_error
	var target_key := path_key(target)
	_saving_paths[target_key] = true
	var err := ResourceSaver.save(resource, target)
	_saving_paths.erase(target_key)
	if err != OK:
		return err
	# 只有写入成功后才接管路径，保存失败时保留原文档身份。
	if resource.resource_path != target:
		resource.take_over_path(target)
	_track_resource(resource)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(target)
	mark_saved()
	return OK


static func normalized_path(path: String) -> String:
	if path.is_empty():
		return ""
	var absolute := ProjectSettings.globalize_path(path.replace("\\", "/")).simplify_path()
	if OS.has_feature("windows") and FileAccess.file_exists(absolute):
		absolute = _existing_path_case(absolute)
	var user_root := OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if path_key(absolute).begins_with(path_key(user_root) + "/"):
		return "user://" + absolute.substr(user_root.length() + 1)
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	if path_key(absolute).begins_with(path_key(project_root) + "/"):
		return "res://" + absolute.substr(project_root.length() + 1)
	return ProjectSettings.localize_path(absolute)


static func path_key(path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path.replace("\\", "/")).simplify_path()
	return absolute.to_lower() if OS.has_feature("windows") else absolute


static func _track_resource(tracked: Resource) -> void:
	for reference in _tracked_resources.duplicate():
		var existing: Object = reference.get_ref()
		if existing == null:
			_tracked_resources.erase(reference)
		elif existing == tracked:
			return
	_tracked_resources.append(weakref(tracked))


## Windows 的资源缓存区分大小写，已有文件先恢复磁盘上的目录名和文件名。
static func _existing_path_case(absolute: String) -> String:
	var parts := absolute.split("/", false)
	var current := parts[0] + "/"
	var first := 1
	if absolute.begins_with("//"):
		current = "//" + parts[0] + "/" + parts[1] + "/"
		first = 2
	# 从已知根目录向下查找，避免沙箱里枚举无权访问的盘符和用户目录。
	for root_path in [ProjectSettings.globalize_path("res://"), OS.get_user_data_dir(), OS.get_environment("TEMP")]:
		var anchor := str(root_path).replace("\\", "/").trim_suffix("/")
		if not anchor.is_empty() and path_key(absolute).begins_with(path_key(anchor) + "/"):
			current = anchor
			parts = absolute.substr(anchor.length() + 1).split("/", false)
			first = 0
			break
	for index in range(first, parts.size()):
		var segment := parts[index]
		var directory := DirAccess.open(current)
		if directory != null:
			var names := directory.get_directories()
			names.append_array(directory.get_files())
			for name in names:
				if name.nocasecmp_to(segment) == 0:
					segment = name
					break
		current = current.path_join(segment)
	return current


func _entry(label: String) -> Dictionary:
	return {"label": label, "snapshot": capture(resource)}


func _move_to(index: int) -> bool:
	_cursor = index
	restore(_history[_cursor]["snapshot"])
	if on_restored.is_valid():
		on_restored.call()
	changed.emit()
	state_changed.emit()
	return true


func _trim() -> void:
	while _history.size() > MAX_HISTORY:
		_history.pop_front()
		_cursor -= 1
		_saved_cursor = maxi(_saved_cursor - 1, -1)


static func capture(root: Resource) -> Dictionary:
	var table := {}
	_visit(root, table)
	return table


static func restore(table: Dictionary) -> void:
	for res: Resource in table:
		var fields: Dictionary = table[res]
		for field: StringName in fields:
			res.set(field, _isolated(fields[field]))


static func _visit(value: Variant, table: Dictionary) -> void:
	if value is Array:
		for item: Variant in value:
			_visit(item, table)
	elif value is Dictionary:
		for item: Variant in value.values():
			_visit(item, table)
	elif value is Resource and value.get_script() != null and not table.has(value):
		var fields := {&"resource_name": value.resource_name}
		table[value] = fields
		for prop: Dictionary in value.get_property_list():
			if prop["usage"] & PROPERTY_USAGE_STORAGE and prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var field: Variant = value.get(prop["name"])
				fields[StringName(prop["name"])] = _isolated(field)
				_visit(field, table)


static func _isolated(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value
