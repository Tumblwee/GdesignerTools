@tool
class_name GDKeywordCatalogDialog
extends AcceptDialog

## 编辑“类型”目录：改名、新增、停用。关卡和演员共用。
## 删除是软删除：稳定 ID 不复用，重新添加同名类型会复活原 ID。

var _catalog: Resource = null
var _on_changed: Callable = Callable()
var _rows: VBoxContainer = null
var _new_edit: LineEdit = null
var _status: Label = null


## on_changed(label)：目录被改动后调用。
static func open(host: Node, catalog: Resource, on_changed: Callable) -> GDKeywordCatalogDialog:
	var dialog := GDKeywordCatalogDialog.new()
	dialog._catalog = catalog
	dialog._on_changed = on_changed
	dialog._build()
	host.add_child(dialog)
	dialog.popup_centered()
	return dialog


func _build() -> void:
	title = "类型目录"
	ok_button_text = "完成"
	min_size = Vector2i(420, 440)
	visibility_changed.connect(func() -> void:
		if not visible:
			queue_free.call_deferred()
	)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", GDEditorUi.GAP)
	add_child(root)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	root.add_child(GDEditorUi.scroll_of(_rows))

	var add_row := HBoxContainer.new()
	root.add_child(add_row)
	_new_edit = LineEdit.new()
	_new_edit.placeholder_text = "输入新类型的名字，回车添加"
	_new_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_edit.text_submitted.connect(func(_t: String) -> void: _add_entry())
	add_row.add_child(_new_edit)
	add_row.add_child(GDEditorUi.tool_button(&"Add", "添加", _add_entry))

	var generate := FoldableContainer.new()
	generate.title = "枚举代码生成"
	generate.folded = true
	root.add_child(generate)
	var form := GDForm.new()
	generate.add_child(form)
	form.text("输出目录",
		func() -> String: return _catalog.generated_output_folder,
		func(value: String) -> void: _catalog.editor_set_generated_output_folder(value),
		{"placeholder": "例如 res://generated/keywords"}
	)
	form.committed.connect(func(_label: String, _merge: bool) -> void: _notify("修改输出目录"))
	form.button("生成枚举", _generate)
	_status = form.note("")
	_refresh()


func _refresh() -> void:
	GDEditorUi.clear_children(_rows)
	for entry in _catalog.entries:
		if entry != null and not entry.deprecated:
			_rows.add_child(_make_row(entry))
	_status.text = (
		"尚未配置输出目录" if _catalog.generated_output_folder.is_empty()
		else ("枚举已是最新" if _catalog.is_enum_up_to_date() else "有改动，尚未生成")
	)


func _make_row(entry: Resource) -> Control:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.text = entry.display_name if not entry.display_name.is_empty() else entry.entry_name
	edit.tooltip_text = "%s · ID %d" % [entry.entry_name, entry.stable_id]
	edit.select_all_on_focus = true
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var apply := func() -> void:
		var value := edit.text.strip_edges()
		if not value.is_empty() and value != entry.display_name:
			entry.editor_set_metadata(value, entry.description)
			_catalog.emit_changed()
			_notify("重命名类型")
	edit.text_submitted.connect(func(_t: String) -> void: apply.call())
	edit.focus_exited.connect(apply)
	row.add_child(edit)
	row.add_child(GDEditorUi.tool_button(&"Remove", "停用这个类型", func() -> void:
		_catalog.remove_entry(entry.entry_name)
		_notify("停用类型")
		_refresh()
	))
	return row


func _add_entry() -> void:
	var display := _new_edit.text.strip_edges()
	if display.is_empty():
		return
	_catalog.add_entry(unique_internal_name(_catalog, display), display, "")
	_new_edit.text = ""
	_notify("添加类型")
	_refresh()


func _generate() -> void:
	if _catalog.enum_type_name.is_empty():
		_catalog.enum_type_name = "GeneratedArchetypeType"
	if _catalog.enum_namespace.is_empty():
		_catalog.enum_namespace = "Project.Keywords"
	if _catalog.regenerate():
		_notify("生成枚举")
		_refresh()
	else:
		_status.text = "生成失败：请检查输出目录"


func _notify(label: String) -> void:
	if _on_changed.is_valid():
		_on_changed.call(label)


## 从显示名取出合法的枚举字段名；中文名回退到 Type、Type2……
static func unique_internal_name(catalog: Resource, display: String) -> String:
	var base := ""
	for i in range(display.length()):
		var code := display.unicode_at(i)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			base += char(code)
	if base.is_empty():
		base = "Type"
	elif base.unicode_at(0) >= 48 and base.unicode_at(0) <= 57:
		base = "T" + base
	base = base.left(1).to_upper() + base.substr(1)
	var candidate := base
	var suffix := 1
	while catalog.find_any_by_name(candidate) != null:
		suffix += 1
		candidate = "%s%d" % [base, suffix]
	return candidate
