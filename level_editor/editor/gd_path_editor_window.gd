@tool
class_name GDPathEditorWindow
extends Window

## 路径编辑工作窗口（对应 TimiMiniGame.SceneEditor.Editor.Scene.PathEditorWindow）
## 支持：+ 新建路径、删除选中、聚焦 (F)、从关卡场景重建、保存；
## 属性面板：显示名、类型 (keyword id / PathTypeKeywords 下拉)、速度 (m/s)、闭环、节点数、总长、采样预览 + 采样 t 滑条、节点列表增删改。

var _layout: GDLevelSceneRes = null
var _selected_path_id: int = 0
var _preview_enabled: bool = false
var _preview_t: float = 0.0

var _list_box: VBoxContainer = null
var _inspector_box: VBoxContainer = null
var _path_count_label: Label = null
var _status_label: Label = null

func _init() -> void:
	title = GDSceneEditorL10n.l("路径编辑器")
	size = Vector2i(460, 560)
	close_requested.connect(hide)
	_build_ui()

func bind_layout(layout: GDLevelSceneRes) -> void:
	_layout = layout
	if _layout != null and not _layout.paths.is_empty() and _selected_path_id <= 0:
		_selected_path_id = _layout.paths[0].path_id
	refresh_ui()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 顶部工具栏
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 4)
	root.add_child(toolbar)

	var new_btn := Button.new()
	new_btn.text = "+ 新建路径"
	new_btn.tooltip_text = "在 Path Root 下创建一条 2 节点默认路径"
	new_btn.pressed.connect(create_new_path)
	toolbar.add_child(new_btn)

	var del_btn := Button.new()
	del_btn.text = "删除选中"
	del_btn.pressed.connect(delete_selected)
	toolbar.add_child(del_btn)

	var focus_btn := Button.new()
	focus_btn.text = "聚焦 (F)"
	focus_btn.pressed.connect(func() -> void:
		if _status_label != null and _selected_path_id > 0:
			_status_label.text = "已聚焦路径 #%d" % _selected_path_id
	)
	toolbar.add_child(focus_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var rebuild_btn := Button.new()
	rebuild_btn.text = "从关卡场景重建"
	rebuild_btn.pressed.connect(refresh_ui)
	toolbar.add_child(rebuild_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(save_layout)
	toolbar.add_child(save_btn)

	_path_count_label = Label.new()
	_path_count_label.text = "路径 (0)"
	root.add_child(_path_count_label)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size.y = 140
	root.add_child(list_scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 3)
	list_scroll.add_child(_list_box)
	GDEditorUi.configure_vertical_scroll(list_scroll, _list_box)

	var insp_scroll := ScrollContainer.new()
	insp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(insp_scroll)

	_inspector_box = VBoxContainer.new()
	_inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_box.add_theme_constant_override("separation", 6)
	insp_scroll.add_child(_inspector_box)
	GDEditorUi.configure_vertical_scroll(insp_scroll, _inspector_box)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.65))
	root.add_child(_status_label)

func create_new_path() -> int:
	if _layout == null:
		return 0
	var pid := _layout.editor_add_path(0, GDPathSystem.SplineData.build_default_spline(), 1.0)
	_selected_path_id = pid
	refresh_ui()
	return pid

func delete_selected() -> bool:
	if _layout == null or _selected_path_id <= 0:
		return false
	var ok := _layout.editor_remove_path(_selected_path_id)
	_selected_path_id = _layout.paths[0].path_id if not _layout.paths.is_empty() else 0
	refresh_ui()
	return ok

func save_layout() -> void:
	if _layout == null:
		return
	if not _layout.resource_path.is_empty():
		ResourceSaver.save(_layout, _layout.resource_path)
	if _status_label != null:
		_status_label.text = "路径已保存"

func refresh_ui() -> void:
	if _list_box == null or _inspector_box == null:
		return
	GDEditorUi.clear_children(_list_box)
	GDEditorUi.clear_children(_inspector_box)

	if _layout == null:
		_path_count_label.text = "未绑定 Layout。请在关卡编辑器打开一个关卡场景。"
		return

	_path_count_label.text = "路径 (%d)" % _layout.paths.size()
	for inst in _layout.paths:
		if inst == null:
			continue
		var row := HBoxContainer.new()
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var closed_tag := " · 闭环" if inst.closed else ""
		btn.text = "%s%s  ·  %d 节点%s" % [
			"▶ " if inst.path_id == _selected_path_id else "",
			inst.display_name,
			inst.knot_count,
			closed_tag
		]
		var captured_id: int = inst.path_id
		btn.pressed.connect(func() -> void:
			_selected_path_id = captured_id
			refresh_ui()
		)
		row.add_child(btn)

		var id_lbl := Label.new()
		id_lbl.text = "#%d" % inst.path_id
		id_lbl.custom_minimum_size.x = 60
		row.add_child(id_lbl)
		_list_box.add_child(row)

	var found := _layout.editor_try_get_path(_selected_path_id)
	if not bool(found.get("ok", false)):
		var hint := Label.new()
		hint.text = "从上方列表选中一条路径以编辑其属性。"
		_inspector_box.add_child(hint)
		return

	var path_inst: GDPathSystem.PathInstance = found["path"]
	_build_selected_path_inspector(path_inst)

