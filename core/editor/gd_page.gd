@tool
class_name GDPage
extends VBoxContainer

## 四个编辑器页面的共同骨架。
##
##   工具栏：文档名 ● | 保存 撤销 重做 | 页面自己的按钮 ……… 右侧按钮
##   主体：  左侧资产库 | 中央工作区 | 右侧属性
##
## 子类覆写 _build（搭界面）和 _refresh（从模型刷新）。
## 改模型只走一条路：edit(label, 改动)，或者改完之后 doc.commit(label)。

signal status_changed(text: String, tone: StringName)
## 文档的脏标记或撤销状态变了，外壳据此刷新页签。
signal document_state_changed

var doc: GDDocument = null
## 页面专属按钮放这里。
var toolbar: HBoxContainer = null
## 靠右的按钮放这里。
var toolbar_right: HBoxContainer = null

var _docs: Dictionary = {} # Resource -> GDDocument
var _doc_label: Label = null
var _save_btn: Button = null
var _undo_btn: Button = null
var _redo_btn: Button = null
var _panes: Control = null
var _status_row: Control = null
var _bottom_split: VSplitContainer = null


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", GDEditorUi.GAP)
	_build_chrome()
	_build()
	_sync_chrome()


## 子类覆写：搭界面。
func _build() -> void:
	pass


## 子类覆写：模型变了，刷新视图。不要在这里提交改动。
func _refresh() -> void:
	pass


## 子类覆写：页面显示出来，或窗口重新拿到焦点。
func activate() -> void:
	pass


## 子类覆写：控制台在这一页执行 command 时附带的默认参数，例如 ["--layout", "res://x.tres"]。
func cli_context(_command: String) -> PackedStringArray:
	return PackedStringArray()


## 子类覆写：没有保存路径时给出建议路径，返回空串则弹“另存为”。
func _suggest_save_path(_resource: Resource) -> String:
	return ""


## 切换到某个资产。同一资产再次打开时沿用它的撤销历史。
func open_document(resource: Resource) -> GDDocument:
	if doc != null:
		doc.changed.disconnect(_refresh)
		doc.state_changed.disconnect(_sync_chrome)
	doc = null
	if resource != null:
		if not _docs.has(resource):
			_docs[resource] = GDDocument.new(resource)
		doc = _docs[resource]
		doc.changed.connect(_refresh)
		doc.state_changed.connect(_sync_chrome)
	_sync_chrome()
	return doc


func close_document(resource: Resource) -> void:
	_docs.erase(resource)
	if doc != null and doc.resource == resource:
		open_document(null)


func edit(label: String, change: Callable, merge: bool = false) -> void:
	if doc == null:
		return
	change.call()
	doc.commit(label, merge)


func say(text: String, tone: StringName = &"muted") -> void:
	status_changed.emit(text, tone)


func save_current() -> void:
	if doc != null:
		_save(doc)


func save_all() -> void:
	for candidate: GDDocument in _docs.values():
		prepare_save(candidate)
		if candidate.dirty:
			_save(candidate)


## 先同步场景等外部状态，再决定文档是否需要保存。
func prepare_save(_target: GDDocument) -> void:
	pass


func unsaved_titles() -> PackedStringArray:
	var titles := PackedStringArray()
	for candidate: GDDocument in _docs.values():
		if candidate.dirty:
			titles.append(doc_title(candidate.resource))
	return titles


func is_dirty() -> bool:
	return not unsaved_titles().is_empty()


## 子类可覆写：资产在工具栏和未保存提示里显示的名字。
func doc_title(resource: Resource) -> String:
	if resource == null:
		return ""
	var named: Variant = resource.get("display_name")
	if named is String and not named.is_empty():
		return named
	return resource.resource_name if not resource.resource_name.is_empty() else resource.resource_path.get_file()


func save_as_current() -> void:
	if doc == null:
		return
	_show_save_as(doc)


func _show_save_as(target: GDDocument, suggested: String = "") -> void:
	var initial := suggested if not suggested.is_empty() else _suggested_or_default(target.resource)
	GDDialogs.save_file(self, "另存为", PackedStringArray(["*.tres ; Godot 资源"]), initial, func(path: String) -> void:
		# FileDialog 在已有文件时先询问覆盖。其它已加载文档仍由 GDDocument 拒绝。
		_report_save(target, _save_as(target, path, true), path)
	)


func _save_as(target: GDDocument, path: String, allow_overwrite: bool = false) -> Error:
	prepare_save(target)
	return target.save(path, allow_overwrite)


func _save(target: GDDocument) -> void:
	prepare_save(target)
	if target.resource.resource_path.is_empty():
		var suggested := _suggest_save_path(target.resource)
		if suggested.is_empty():
			_show_save_as(target)
			return
		_report_save(target, target.save(suggested), suggested)
	else:
		_report_save(target, target.save())


func _report_save(target: GDDocument, err: Error, attempted_path: String = "") -> void:
	if err == OK:
		say("已保存 %s" % target.resource.resource_path, &"ok")
	else:
		if target.resource.resource_path.is_empty():
			target.mark_unsaved()
		say("保存失败：%s（%s）" % [target.resource.resource_path, error_string(err)], &"danger")
		if err == ERR_ALREADY_EXISTS and is_inside_tree():
			_show_save_conflict(target, attempted_path if not attempted_path.is_empty() else _suggested_or_default(target.resource))


