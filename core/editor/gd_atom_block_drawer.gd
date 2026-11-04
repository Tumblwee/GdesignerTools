@tool
class_name GDCoreAtomEditorWidgets
extends RefCounted

## 原子创建器窗口、添加原子弹窗、原子区块绘制器、以及原型自定义属性检视器区块
## 对应 AtomBlockDrawer / AtomPickerPopup / AtomCreatorWindow / ArchetypeSOEditor 自定义属性区块

## 1. 「添加原子」弹窗（对应 AtomPickerPopup）
class AtomPickerPopup extends Window:
	signal atom_template_picked(template: GDEntityAtomSystem.AtomTemplateRes)

	var _all_templates: Array[GDEntityAtomSystem.AtomTemplateRes] = []
	var _tab_index: int = 0
	var _search_text: String = ""
	var _search_edit: LineEdit = null
	var _tab_bar: TabBar = null
	var _list_box: VBoxContainer = null

	func _init() -> void:
		title = "添加原子"
		size = Vector2i(440, 480)
		unresizable = false
		close_requested.connect(hide)
		_build_ui()
		reload_templates()

	func _build_ui() -> void:
		var root := VBoxContainer.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		root.add_theme_constant_override("separation", 6)
		add_child(root)

		var top_bar := HBoxContainer.new()
		root.add_child(top_bar)

		_search_edit = LineEdit.new()
		_search_edit.placeholder_text = "搜索原子显示名或脚本名…"
		_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_search_edit.text_changed.connect(func(txt: String) -> void:
			_search_text = txt
			_rebuild_list()
		)
		top_bar.add_child(_search_edit)

		var refresh_btn := Button.new()
		refresh_btn.text = "刷新"
		refresh_btn.pressed.connect(reload_templates)
		top_bar.add_child(refresh_btn)

		_tab_bar = TabBar.new()
		_tab_bar.add_tab("Logic")
		_tab_bar.add_tab("Visual")
		_tab_bar.add_tab("UI")
		_tab_bar.tab_changed.connect(func(idx: int) -> void:
			_tab_index = idx
			_rebuild_list()
		)
		root.add_child(_tab_bar)

		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(scroll)

		_list_box = VBoxContainer.new()
		_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list_box.add_theme_constant_override("separation", 4)
		scroll.add_child(_list_box)
		GDEditorUi.configure_vertical_scroll(scroll, _list_box)

	func reload_templates() -> void:
		_all_templates = GDCliRoot.find_all_atom_templates()
		# 确保内置三大原子模板存在
		_ensure_builtin_templates(_all_templates)
		_rebuild_list()

	static func _ensure_builtin_templates(list: Array[GDEntityAtomSystem.AtomTemplateRes]) -> void:
		var names := {}
		for t in list:
			names[t.atom_script_type_name] = true
		var builtins := [
			{"name": "InteractableAtom", "display": "可交互原子 (InteractableAtom)", "type": GDCoreTypes.AtomType.LOGIC, "desc": "点击/长按交互手势与碰撞盒自动拟合"},
			{"name": "VisualAtom", "display": "表现原子 (VisualAtom)", "type": GDCoreTypes.AtomType.VISUAL, "desc": "表现 Root 子节点与多外观等级切换"},
			{"name": "UIAnchor3DAtom", "display": "3DUI 挂点原子 (UIAnchor3DAtom)", "type": GDCoreTypes.AtomType.LOGIC, "desc": "3DUIRoot 挂点字典查询"},
		]
		for b in builtins:
			if not names.has(b["name"]):
				var tpl := GDEntityAtomSystem.AtomTemplateRes.new()
				tpl.write_metadata(b["display"], b["desc"], b["type"], null, null, b["name"])
				list.append(tpl)

	func _rebuild_list() -> void:
		if _list_box == null:
			return
		GDEditorUi.clear_children(_list_box)

		var any_shown := false
		for tpl in _all_templates:
			if tpl == null or tpl.atom_type != _tab_index:
				continue
			if not _search_text.is_empty():
				var q := _search_text.to_lower()
				if not tpl.display_name.to_lower().contains(q) and not tpl.atom_script_type_name.to_lower().contains(q):
					continue
			any_shown = true
			var row := PanelContainer.new()
			var hbox := HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 8)
			row.add_child(hbox)

			var vbox := VBoxContainer.new()
			vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var title_lbl := Label.new()
			title_lbl.text = tpl.display_name if not tpl.display_name.is_empty() else tpl.atom_script_type_name
			vbox.add_child(title_lbl)

			var sub_lbl := Label.new()
			sub_lbl.text = "脚本：%s" % (tpl.atom_script_type_name if not tpl.atom_script_type_name.is_empty() else "（未绑定）")
			sub_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.72))
			vbox.add_child(sub_lbl)
			hbox.add_child(vbox)

			var add_btn := Button.new()
			add_btn.text = "添加"
			add_btn.disabled = tpl.atom_script_type_name.is_empty()
			var captured := tpl
			add_btn.pressed.connect(func() -> void:
				atom_template_picked.emit(captured)
				hide()
			)
			hbox.add_child(add_btn)
			_list_box.add_child(row)

		if not any_shown:
			var empty_lbl := Label.new()
			empty_lbl.text = "该分类（%s）下没有匹配的 AtomTemplate。" % GDCoreTypes.atom_type_name(_tab_index)
			_list_box.add_child(empty_lbl)