func _build_selected_path_inspector(inst: GDPathSystem.PathInstance) -> void:
	var header := Label.new()
	header.text = "属性 · #%d" % inst.path_id
	_inspector_box.add_child(header)

	# 显示名
	var disp_row := HBoxContainer.new()
	var disp_lbl := Label.new()
	disp_lbl.text = "显示名"
	disp_lbl.custom_minimum_size.x = 110
	disp_row.add_child(disp_lbl)
	var disp_edit := LineEdit.new()
	disp_edit.text = inst.display_name
	disp_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disp_edit.text_submitted.connect(func(txt: String) -> void:
		_layout.editor_replace_path(inst.path_id, inst.with_display_name(txt))
		refresh_ui()
	)
	disp_row.add_child(disp_edit)
	_inspector_box.add_child(disp_row)

	# 路径类型
	var type_row := HBoxContainer.new()
	var type_lbl := Label.new()
	type_lbl.text = "类型 (keyword id)"
	type_lbl.custom_minimum_size.x = 110
	type_row.add_child(type_lbl)
	var type_spin := SpinBox.new()
	type_spin.step = 1
	type_spin.min_value = 0
	type_spin.max_value = 99999
	type_spin.value = inst.path_type_keyword
	type_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_spin.value_changed.connect(func(v: float) -> void:
		_layout.editor_replace_path(inst.path_id, inst.with_path_type(roundi(v)))
	)
	type_row.add_child(type_spin)
	_inspector_box.add_child(type_row)

	# 速度
	var spd_row := HBoxContainer.new()
	var spd_lbl := Label.new()
	spd_lbl.text = "速度 (m/s)"
	spd_lbl.custom_minimum_size.x = 110
	spd_row.add_child(spd_lbl)
	var spd_spin := SpinBox.new()
	spd_spin.step = 0.1
	spd_spin.min_value = 0.0
	spd_spin.max_value = 1000.0
	spd_spin.value = inst.speed
	spd_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spd_spin.value_changed.connect(func(v: float) -> void:
		_layout.editor_replace_path(inst.path_id, inst.with_speed(maxf(0.0, v)))
	)
	spd_row.add_child(spd_spin)
	_inspector_box.add_child(spd_row)

	# 闭环
	var closed_cb := CheckBox.new()
	closed_cb.text = "闭环"
	closed_cb.button_pressed = inst.closed
	closed_cb.toggled.connect(func(on: bool) -> void:
		_layout.editor_replace_path(inst.path_id, inst.with_closed(on))
		refresh_ui()
	)
	_inspector_box.add_child(closed_cb)

	# 只读统计：节点数与总长
	var length_val := inst.spline.get_length() if inst.spline != null else 0.0
	var info_lbl := Label.new()
	info_lbl.text = "节点数：%d    总长：%.2f m" % [inst.knot_count, length_val]
	_inspector_box.add_child(info_lbl)

	# 采样预览
	var prev_cb := CheckBox.new()
	prev_cb.text = "采样预览"
	prev_cb.disabled = inst.knot_count < 2
	prev_cb.button_pressed = _preview_enabled
	prev_cb.toggled.connect(func(on: bool) -> void:
		_preview_enabled = on
		refresh_ui()
	)
	_inspector_box.add_child(prev_cb)

	if _preview_enabled and inst.spline != null and inst.knot_count >= 2:
		var t_row := HBoxContainer.new()
		var t_lbl := Label.new()
		t_lbl.text = "采样 t (%.2f)" % _preview_t
		t_lbl.custom_minimum_size.x = 110
		t_row.add_child(t_lbl)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = _preview_t
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sample_out := Label.new()
		var update_sample := func(tv: float) -> void:
			_preview_t = tv
			t_lbl.text = "采样 t (%.2f)" % tv
			var p := inst.spline.evaluate_position(tv)
			var tan := inst.spline.evaluate_tangent(tv)
			sample_out.text = "采样点：(%.2f, %.2f, %.2f)  切线：(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z, tan.x, tan.y, tan.z]
		update_sample.call(_preview_t)
		slider.value_changed.connect(update_sample)
		t_row.add_child(slider)
		_inspector_box.add_child(t_row)
		_inspector_box.add_child(sample_out)

	# 节点列表编辑
	var knot_hdr := HBoxContainer.new()
	var kh_lbl := Label.new()
	kh_lbl.text = "曲线节点 (Knots)"
	kh_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	knot_hdr.add_child(kh_lbl)
	var add_knot_btn := Button.new()
	add_knot_btn.text = "+ 添加节点"
	add_knot_btn.pressed.connect(func() -> void:
		var sp := inst.spline.clone_spline()
		var last_pos := sp.knots[sp.knots.size() - 1].position if not sp.knots.is_empty() else Vector3.ZERO
		sp.add_knot(GDPathSystem.SplineKnot.new(last_pos + Vector3(2.0, 0.0, 0.0)))
		_layout.editor_replace_path(inst.path_id, inst.with_spline(sp))
		refresh_ui()
	)
	knot_hdr.add_child(add_knot_btn)
	_inspector_box.add_child(knot_hdr)

	if inst.spline != null:
		for k_idx in range(inst.spline.knots.size()):
			var knot := inst.spline.knots[k_idx]
			if knot == null:
				continue
			var kr := HBoxContainer.new()
			var kl := Label.new()
			kl.text = "#%d (%.1f, %.1f, %.1f)" % [k_idx, knot.position.x, knot.position.y, knot.position.z]
			kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			kr.add_child(kl)
			var rm_k := Button.new()
			rm_k.text = "×"
			var cap_k := k_idx
			rm_k.pressed.connect(func() -> void:
				var sp := inst.spline.clone_spline()
				sp.knots.remove_at(cap_k)
				_layout.editor_replace_path(inst.path_id, inst.with_spline(sp))
				refresh_ui()
			)
			kr.add_child(rm_k)
			_inspector_box.add_child(kr)