func _alternative_save_path(target: GDDocument, attempted_path: String) -> String:
	var suffix := 2
	var extension := attempted_path.get_extension()
	var stem := attempted_path.get_basename()
	var candidate := "%s_%d.%s" % [stem, suffix, extension]
	while target.can_save(candidate) != OK:
		suffix += 1
		candidate = "%s_%d.%s" % [stem, suffix, extension]
	return candidate


func _show_save_conflict(target: GDDocument, attempted_path: String) -> void:
	var alternative := _alternative_save_path(target, attempted_path)
	var dialog := GDDialogs.confirm(self, "保存路径已占用", "文件已存在或已被其它文档打开。请选择新的保存位置。\n%s" % attempted_path,
		"另存为…", func() -> void: _show_save_as(target, alternative))
	dialog.add_button("保存为 %s" % alternative.get_file(), false, "unique")
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"unique":
			dialog.hide()
			_report_save(target, _save_as(target, alternative), alternative)
	)


func _suggested_or_default(resource: Resource) -> String:
	var suggested := _suggest_save_path(resource)
	return suggested if not suggested.is_empty() else "res://%s.tres" % doc_title(resource).validate_filename()


func _build_chrome() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	add_child(bar)

	_doc_label = GDEditorUi.title_label("")
	_doc_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_doc_label.clip_text = false
	_doc_label.custom_minimum_size.x = 0
	bar.add_child(_doc_label)
	var gap := Control.new()
	gap.custom_minimum_size.x = GDEditorUi.GAP
	bar.add_child(gap)

	_save_btn = GDEditorUi.tool_button(&"Save", "保存", save_current, GDEditorUi.key(KEY_S, true))
	_undo_btn = GDEditorUi.tool_button(&"UndoRedo", "撤销", func() -> void: _step_history(true), GDEditorUi.key(KEY_Z, true))
	_redo_btn = GDEditorUi.tool_button(&"Redo", "重做", func() -> void: _step_history(false), GDEditorUi.key(KEY_Y, true))
	for btn in [_save_btn, _undo_btn, _redo_btn]:
		btn.shortcut_context = self
		bar.add_child(btn)
	bar.add_child(VSeparator.new())

	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 2)
	bar.add_child(toolbar)
	bar.add_child(GDEditorUi.spacer())
	toolbar_right = HBoxContainer.new()
	toolbar_right.add_theme_constant_override("separation", 2)
	bar.add_child(toolbar_right)
	GDEditorUi.wrap_toolbar(bar)


func _step_history(backwards: bool) -> void:
	if doc == null:
		return
	var label := doc.undo_label if backwards else doc.redo_label
	if backwards and doc.undo():
		say("已撤销：%s" % label)
	elif not backwards and doc.redo():
		say("已重做：%s" % label)


func _sync_chrome() -> void:
	var has_doc := doc != null
	_doc_label.text = "" if not has_doc else "%s%s" % [doc_title(doc.resource), "  ●" if doc.dirty else ""]
	_doc_label.tooltip_text = "" if not has_doc else (doc.resource.resource_path if not doc.resource.resource_path.is_empty() else "尚未保存到磁盘")
	_save_btn.disabled = not has_doc
	_undo_btn.disabled = not has_doc or not doc.can_undo
	_redo_btn.disabled = not has_doc or not doc.can_redo
	_undo_btn.tooltip_text = "撤销" if not has_doc or not doc.can_undo else "撤销：%s" % doc.undo_label
	_redo_btn.tooltip_text = "重做" if not has_doc or not doc.can_redo else "重做：%s" % doc.redo_label
	document_state_changed.emit()


## 组装“左 | 中 | 右”三栏。任意一栏传 null 表示没有。分隔位置按页面记住。
func set_panes(left: Control, center: Control, right: Control, left_width: int = 240, right_width: int = 300) -> void:
	var page_key := String((get_script() as Script).get_global_name())
	var outer := HSplitContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(outer)
	_panes = outer
	var host: Container = outer
	if left != null:
		left.custom_minimum_size.x = 180
		outer.add_child(left)
		_remember_split(outer, "%s.left" % page_key, left_width)
		if right != null:
			var inner := HSplitContainer.new()
			inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			outer.add_child(inner)
			host = inner
	if center != null:
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.add_child(center)
	if right != null:
		right.custom_minimum_size.x = 240
		host.add_child(right)
		_remember_split(host, "%s.right" % page_key, -right_width)


static func _remember_split(split: SplitContainer, key: String, default_offset: int) -> void:
	split.split_offset = GDHybridPrefs.get_int("Gdesigner.Split.%s" % key, default_offset)
	split.dragged.connect(func(offset: int) -> void: GDHybridPrefs.set_int("Gdesigner.Split.%s" % key, offset))


## Optional second toolbar row. Existing pages retain their original layout.
func set_status_row(control: Control) -> void:
	if is_instance_valid(_status_row):
		remove_child(_status_row)
		_status_row.queue_free()
	_status_row = control
	if control != null:
		add_child(control)
		move_child(control, 1)


## A resizable bottom panel, with its height remembered per page.
func set_bottom(control: Control, default_height: int = 180) -> void:
	if _bottom_split == null:
		_bottom_split = VSplitContainer.new()
		_bottom_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(_bottom_split)
		if _panes != null:
			_panes.reparent(_bottom_split)
		var page_key := String((get_script() as Script).get_global_name())
		_remember_split(_bottom_split, "%s.bottom" % page_key, -default_height)
	elif _bottom_split.get_child_count() > 1:
		var previous := _bottom_split.get_child(1)
		_bottom_split.remove_child(previous)
		previous.queue_free()
	if control != null:
		_bottom_split.add_child(control)