## 2. 原子创建器窗口（对应 AtomCreatorWindow）
class AtomCreatorWindow extends Window:
	var _script_name_edit: LineEdit = null
	var _atom_type_opt: OptionButton = null
	var _display_name_edit: LineEdit = null
	var _desc_edit: LineEdit = null
	var _script_dir_edit: LineEdit = null
	var _template_dir_edit: LineEdit = null
	var _status_label: Label = null

	func _init() -> void:
		title = "原子创建器（脚本 + 模板）"
		size = Vector2i(480, 420)
		close_requested.connect(hide)
		_build_ui()

	func _build_ui() -> void:
		var root := VBoxContainer.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		root.add_theme_constant_override("separation", 6)
		add_child(root)

		var help := Label.new()
		help.text = "原子 = 节点上的脚本（AtomBase）+ 每类型一份 AtomTemplateRes（名字/介绍/Icon）。\n实例配置写在组件字段，不再为每个实例建单独配置资源。"
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(help)

		_script_name_edit = _add_labeled_line_edit(root, "脚本名", "SampleAtom")
		var type_row := HBoxContainer.new()
		var type_lbl := Label.new()
		type_lbl.text = "AtomType"
		type_lbl.custom_minimum_size.x = 110
		type_row.add_child(type_lbl)
		_atom_type_opt = OptionButton.new()
		_atom_type_opt.add_item("Logic", GDCoreTypes.AtomType.LOGIC)
		_atom_type_opt.add_item("Visual", GDCoreTypes.AtomType.VISUAL)
		_atom_type_opt.add_item("UI", GDCoreTypes.AtomType.UI)
		_atom_type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		type_row.add_child(_atom_type_opt)
		root.add_child(type_row)

		_display_name_edit = _add_labeled_line_edit(root, "DisplayName", "Sample 原子")
		_desc_edit = _add_labeled_line_edit(root, "Description", "描述这个原子的作用。")
		_script_dir_edit = _add_labeled_line_edit(root, "脚本目录", "res://project_atoms/scripts")
		_template_dir_edit = _add_labeled_line_edit(root, "模板目录", GDCliRoot.AtomCreator.DEFAULT_TEMP_DIR)

		var create_btn := Button.new()
		create_btn.text = "创建原子"
		create_btn.custom_minimum_size.y = 34
		create_btn.pressed.connect(_do_create)
		root.add_child(create_btn)

		_status_label = Label.new()
		_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(_status_label)

	static func _add_labeled_line_edit(parent: Node, label_text: String, default_val: String) -> LineEdit:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = label_text
		lbl.custom_minimum_size.x = 110
		row.add_child(lbl)
		var edit := LineEdit.new()
		edit.text = default_val
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)
		parent.add_child(row)
		return edit

	func _do_create() -> void:
		var res := GDCliRoot.AtomCreator.create_atom({
			"script_name": _script_name_edit.text,
			"display_name": _display_name_edit.text,
			"description": _desc_edit.text,
			"atom_type": _atom_type_opt.get_selected_id(),
			"script_dir": _script_dir_edit.text,
			"template_dir": _template_dir_edit.text,
		})
		if bool(res.get("ok", false)):
			_status_label.text = "创建成功：%s\n脚本：%s" % [str(res.get("asset_path", "")), str(res.get("script_path", ""))]
			_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		else:
			_status_label.text = "创建失败：%s · %s" % [str(res.get("error_code", "")), str(res.get("error_message", ""))]
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))


