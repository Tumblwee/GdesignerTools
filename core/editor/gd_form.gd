@tool
class_name GDForm
extends VBoxContainer

## 声明式属性表单。每个字段只声明 read / write 两个闭包。
##
## 约定：
## - 文本在回车或失焦时提交，Esc 还原；数值和开关立刻提交。
## - 每次提交发 committed 信号，由页面转成 GDDocument.commit。
## - 模型变了只回读控件（sync），不重建，所以 Tab 切字段不会丢焦点。
##
## 用法：
##   if form.begin(selected_object):
##       form.text("名称", func(): return a.name, func(v): a.name = v)
##   # 同一个 key 下 begin 返回 false，并只刷新控件的值。

signal committed(label: String, merge: bool)

const LABEL_WIDTH := 92

## 记住各折叠区的开合，切换选中项时不会反复重置。
static var _folded_by_title: Dictionary = {}

var _key: Variant = null
var _target: Container = self
var _readers: Array[Callable] = []
var _syncing: bool = false
var _suspended: bool = false


func _init() -> void:
	add_theme_constant_override("separation", GDEditorUi.GAP)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func begin(key: Variant) -> bool:
	if key == _key and _key != null:
		sync()
		return false
	clear()
	_key = key
	return true


func clear() -> void:
	_suspended = true
	GDEditorUi.clear_children(self)
	_suspended = false
	_readers.clear()
	_key = null
	_target = self


## 回读模型到控件。正在输入的文本框不会被覆盖。
func sync() -> void:
	_syncing = true
	for reader in _readers:
		reader.call()
	_syncing = false


func heading(title: String, subtitle: String = "") -> void:
	_target.add_child(GDEditorUi.title_label(title))
	if not subtitle.is_empty():
		_target.add_child(GDEditorUi.hint_label(subtitle))


## 开一个折叠区，之后的字段都放进去。end_group 回到顶层。
func group(title: String, folded_by_default: bool = false) -> void:
	end_group()
	var fold := FoldableContainer.new()
	fold.title = title
	fold.folded = bool(_folded_by_title.get(title, folded_by_default))
	fold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fold.folding_changed.connect(func(is_folded: bool) -> void: _folded_by_title[title] = is_folded)
	add_child(fold)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", GDEditorUi.GAP)
	fold.add_child(box)
	_target = box


func end_group() -> void:
	_target = self


func note(message: String, tone: StringName = &"muted") -> Label:
	var label := GDEditorUi.hint_label(message)
	label.add_theme_color_override("font_color", GDEditorUi.tone(tone))
	_target.add_child(label)
	return label


func custom(control: Control) -> Control:
	_target.add_child(control)
	return control


## 文字随模型变化的提示。read 返回空串时隐藏。
func live_note(read: Callable, tone: StringName = &"warn") -> void:
	var label := note("", tone)
	var pull := func() -> void:
		label.text = str(read.call())
		label.visible = not label.text.is_empty()
	_readers.append(pull)
	pull.call()


## 自定义控件的状态随模型刷新（例如按钮的可用 / 可见）。立即调用一次，之后每次回读都调用。
func on_sync(apply: Callable) -> void:
	_readers.append(apply)
	apply.call()


## 嵌在当前位置的子表单，提交和回读都接到父表单。用来给列表项单独分块。
func nested() -> GDForm:
	var child := GDForm.new()
	child.committed.connect(committed.emit)
	_readers.append(child.sync)
	_target.add_child(child)
	return child


func row(label: String, control: Control, tip: String = "") -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", GDEditorUi.GAP)
	var caption := GDEditorUi.muted_label(label)
	caption.custom_minimum_size.x = LABEL_WIDTH
	caption.clip_text = true
	caption.mouse_filter = Control.MOUSE_FILTER_PASS
	caption.tooltip_text = tip if not tip.is_empty() else label
	line.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(control)
	_target.add_child(line)
	return control


func button(text_value: String, on_pressed: Callable, kind: StringName = &"normal") -> Button:
	var btn := GDEditorUi.text_button(text_value, on_pressed, kind)
	_target.add_child(btn)
	return btn


func text(label: String, read: Callable, write: Callable, opts: Dictionary = {}) -> Control:
	return _text_area(label, read, write, opts) if opts.get("multiline", false) else _line_edit(label, read, write, opts)


