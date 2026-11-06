@tool
class_name GDKeywordCatalogDialog
extends AcceptDialog

## 编辑“类型”目录：改名、颜色、新增、停用。关卡和演员共用。
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
	var hint := Label.new()
	hint.text = "点击色块修改类型颜色，同类型的原型和实例共用。"
	root.add_child(hint)

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
	row.set_meta(&"type_entry", entry)
	var color := ColorPickerButton.new()
	color.custom_minimum_size = Vector2(44, 28)
	color.edit_alpha = false
	color.color = entry.get_display_color()
	color.tooltip_text = "类型颜色 · #%s" % color.color.to_html(false)
	color.get_picker().deferred_mode = true
	color.color_changed.connect(func(value: Color) -> void:
		var opaque := Color(value, 1.0)
		if opaque.is_equal_approx(entry.get_display_color()):
			return
		entry.display_color = opaque
		_catalog.emit_changed()
		_notify("修改类型颜色")
		refresh_colors()
	)
	row.add_child(color)
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


## 撤销、重做只同步色块，不重建正在使用的取色器。
func refresh_colors() -> void:
	for row in _rows.get_children():
		var entry: Resource = row.get_meta(&"type_entry", null)
		if entry != null:
			var color := row.get_child(0) as ColorPickerButton
			color.color = entry.get_display_color()
			color.tooltip_text = "类型颜色 · #%s" % color.color.to_html(false)


func _add_entry() -> void:
	var display := _new_edit.text.strip_edges()
	if display.is_empty():
		return
	# 相同显示名不重复创建；停用后再次添加则恢复同一个稳定 ID。
	for entry in _catalog.entries:
		if entry != null and entry.display_name == display:
			if not entry.deprecated:
				_status.text = "已存在这个类型"
				return
			_catalog.add_entry(entry.entry_name, display, entry.description)
			_new_edit.text = ""
			_notify("恢复类型")
			_refresh()
			return
	var added = _catalog.add_entry(unique_internal_name(_catalog, display), display, "")
	if added == null:
		_status.text = "添加失败：类型名称无效"
		return
	_new_edit.text = ""
	_notify("添加类型")
	_refresh()


func _generate() -> void:
	# 生成是可选操作。给首次生成提供有效路径，避免把配置缺失报成编译错误。
	if _catalog.enum_type_name.is_empty():
		_catalog.enum_type_name = "GeneratedArchetypeType"
	if _catalog.enum_namespace.is_empty():
		_catalog.enum_namespace = "Project.Keywords"
	if _catalog.generated_file_path.strip_edges().is_empty():
		_catalog.editor_set_generated_output_folder("res://game_res/generated/keywords")
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
	while catalog.find_any_by_name(candidate) != null or not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(candidate):
		suffix += 1
		candidate = "%s%d" % [base, suffix]
	return candidate