## 3. 原型 Inspector 公共区块构建器（供 LevelEditor 与 ActorEditor 共用）
static func build_custom_attributes_inspector(
	parent: VBoxContainer,
	archetype: GDArchetypeRes,
	candidate_bindings: Array[GDEntityAtomSystem.AtomVarTagRegistry.Binding],
	on_changed: Callable
) -> void:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	parent.add_child(panel)

	var header_row := HBoxContainer.new()
	var title_lbl := Label.new()
	title_lbl.text = "自定义属性"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_lbl)

	var add_btn := Button.new()
	add_btn.text = "+ 添加属性"
	add_btn.pressed.connect(func() -> void:
		var new_def := GDCustomAttributeDef.new()
		archetype.custom_attributes.append(new_def)
		archetype.emit_changed()
		if on_changed.is_valid():
			on_changed.call()
	)
	header_row.add_child(add_btn)
	vbox.add_child(header_row)

	if archetype.custom_attributes.is_empty():
		var hint := Label.new()
		hint.text = "尚未配置自定义属性。点「+ 添加属性」，并给条目设置映射标签后，运行时才会覆盖实例原子变量。"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Color(0.68, 0.68, 0.72))
		vbox.add_child(hint)
		return

	# 统计重复标签
	var tag_counts: Dictionary = {}
	for def in archetype.custom_attributes:
		if def != null and not def.tag.strip_edges().is_empty():
			tag_counts[def.tag] = int(tag_counts.get(def.tag, 0)) + 1

	for i in range(archetype.custom_attributes.size()):
		var def := archetype.custom_attributes[i]
		if def == null:
			continue
		var item_panel := PanelContainer.new()
		var item_box := VBoxContainer.new()
		item_box.add_theme_constant_override("separation", 4)
		item_panel.add_child(item_box)
		vbox.add_child(item_panel)

		# 展示名 + 删除按钮
		var top_r := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = "展示名"
		name_lbl.custom_minimum_size.x = 72
		top_r.add_child(name_lbl)
		var name_edit := LineEdit.new()
		name_edit.text = def.display_name
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.text_submitted.connect(func(t: String) -> void:
			def.display_name = t
			archetype.emit_changed()
			if on_changed.is_valid():
				on_changed.call()
		)
		name_edit.focus_exited.connect(func() -> void:
			if def.display_name != name_edit.text:
				def.display_name = name_edit.text
				archetype.emit_changed()
		)
		top_r.add_child(name_edit)

		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.tooltip_text = "移除该自定义属性"
		var idx_captured := i
		del_btn.pressed.connect(func() -> void:
			archetype.custom_attributes.remove_at(idx_captured)
			archetype.emit_changed()
			if on_changed.is_valid():
				on_changed.call()
		)
		top_r.add_child(del_btn)
		item_box.add_child(top_r)

		# 映射标签选择 + 手填
		var tag_r := HBoxContainer.new()
		var tag_lbl := Label.new()
		tag_lbl.text = "映射标签"
		tag_lbl.custom_minimum_size.x = 72
		tag_r.add_child(tag_lbl)

		var tag_edit := LineEdit.new()
		tag_edit.text = def.tag
		tag_edit.placeholder_text = "例如 fog.negative"
		tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tag_edit.text_changed.connect(func(t: String) -> void:
			def.tag = t.strip_edges()
			archetype.emit_changed()
		)
		tag_r.add_child(tag_edit)
		item_box.add_child(tag_r)

		# 值类型
		var vt_r := HBoxContainer.new()
		var vt_lbl := Label.new()
		vt_lbl.text = "值类型"
		vt_lbl.custom_minimum_size.x = 72
		vt_r.add_child(vt_lbl)
		var vt_opt := OptionButton.new()
		vt_opt.add_item("Int", GDCoreTypes.KeywordValueType.INT)
		vt_opt.add_item("Float", GDCoreTypes.KeywordValueType.FLOAT)
		vt_opt.add_item("String", GDCoreTypes.KeywordValueType.STRING)
		vt_opt.add_item("Bool", GDCoreTypes.KeywordValueType.BOOL)
		vt_opt.selected = clampi(def.value_type, 0, 3)
		vt_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vt_opt.item_selected.connect(func(sel_idx: int) -> void:
			def.value_type = sel_idx
			archetype.emit_changed()
			if on_changed.is_valid():
				on_changed.call()
		)
		vt_r.add_child(vt_opt)
		item_box.add_child(vt_r)

		# 默认值
		var def_r := HBoxContainer.new()
		var def_lbl := Label.new()
		def_lbl.text = "默认值"
		def_lbl.custom_minimum_size.x = 72
		def_r.add_child(def_lbl)
		match def.value_type:
			GDCoreTypes.KeywordValueType.INT:
				var sb := SpinBox.new()
				sb.step = 1
				sb.allow_greater = true
				sb.allow_lesser = true
				sb.value = def.default_int
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.value_changed.connect(func(v: float) -> void:
					def.default_int = roundi(v)
					archetype.emit_changed()
				)
				def_r.add_child(sb)
			GDCoreTypes.KeywordValueType.FLOAT:
				var sb := SpinBox.new()
				sb.step = 0.01
				sb.allow_greater = true
				sb.allow_lesser = true
				sb.value = def.default_float
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.value_changed.connect(func(v: float) -> void:
					def.default_float = v
					archetype.emit_changed()
				)
				def_r.add_child(sb)
			GDCoreTypes.KeywordValueType.STRING:
				var se := LineEdit.new()
				se.text = def.default_string
				se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				se.text_changed.connect(func(t: String) -> void:
					def.default_string = t
					archetype.emit_changed()
				)
				def_r.add_child(se)
			GDCoreTypes.KeywordValueType.BOOL:
				var cb := CheckBox.new()
				cb.button_pressed = def.default_bool
				cb.toggled.connect(func(on: bool) -> void:
					def.default_bool = on
					archetype.emit_changed()
				)
				def_r.add_child(cb)
		item_box.add_child(def_r)

		# 警告提示
		if def.tag.strip_edges().is_empty():
			var w := Label.new()
			w.text = "⚠ 未设置映射标签，运行时不会覆盖实例原子变量。"
			w.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
			item_box.add_child(w)
		elif not candidate_bindings.is_empty():
			var matched := false
			for b in candidate_bindings:
				if b.tag == def.tag:
					matched = true
					break
			if not matched:
				var w := Label.new()
				w.text = "⚠ 映射标签「%s」在当前实例 Prefab 的原子上找不到对应变量。" % def.tag
				w.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
				item_box.add_child(w)

		if not def.tag.strip_edges().is_empty() and int(tag_counts.get(def.tag, 0)) > 1:
			var w := Label.new()
			w.text = "⚠ 同一原型内映射标签重复。"
			w.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
			item_box.add_child(w)