func integer(label: String, read: Callable, write: Callable, opts: Dictionary = {}) -> SpinBox:
	return _spin(label, read, write, {"step": 1.0} if opts.is_empty() else ({"step": 1.0}.merged(opts)), true)


func number(label: String, read: Callable, write: Callable, opts: Dictionary = {}) -> SpinBox:
	return _spin(label, read, write, opts, false)


func toggle(label: String, read: Callable, write: Callable, tip: String = "") -> CheckBox:
	var box := CheckBox.new()
	box.toggled.connect(func(on: bool) -> void:
		if _syncing or on == bool(read.call()):
			return
		write.call(on)
		committed.emit(label, false)
	)
	_readers.append(func() -> void: box.set_pressed_no_signal(bool(read.call())))
	box.set_pressed_no_signal(bool(read.call()))
	return row(label, box, tip)


## items: [[文字, id], ...]。切换会改变表单结构时，让 begin 的 key 带上这个值。
func choice(label: String, items: Array, read: Callable, write: Callable, tip: String = "") -> OptionButton:
	var option := OptionButton.new()
	option.clip_text = true
	option.fit_to_longest_item = false
	for item: Array in items:
		option.add_item(str(item[0]), int(item[1]))
	var pull := func() -> void: option.select(option.get_item_index(int(read.call())))
	option.item_selected.connect(func(index: int) -> void:
		var picked := option.get_item_id(index)
		if picked != int(read.call()):
			write.call(picked)
			committed.emit(label, false)
	)
	_readers.append(pull)
	pull.call()
	return row(label, option, tip)


func vector3(label: String, read: Callable, write: Callable, step: float = 0.1) -> void:
	_vector(label, 3, read, write, step)


func vector2(label: String, read: Callable, write: Callable, step: float = 0.1) -> void:
	_vector(label, 2, read, write, step)


## 反射生成表单：扫描对象的 @export 字段。
## opts.labels    字段 -> 中文名
## opts.enums     字段 -> 枚举字典，或 [[文字, id], ...]
## opts.skip      要跳过的字段
## opts.only      只显示这些字段（同时决定顺序）
## opts.numbers   字段 -> 数值选项 {"min", "max", "step", "suffix", "tip"}
## opts.setters   字段 -> func(对象, 值)：模型有带校验或联动的 setter 时用它代替直接赋值
## 嵌套的数据 Resource 会展开成同一张表单。
func auto(target: Object, opts: Dictionary = {}) -> void:
	var labels: Dictionary = opts.get("labels", {})
	var enums: Dictionary = opts.get("enums", {})
	var skip: Array = opts.get("skip", [])
	var only: Array = opts.get("only", [])
	var props: Dictionary = {}
	for prop: Dictionary in target.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_EDITOR and prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			props[prop["name"]] = prop
	var names: Array = only if not only.is_empty() else props.keys()
	for prop_name: String in names:
		if prop_name in skip or not props.has(prop_name):
			continue
		var caption := str(labels.get(prop_name, prop_name.capitalize()))
		_auto_field(target, props[prop_name], caption, enums.get(prop_name), opts)


func _auto_field(target: Object, prop: Dictionary, caption: String, enum_def: Variant, opts: Dictionary) -> void:
	var prop_name: String = prop["name"]
	var read := func() -> Variant: return target.get(prop_name)
	var setter: Callable = opts.get("setters", {}).get(prop_name, Callable())
	var write := func(value: Variant) -> void:
		if setter.is_valid():
			setter.call(target, value)
		else:
			target.set(prop_name, value)
	var number_opts: Dictionary = opts.get("numbers", {}).get(prop_name, {})
	if enum_def != null:
		choice(caption, _enum_items(enum_def), read, write)
		return
	match int(prop["type"]):
		TYPE_BOOL:
			toggle(caption, read, write)
		TYPE_INT:
			if int(prop["hint"]) == PROPERTY_HINT_ENUM:
				choice(caption, _enum_items_from_hint(str(prop["hint_string"])), read, write)
			else:
				integer(caption, read, write, number_opts)
		TYPE_FLOAT:
			number(caption, read, write, number_opts)
		TYPE_STRING:
			text(caption, read, write, {"multiline": int(prop["hint"]) == PROPERTY_HINT_MULTILINE_TEXT})
		TYPE_VECTOR2:
			vector2(caption, read, write)
		TYPE_VECTOR3:
			vector3(caption, read, write)
		TYPE_OBJECT:
			var nested: Variant = target.get(prop_name)
			if nested is Resource and nested.get_script() != null and nested.resource_path.is_empty():
				auto(nested, opts.merged({"only": [], "skip": []}, true))


