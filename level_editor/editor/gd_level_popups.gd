@tool
class_name GDLevelEditorPopups
extends RefCounted

## 关卡编辑器全套附属弹窗与向导：
## 1. TypeEditPopup (PlacementArchetypeTypeEditPopup：增删改类型、图标选择、枚举生成状态与一键生成)
## 2. ArchetypeCreatorWindow (PlacementArchetypeCreatorWindow：一键创建原型 + Entity Prefab)
## 3. CreateModuleWizardWindow (模块创建向导：三路径必填 + Dry Run)
## 4. ResetInstanceIdPopup (重设实例 ID 弹窗：校验正整数与冲突，自动替换 Name/DisplayName 中的旧 ID)
## 5. LayoutIdMigrationWizardWindow (ID Schema 迁移窗口)

## 1. 编辑建筑/演员原型类型弹窗（LevelEditor 与 ActorEditor 共用）
class TypeEditPopup extends Window:
	signal catalog_changed()

	var _catalog: GDKeywordCatalogSystem.KeywordCatalogRes = null
	var _folder_edit: LineEdit = null
	var _status_label: Label = null
	var _entries_box: VBoxContainer = null
	var _new_internal_edit: LineEdit = null
	var _new_display_edit: LineEdit = null
	var _error_label: Label = null

	func _init() -> void:
		title = "编辑原型类型"
		size = Vector2i(460, 540)
		close_requested.connect(hide)
		_build_ui()

	func bind_catalog(catalog: GDKeywordCatalogSystem.KeywordCatalogRes) -> void:
		_catalog = catalog
		refresh_ui()

	func _build_ui() -> void:
		var root := VBoxContainer.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		root.add_theme_constant_override("separation", 6)
		add_child(root)

		var gen_panel := PanelContainer.new()
		var gen_box := VBoxContainer.new()
		gen_box.add_theme_constant_override("separation", 4)
		gen_panel.add_child(gen_box)
		root.add_child(gen_panel)

		var f_row := HBoxContainer.new()
		var f_lbl := Label.new()
		f_lbl.text = "生成脚本文件夹"
		f_lbl.custom_minimum_size.x = 110
		f_row.add_child(f_lbl)
		_folder_edit = LineEdit.new()
		_folder_edit.placeholder_text = "例如 res://generated/keywords"
		_folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_folder_edit.text_submitted.connect(func(txt: String) -> void:
			if _catalog != null:
				_catalog.editor_set_generated_output_folder(txt)
				refresh_ui()
				catalog_changed.emit()
		)
		f_row.add_child(_folder_edit)
		gen_box.add_child(f_row)

		var status_row := HBoxContainer.new()
		_status_label = Label.new()
		_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_row.add_child(_status_label)

		var regen_btn := Button.new()
		regen_btn.text = "生成枚举"
		regen_btn.pressed.connect(func() -> void:
			if _catalog == null:
				return
			if not _folder_edit.text.strip_edges().is_empty():
				_catalog.editor_set_generated_output_folder(_folder_edit.text)
			if _catalog.enum_type_name.is_empty():
				_catalog.enum_type_name = "GeneratedArchetypeType"
			if _catalog.enum_namespace.is_empty():
				_catalog.enum_namespace = "Project.Keywords"
			if _catalog.regenerate():
				_error_label.text = ""
				refresh_ui()
				catalog_changed.emit()
			else:
				_error_label.text = "生成枚举失败，请检查文件夹路径与标识符。"
		)
		status_row.add_child(regen_btn)
		gen_box.add_child(status_row)

		var list_lbl := Label.new()
		list_lbl.text = "已有类型"
		root.add_child(list_lbl)

		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(scroll)

		_entries_box = VBoxContainer.new()
		_entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_entries_box.add_theme_constant_override("separation", 4)
		scroll.add_child(_entries_box)
		GDEditorUi.configure_vertical_scroll(scroll, _entries_box)

		# 新增类型区
		var add_panel := PanelContainer.new()
		var add_box := VBoxContainer.new()
		add_box.add_theme_constant_override("separation", 4)
		add_panel.add_child(add_box)
		root.add_child(add_panel)

		var add_title := Label.new()
		add_title.text = "新增类型"
		add_box.add_child(add_title)

		_new_internal_edit = LineEdit.new()
		_new_internal_edit.placeholder_text = "类型名（枚举字段，如 FunctionalBuilding，留空自动生成）"
		add_box.add_child(_new_internal_edit)

		_new_display_edit = LineEdit.new()
		_new_display_edit.placeholder_text = "显示名（如 功能建筑）"
		add_box.add_child(_new_display_edit)

		var add_btn := Button.new()
		add_btn.text = "新增"
		add_btn.pressed.connect(_try_add_type)
		add_box.add_child(add_btn)

		_error_label = Label.new()
		_error_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		root.add_child(_error_label)

	func refresh_ui() -> void:
		if _entries_box == null:
			return
		GDEditorUi.clear_children(_entries_box)
		if _catalog == null:
			_status_label.text = "未绑定类型目录"
			return
		_folder_edit.text = _catalog.generated_output_folder
		if _catalog.generated_output_folder.is_empty():
			_status_label.text = "尚未配置生成脚本文件夹（留空不自动生成）"
		elif _catalog.is_enum_up_to_date():
			_status_label.text = "✔ 枚举已是最新（无需生成）"
		else:
			_status_label.text = "⚠ 类型有改动尚未生成枚举"

		for e in _catalog.entries:
			if e == null or e.deprecated:
				continue
			var row := HBoxContainer.new()
			var disp_e := LineEdit.new()
			disp_e.text = e.display_name if not e.display_name.is_empty() else e.entry_name
			disp_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cap_e: GDKeywordCatalogSystem.KeywordEntry = e
			disp_e.text_submitted.connect(func(txt: String) -> void:
				if not txt.strip_edges().is_empty():
					cap_e.editor_set_metadata(txt.strip_edges(), cap_e.description)
					_catalog.emit_changed()
					catalog_changed.emit()
			)
			row.add_child(disp_e)

			var info_lbl := Label.new()
			info_lbl.text = "%s (id=%d)" % [e.entry_name, e.stable_id]
			info_lbl.custom_minimum_size.x = 120
			row.add_child(info_lbl)

			var rm_btn := Button.new()
			rm_btn.text = "✕"
			rm_btn.tooltip_text = "停用该类型（软删，不复用 id）"
			rm_btn.pressed.connect(func() -> void:
				_catalog.remove_entry(cap_e.entry_name)
				refresh_ui()
				catalog_changed.emit()
			)
			row.add_child(rm_btn)
			_entries_box.add_child(row)

	func _try_add_type() -> void:
		if _catalog == null:
			return
		_error_label.text = ""
		var disp := _new_display_edit.text.strip_edges()
		var internal_n := _new_internal_edit.text.strip_edges()
		if internal_n.is_empty():
			internal_n = make_unique_internal_name(_catalog, disp)
		if disp.is_empty():
			disp = internal_n
		var check := GDKeywordCatalogSystem.KeywordIdentifierUtil.validate_identifier(
			internal_n, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.KEYWORD_ENTRY
		)
		if not bool(check.get("ok", false)):
			_error_label.text = "类型名非法：%s" % str(check.get("reason", ""))
			return
		if _catalog.find_active_by_name(internal_n) != null:
			_error_label.text = "已存在同名类型名「%s」。" % internal_n
			return
		_catalog.add_entry(internal_n, disp, "")
		_new_internal_edit.text = ""
		_new_display_edit.text = ""
		refresh_ui()
		catalog_changed.emit()

	static func make_unique_internal_name(catalog: GDKeywordCatalogSystem.KeywordCatalogRes, display: String) -> String:
		var base_name := ""
		for i in range(display.length()):
			var c := display.unicode_at(i)
			if (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57):
				base_name += char(c)
		if base_name.is_empty():
			base_name = "Type"
		elif base_name.unicode_at(0) >= 48 and base_name.unicode_at(0) <= 57:
			base_name = "T" + base_name
		base_name = base_name.substr(0, 1).to_upper() + base_name.substr(1)
		var candidate := base_name
		var suffix := 1
		while catalog.find_any_by_name(candidate) != null:
			suffix += 1
			candidate = "%s%d" % [base_name, suffix]
		return candidate


