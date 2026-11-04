@tool
class_name GDDialogs
extends RefCounted

## 一次性对话框。用完自动释放，调用方不用持有任何窗口。


static func confirm(host: Node, title: String, message: String, ok_text: String, on_ok: Callable) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.dialog_autowrap = true
	dialog.ok_button_text = ok_text
	dialog.cancel_button_text = "取消"
	dialog.min_size = Vector2i(380, 0)
	dialog.confirmed.connect(on_ok)
	_show(host, dialog)
	return dialog


## 单行输入。validate: func(text) -> String，返回错误文案，空串表示通过。
static func prompt(host: Node, title: String, label: String, initial: String, on_ok: Callable, validate: Callable = Callable()) -> ConfirmationDialog:
	var fields: Array = [{"key": "value", "label": label, "value": initial}]
	var wrapped_validate := Callable()
	if validate.is_valid():
		wrapped_validate = func(values: Dictionary) -> String: return str(validate.call(str(values["value"])))
	return form(host, title, fields, func(values: Dictionary) -> void: on_ok.call(str(values["value"])), wrapped_validate)


## 多字段表单对话框。
## fields: [{"key", "label", "value", "placeholder"?, "items"?: [[文字, id], ...]}]。带 items 的是下拉框。
## validate: func(values: Dictionary) -> String。
static func form(host: Node, title: String, fields: Array, on_ok: Callable, validate: Callable = Callable()) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.ok_button_text = "确定"
	dialog.cancel_button_text = "取消"
	dialog.min_size = Vector2i(420, 0)

	var values := {}
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", GDEditorUi.GAP)
	dialog.add_child(box)
	var inputs := GDForm.new()
	box.add_child(inputs)
	var error := GDEditorUi.hint_label("")
	error.add_theme_color_override("font_color", GDEditorUi.tone(&"danger"))
	error.visible = false
	box.add_child(error)

	var revalidate := func() -> void:
		var message := str(validate.call(values)) if validate.is_valid() else ""
		error.text = message
		error.visible = not message.is_empty()
		dialog.get_ok_button().disabled = not message.is_empty()

	var first_edit: LineEdit = null
	for field: Dictionary in fields:
		var key: String = field["key"]
		values[key] = field.get("value", "")
		if field.has("items"):
			inputs.choice(str(field["label"]), field["items"],
				func() -> Variant: return values[key],
				func(v: Variant) -> void:
					values[key] = v
					revalidate.call()
			)
			continue
		var edit := LineEdit.new()
		edit.text = str(values[key])
		edit.placeholder_text = str(field.get("placeholder", ""))
		edit.select_all_on_focus = true
		edit.text_changed.connect(func(t: String) -> void:
			values[key] = t.strip_edges()
			revalidate.call()
		)
		dialog.register_text_enter(edit)
		inputs.row(str(field["label"]), edit)
		if first_edit == null:
			first_edit = edit

	dialog.confirmed.connect(func() -> void: on_ok.call(values))
	_show(host, dialog)
	revalidate.call()
	if first_edit != null:
		first_edit.grab_focus()
	return dialog


static func open_file(host: Node, title: String, filters: PackedStringArray, on_path: Callable) -> FileDialog:
	return _file_dialog(host, title, filters, FileDialog.FILE_MODE_OPEN_FILE, "", on_path)


static func save_file(host: Node, title: String, filters: PackedStringArray, suggested: String, on_path: Callable) -> FileDialog:
	return _file_dialog(host, title, filters, FileDialog.FILE_MODE_SAVE_FILE, suggested, on_path)


static func _file_dialog(host: Node, title: String, filters: PackedStringArray, mode: FileDialog.FileMode, suggested: String, on_path: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.file_mode = mode
	dialog.filters = filters
	dialog.size = Vector2i(760, 520)
	if not suggested.is_empty():
		dialog.current_path = suggested
	dialog.file_selected.connect(on_path)
	_show(host, dialog)
	return dialog


static func _show(host: Node, dialog: Window) -> void:
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free.call_deferred()
	)
	host.add_child(dialog)
	if dialog is AcceptDialog or dialog is FileDialog:
		dialog.popup_centered()