static func _enum_items(enum_def: Variant) -> Array:
	if enum_def is Array:
		return enum_def
	var items: Array = []
	for name_key: String in enum_def:
		items.append([name_key.capitalize(), int(enum_def[name_key])])
	return items


static func _enum_items_from_hint(hint: String) -> Array:
	var items: Array = []
	var next_id := 0
	for part in hint.split(","):
		var pieces := part.split(":")
		if pieces.size() > 1:
			next_id = pieces[1].to_int()
		items.append([pieces[0].capitalize(), next_id])
		next_id += 1
	return items


func _line_edit(label: String, read: Callable, write: Callable, opts: Dictionary) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = str(opts.get("placeholder", ""))
	edit.editable = not bool(opts.get("readonly", false))
	edit.select_all_on_focus = true
	var apply := func() -> void:
		if _suspended or not edit.editable:
			return
		var value := edit.text.strip_edges()
		if value != str(read.call()):
			write.call(value)
			committed.emit(label, false)
	edit.text_submitted.connect(func(_t: String) -> void: apply.call())
	edit.focus_exited.connect(apply)
	edit.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed(&"ui_cancel"):
			edit.text = str(read.call())
			edit.release_focus()
			edit.accept_event()
	)
	_readers.append(func() -> void:
		if not edit.has_focus():
			edit.text = str(read.call())
	)
	edit.text = str(read.call())
	return row(label, edit, str(opts.get("tip", "")))


func _text_area(label: String, read: Callable, write: Callable, opts: Dictionary) -> TextEdit:
	var area := TextEdit.new()
	area.scroll_fit_content_height = true
	area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	area.custom_minimum_size.y = 56
	area.placeholder_text = str(opts.get("placeholder", ""))
	area.focus_exited.connect(func() -> void:
		if not _suspended and area.text != str(read.call()):
			write.call(area.text)
			committed.emit(label, false)
	)
	_readers.append(func() -> void:
		if not area.has_focus():
			area.text = str(read.call())
	)
	area.text = str(read.call())
	return row(label, area, str(opts.get("tip", "")))


func _spin(label: String, read: Callable, write: Callable, opts: Dictionary, as_int: bool) -> SpinBox:
	var spin := _make_spin(opts)
	var push := func(value: float) -> void:
		if _syncing:
			return
		var current := float(read.call())
		if is_equal_approx(value, current):
			return
		write.call(roundi(value) if as_int else value)
		committed.emit(label, true)
	spin.value_changed.connect(push)
	_readers.append(func() -> void: spin.value = float(read.call()))
	_syncing = true
	spin.value = float(read.call())
	_syncing = false
	return row(label, spin, str(opts.get("tip", "")))


func _vector(label: String, axes: int, read: Callable, write: Callable, step: float) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 2)
	var spins: Array[SpinBox] = []
	for i in range(axes):
		var spin := _make_spin({"step": step, "prefix": "XYZ"[i]})
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spins.append(spin)
		line.add_child(spin)
	var compose := func() -> Variant:
		if axes == 2:
			return Vector2(spins[0].value, spins[1].value)
		return Vector3(spins[0].value, spins[1].value, spins[2].value)
	for spin in spins:
		spin.value_changed.connect(func(_v: float) -> void:
			if _syncing:
				return
			var value: Variant = compose.call()
			if not value.is_equal_approx(read.call()):
				write.call(value)
				committed.emit(label, true)
		)
	var pull := func() -> void:
		var value: Variant = read.call()
		for i in range(axes):
			spins[i].value = float(value[i])
	_readers.append(pull)
	_syncing = true
	pull.call()
	_syncing = false
	_target.add_child(GDEditorUi.muted_label(label))
	_target.add_child(line)


static func _make_spin(opts: Dictionary) -> SpinBox:
	var spin := SpinBox.new()
	spin.step = float(opts.get("step", 0.01))
	spin.select_all_on_focus = true
	spin.prefix = str(opts.get("prefix", ""))
	spin.suffix = str(opts.get("suffix", ""))
	spin.min_value = float(opts.get("min", -1000000.0))
	spin.max_value = float(opts.get("max", 1000000.0))
	spin.allow_lesser = not opts.has("min")
	spin.allow_greater = not opts.has("max")
	return spin
