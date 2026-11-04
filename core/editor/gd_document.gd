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


## path 为空时写回原路径。没有路径返回 ERR_FILE_BAD_PATH，由调用方决定是否弹“另存为”。
func save(path: String = "") -> Error:
	var target := path if not path.is_empty() else resource.resource_path
	if target.is_empty():
		return ERR_FILE_BAD_PATH
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var err := ResourceSaver.save(resource, target, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		return err
	# FLAG_CHANGE_PATH 不会给从未保存过的资源设路径，这里补上，下次保存才会写回同一个文件。
	if resource.resource_path != target:
		resource.take_over_path(target)
	_saved_cursor = _cursor
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(target)
	state_changed.emit()
	return OK


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