## 2. 重设实例 ID 弹窗（对应 ResetInstanceIdPopup）
class ResetInstanceIdPopup extends Window:
	signal id_reset_confirmed(new_id: int)

	var _layout: GDLevelSceneRes = null
	var _old_id: int = 0
	var _cur_label: Label = null
	var _input_edit: LineEdit = null
	var _err_label: Label = null
	var _confirm_btn: Button = null

	func _init() -> void:
		title = "重设实例 ID"
		size = Vector2i(340, 170)
		close_requested.connect(hide)
		_build_ui()

	func open_for(layout: GDLevelSceneRes, old_instance_id: int) -> void:
		_layout = layout
		_old_id = old_instance_id
		_cur_label.text = "当前 ID：%d" % old_instance_id
		_input_edit.text = str(old_instance_id)
		_validate_current()
		popup_centered()

	func _build_ui() -> void:
		var root := VBoxContainer.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		root.add_theme_constant_override("separation", 6)
		add_child(root)

		_cur_label = Label.new()
		root.add_child(_cur_label)

		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "新 ID："
		lbl.custom_minimum_size.x = 60
		row.add_child(lbl)
		_input_edit = LineEdit.new()
		_input_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_input_edit.text_changed.connect(func(_t: String) -> void: _validate_current())
		row.add_child(_input_edit)
		root.add_child(row)

		_err_label = Label.new()
		_err_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		root.add_child(_err_label)

		var btn_row := HBoxContainer.new()
		btn_row.alignment = BoxContainer.ALIGNMENT_END
		_confirm_btn = Button.new()
		_confirm_btn.text = "确认"
		_confirm_btn.pressed.connect(_apply_reset)
		btn_row.add_child(_confirm_btn)

		var cancel_btn := Button.new()
		cancel_btn.text = "取消"
		cancel_btn.pressed.connect(hide)
		btn_row.add_child(cancel_btn)
		root.add_child(btn_row)

	func validate_input(raw_text: String) -> Dictionary:
		if raw_text == null or raw_text.strip_edges().is_empty():
			return {"ok": false, "new_id": 0, "error": "请输入一个有效的数字 ID。"}
		var s := raw_text.strip_edges()
		if not s.is_valid_int() or s.to_int() <= 0:
			return {"ok": false, "new_id": 0, "error": "ID 必须是正整数。"}
		var new_id := s.to_int()
		if new_id == _old_id:
			return {"ok": false, "new_id": new_id, "error": "新 ID 与当前 ID 相同。"}
		if _layout != null and bool(_layout.editor_try_get_placement(new_id).get("ok", false)):
			return {"ok": false, "new_id": new_id, "error": "ID %d 已被其它实例占用。" % new_id}
		return {"ok": true, "new_id": new_id, "error": ""}

	func _validate_current() -> void:
		var res := validate_input(_input_edit.text)
		var ok := bool(res.get("ok", false))
		_err_label.text = str(res.get("error", ""))
		_confirm_btn.disabled = not ok

	func _apply_reset() -> void:
		var res := validate_input(_input_edit.text)
		if not bool(res.get("ok", false)) or _layout == null:
			return
		var new_id := int(res.get("new_id", 0))
		apply_reset_to_layout(_layout, _old_id, new_id)
		id_reset_confirmed.emit(new_id)
		hide()

	static func apply_reset_to_layout(layout: GDLevelSceneRes, old_id: int, new_id: int) -> bool:
		if layout == null:
			return false
		var found := layout.editor_try_get_placement(old_id)
		if not bool(found.get("ok", false)):
			return false
		var inst: GDPlacementData.PlacementInstance = found["inst"]
		var old_str := str(old_id)
		var new_str := str(new_id)
		inst.editor_rewrite_instance_id(new_id)
		var n := inst.instance_name
		var d := inst.display_name
		var n_up := n.replace(old_str, new_str) if n.contains(old_str) else n
		var d_up := d.replace(old_str, new_str) if d.contains(old_str) else d
		if n_up != n or d_up != d:
			inst.editor_init_instance_identity(n_up, d_up)
		layout.emit_changed()
		return true
