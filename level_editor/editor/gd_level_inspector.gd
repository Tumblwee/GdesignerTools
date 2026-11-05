@tool
class_name GDLevelInspector
extends RefCounted

## 关卡页的右栏：按选中项搭表单。字段提交走页面的 form.committed，按钮自己提交。
## 路径和相机在撤销后会重建成新对象，所以读写时一律按 ID / 序号重新查找。

const PREVIEW_HEIGHT := 180
const DEFAULT_BOUND_YAW := 45.0
const DEFAULT_BOUND_HALF := Vector2(100.0, 100.0)
const ORTHO := GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC
const PERSPECTIVE := GDCameraPoseSystem.CameraProjectionMode.PERSPECTIVE

var _page: GDLevelPage = null
var _form: GDForm = null


func _init(page: GDLevelPage, form: GDForm) -> void:
	_page = page
	_form = form


var _layout: GDLevelSceneRes:
	get:
		return _page.layout


func show_nothing() -> void:
	_form.clear()
	_form.custom(GDEditorUi.empty_state("没有打开关卡"))


func show_level() -> void:
	var layout := _layout
	if not _form.begin([&"level", layout]):
		return
	_live_heading(func() -> String: return _page.doc_title(layout))
	_form.text("显示名", func() -> String: return layout.display_name, func(value: String) -> void: layout.display_name = value)
	_form.live_note(func() -> String:
		return "%d 个原型 · %d 个实例 · %d 条路径 · %d 个相机" % [layout.archetypes.size(), layout.placements.size(), layout.paths.size(), layout.camera_poses.size()]
	, &"muted")
	_form.live_note(func() -> String:
		return "下一个 ID：实例 %d · 原型 %d · 路径 %d" % [layout.next_instance_id, layout.next_archetype_stable_id, layout.next_path_id]
	, &"muted")


# ── 实例 ──

func show_placement(id: int) -> void:
	if not _page.can_edit_scene() or _page.find_placement(id) == null:
		show_level() if _layout != null else show_nothing()
		return
	var target := _layout
	var archetype := _layout.find_archetype_by_stable_id(_page.find_placement(id).archetype_stable_id)
	var key: Array = [&"placement", target, id, _page.find_placement(id).archetype_stable_id]
	if archetype != null:
		key.append_array(GDArchetypeInspector.structure_key(archetype))
	if not _form.begin(key):
		return
	var inst := func() -> GDPlacementData.PlacementInstance: return target.editor_try_get_placement(id).get("inst")
	_live_heading(func() -> String: return _page.placement_title(inst.call()))
	_add_archetype_choice(id)
	_form.vector3("位置", func() -> Vector3: return inst.call().position, func(v: Vector3) -> void:
		if _can_edit_placement(target, id):
			_set_transform(id, v, inst.call().euler_angles, inst.call().scale, target)
	)
	_form.vector3("旋转", func() -> Vector3: return inst.call().euler_angles, func(v: Vector3) -> void:
		if _can_edit_placement(target, id):
			_set_transform(id, inst.call().position, v, inst.call().scale, target)
	, 1.0)
	_form.vector3("缩放", func() -> Vector3: return inst.call().scale, func(v: Vector3) -> void:
		if _can_edit_placement(target, id):
			_set_transform(id, inst.call().position, inst.call().euler_angles, v, target)
	)
	_form.text("名称", func() -> String: return inst.call().instance_name, func(v: String) -> void:
		if _can_edit_placement(target, id):
			target.editor_replace_placement(id, inst.call().with_name(v))
	)
	_form.text("显示名", func() -> String: return inst.call().display_name, func(v: String) -> void:
		if _can_edit_placement(target, id):
			target.editor_replace_placement(id, inst.call().with_display_name(v))
	)
	_form.integer("等级", func() -> int: return inst.call().initial_level, func(v: int) -> void:
		if _can_edit_placement(target, id):
			target.editor_replace_placement(id, inst.call().with_level(v))
	, {"min": 0})
	if archetype != null:
		_add_overrides(id, archetype)
	_form.group("高级", true)
	_form.text("实例 ID", func() -> String: return str(id), func(_v: String) -> void: pass, {"readonly": true})
	_form.button("重设 ID…", func() -> void: _page.commands.reset_instance_id(id))
	_form.end_group()


func _add_archetype_choice(id: int) -> void:
	var target := _layout
	var items: Array = []
	for archetype: GDArchetypeRes in _layout.archetypes:
		if archetype != null:
			items.append(["%s  #%d" % [archetype.display_name, archetype.stable_id], archetype.stable_id])
	var current := _page.find_placement(id).archetype_stable_id
	if _layout.find_archetype_by_stable_id(current) == null:
		items.append(["（丢失）#%d" % current, current])
	var choice := _form.choice("原型", items,
		func() -> int: return target.editor_try_get_placement(id)["inst"].archetype_stable_id,
		func(stable_id: int) -> void:
			if _can_edit_placement(target, id):
				swap_archetype(target, id, stable_id),
		"也可以把左侧原型拖到这里替换"
	)
	choice.set_drag_forwarding(Callable(),
		func(_at: Vector2, data: Variant) -> bool: return _page.can_edit_scene() and GDLevelSceneDrop.is_payload(data),
		func(_at: Vector2, data: Variant) -> void:
			GDLevelSceneDrop.finish_without_placing()
			if _can_edit_placement(target, id):
				_page.commands.replace_archetype(id, int(data.get("stable_id", 0)))
	)


## 换原型：位置和旋转保留，名称跟随新原型，场景节点重新生成。
static func swap_archetype(layout: GDLevelSceneRes, id: int, stable_id: int) -> bool:
	if Engine.is_editor_hint() and not GDLevelSceneDrop.can_edit(layout):
		return false
	if not layout.editor_replace_placement_archetype(id, stable_id):
		return false
	GDLevelSceneDrop.respawn(layout, id)
	return true


func _set_transform(id: int, pos: Vector3, euler: Vector3, scl: Vector3, target: GDLevelSceneRes = null) -> void:
	if target == null:
		target = _layout
	if not _can_edit_placement(target, id):
		return
	_layout.editor_replace_placement(id, _page.find_placement(id).with_transform(pos, euler, scl))
	GDLevelSceneDrop.apply_transform(id, pos, euler, scl, _layout)


func _can_edit_placement(target: GDLevelSceneRes, id: int) -> bool:
	return _layout == target and _page.can_edit_scene() and _page.find_placement(id) != null


## 每个属性一个字段，显示实例上的值；和原型默认值不同时出现“恢复默认”。
func _add_overrides(id: int, archetype: GDArchetypeRes) -> void:
	_form.group("自定义属性")
	var shown := 0
	for def in archetype.custom_attributes:
		if def != null and not def.tag.strip_edges().is_empty():
			_add_override(id, def)
			shown += 1
	if shown == 0:
		_form.note("原型没有带标签的自定义属性")
	_form.end_group()


func _add_override(id: int, def: GDCustomAttributeDef) -> void:
	var target := _layout
	var caption := def.display_name if not def.display_name.is_empty() else def.tag
	var read := func() -> Variant: return _override_value(target.editor_try_get_placement(id).get("inst"), def)
	var write := func(value: Variant) -> void: _write_override(id, def, value, target)
	var field: Control = null
	match def.value_type:
		GDCoreTypes.KeywordValueType.INT:
			field = _form.integer(caption, read, write)
		GDCoreTypes.KeywordValueType.FLOAT:
			field = _form.number(caption, read, write, {"step": 0.01})
		GDCoreTypes.KeywordValueType.BOOL:
			field = _form.toggle(caption, read, write)
		_:
			field = _form.text(caption, read, write)
	var reset := GDEditorUi.tool_button(&"Reload", "恢复默认值 %s" % str(_default_of(def)), func() -> void:
		if not _can_edit_placement(target, id):
			return
		_write_override(id, def, _default_of(def), target)
		_page.doc.commit("恢复默认值")
	)
	field.get_parent().add_child(reset)
	_form.on_sync(func() -> void:
		var overridden := _is_overridden(_page.find_placement(id), def)
		reset.disabled = not overridden
		reset.modulate.a = 1.0 if overridden else 0.0
	)


static func _default_of(def: GDCustomAttributeDef) -> Variant:
	return GDPlacementData.PlacementAttributeOverride.from_custom_attribute_def(def).get_boxed()


static func _override_value(inst: GDPlacementData.PlacementInstance, def: GDCustomAttributeDef) -> Variant:
	for ov in inst.attribute_overrides:
		if ov != null and ov.tag == def.tag:
			return ov.get_boxed()
	return _default_of(def)


static func _is_overridden(inst: GDPlacementData.PlacementInstance, def: GDCustomAttributeDef) -> bool:
	var value: Variant = _override_value(inst, def)
	var fallback: Variant = _default_of(def)
	return not is_equal_approx(value, fallback) if value is float else value != fallback


## 运行时只读实例上的覆盖值，所以“恢复默认”是写回默认值，而不是删掉这一条。
func _write_override(id: int, def: GDCustomAttributeDef, value: Variant, target: GDLevelSceneRes = null) -> void:
	if target == null:
		target = _layout
	if not _can_edit_placement(target, id):
		return
	var inst := _page.find_placement(id)
	var made: GDPlacementData.PlacementAttributeOverride = null
	match def.value_type:
		GDCoreTypes.KeywordValueType.INT:
			made = GDPlacementData.PlacementAttributeOverride.of_int(def.tag, int(value))
		GDCoreTypes.KeywordValueType.FLOAT:
			made = GDPlacementData.PlacementAttributeOverride.of_float(def.tag, float(value))
		GDCoreTypes.KeywordValueType.BOOL:
			made = GDPlacementData.PlacementAttributeOverride.of_bool(def.tag, bool(value))
		_:
			made = GDPlacementData.PlacementAttributeOverride.of_string(def.tag, str(value))
	var overrides: Array = inst.attribute_overrides.filter(func(ov: Variant) -> bool: return ov != null and ov.tag != def.tag)
	overrides.append(made)
	_layout.editor_replace_placement(id, inst.with_overrides(overrides))


# ── 原型 ──

func show_archetype(archetype: GDArchetypeRes) -> void:
	if not _form.begin([&"archetype"] + GDArchetypeInspector.structure_key(archetype)):
		return
	GDArchetypeInspector.add_identity(_form, archetype, _layout.placement_archetype_type_keywords)
	GDArchetypeInspector.add_override(_form, archetype, _layout.archetypes)
	var preview := GDArchetypePreviewPanel.new()
	preview.custom_minimum_size.y = PREVIEW_HEIGHT
	preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_form.custom(preview)
	_form.on_sync(func() -> void: preview.show_archetype(archetype))
	GDArchetypeInspector.add_addresses(_form, archetype)
	GDArchetypeInspector.add_custom_attributes(_form, archetype, func(label: String) -> void: _page.doc.commit(label))
	_form.group("实例 ID 段", true)
	_form.toggle("自定义 ID 段",
		func() -> bool: return archetype.use_custom_instance_id_range,
		func(on: bool) -> void: archetype.editor_set_custom_instance_id_range(on, archetype.instance_id_min, archetype.instance_id_max),
		"开启后，这个原型的新实例只从下面的区间里取 ID"
	)
	_form.integer("最小", func() -> int: return archetype.instance_id_min,
		func(v: int) -> void: archetype.editor_set_custom_instance_id_range(archetype.use_custom_instance_id_range, v, archetype.instance_id_max), {"min": 0})
	_form.integer("最大", func() -> int: return archetype.instance_id_max,
		func(v: int) -> void: archetype.editor_set_custom_instance_id_range(archetype.use_custom_instance_id_range, archetype.instance_id_min, v), {"min": 0})
	_form.live_note(func() -> String:
		if not archetype.use_custom_instance_id_range:
			return ""
		return str(GDPlacementData.PlacementInstanceIdRangeLogic.try_validate_custom_range(archetype.instance_id_min, archetype.instance_id_max).get("error", ""))
	)
	var standardize := _form.button("标准化实例 ID", func() -> void: _page.commands.standardize_instance_ids(archetype))
	standardize.tooltip_text = "把这个原型的实例按顺序重新编号到 ID 段的开头"
	_form.on_sync(func() -> void: standardize.disabled = not archetype.has_valid_custom_instance_id_range)
	_form.end_group()


# ── 路径 ──

func show_path(id: int) -> void:
	if not _page.can_edit_scene() or _page.find_path(id) == null:
		show_level() if _layout != null else show_nothing()
		return
	var target := _layout
	if not _form.begin([&"path", target, id, _page.find_path(id).knot_count]):
		return
	var path := func() -> GDPathSystem.PathInstance: return target.editor_try_get_path(id).get("path")
	var edit := func(change: Callable) -> void:
		if _layout == target and _page.can_edit_scene() and path.call() != null:
			target.editor_replace_path(id, change.call(path.call()))
	_live_heading(func() -> String: return GDLevelPage.path_title(path.call()))
	_form.text("显示名", func() -> String: return path.call().display_name, func(v: String) -> void: edit.call(func(p: GDPathSystem.PathInstance) -> GDPathSystem.PathInstance: return p.with_display_name(v)))
	var write_type := func(v: int) -> void: edit.call(func(p: GDPathSystem.PathInstance) -> GDPathSystem.PathInstance: return p.with_path_type(v))
	if _layout.path_type_keywords != null:
		_form.choice("类型", GDArchetypeInspector.type_items(_layout.path_type_keywords), func() -> int: return path.call().path_type_keyword, write_type)
	else:
		_form.integer("类型", func() -> int: return path.call().path_type_keyword, write_type, {"min": 0, "tip": "路径类型关键字 ID"})
	_form.number("速度", func() -> float: return path.call().speed, func(v: float) -> void: edit.call(func(p: GDPathSystem.PathInstance) -> GDPathSystem.PathInstance: return p.with_speed(v)), {"min": 0.0, "step": 0.1, "suffix": "m/s"})
	_form.toggle("闭环", func() -> bool: return path.call().closed, func(on: bool) -> void: edit.call(func(p: GDPathSystem.PathInstance) -> GDPathSystem.PathInstance: return p.with_closed(on)))
	_form.live_note(func() -> String: return "%d 个节点 · 全长 %.2f 米" % [path.call().knot_count, path.call().spline.get_length()], &"muted")
	_add_probe(id)
	_form.group("节点")
	for k in range(_page.find_path(id).knot_count):
		_add_knot(_form.nested(), id, k)
	_form.button("添加节点", func() -> void: _add_knot_at_end(id))
	_form.end_group()


## 采样预览只在平面图上画一个点，不改数据。
func _add_probe(id: int) -> void:
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.01
	var readout := GDEditorUi.muted_label("")
	var update := func(show_marker: bool) -> void:
		var spline := _page.find_path(id).spline
		var at := spline.evaluate_position(slider.value)
		readout.text = "t = %.2f    (%.2f, %.2f, %.2f)" % [slider.value, at.x, at.y, at.z]
		if show_marker:
			_page.set_probe(Vector2(at.x, at.z))
	slider.value_changed.connect(func(_t: float) -> void: update.call(true))
	_form.row("采样预览", slider, "拖动查看路径上 t 处的位置，不会保存")
	_form.custom(readout)
	_form.on_sync(func() -> void: update.call(_page.has_probe()))


func _add_knot(form: GDForm, id: int, k: int) -> void:
	var target := _layout
	var title := HBoxContainer.new()
	title.add_child(GDEditorUi.title_label("节点 %d" % (k + 1)))
	var remove := GDEditorUi.tool_button(&"Remove", "删除节点", func() -> void:
		if _layout != target or not _page.can_edit_scene():
			return
		var spline := _page.find_path(id).spline.clone_spline()
		spline.knots.remove_at(k)
		_layout.editor_replace_path(id, _page.find_path(id).with_spline(spline))
		_page.doc.commit("删除路径节点")
	)
	remove.disabled = _page.find_path(id).knot_count <= 2
	title.add_child(remove)
	form.custom(title)
	for field: Array in [[&"position", "位置"], [&"tangent_in", "入切线"], [&"tangent_out", "出切线"]]:
		if field[0] == &"tangent_in":
			form.group("切线", true)
		form.vector3(field[1],
			func() -> Vector3: return _page.find_path(id).spline.knots[k].get(field[0]),
			func(v: Vector3) -> void:
				if _layout == target and _page.can_edit_scene():
					set_knot(target, id, k, field[0], v)
		)
	form.end_group()


func _add_knot_at_end(id: int) -> void:
	if not _page.can_edit_scene() or _page.find_path(id) == null:
		return
	var path := _page.find_path(id)
	var spline := path.spline.clone_spline()
	var last: Vector3 = spline.knots[-1].position if not spline.knots.is_empty() else Vector3.ZERO
	var step := Vector3(2, 0, 0)
	if spline.knots.size() >= 2:
		var dir := last - spline.knots[-2].position
		step = dir.normalized() * 2.0 if dir.length() > 0.01 else step
	spline.add_knot(GDPathSystem.SplineKnot.new(last + step))
	_layout.editor_replace_path(id, path.with_spline(spline))
	_page.doc.commit("添加路径节点")


static func set_knot(layout: GDLevelSceneRes, id: int, k: int, field: StringName, value: Vector3) -> void:
	var path: GDPathSystem.PathInstance = layout.editor_try_get_path(id)["path"]
	var spline := path.spline.clone_spline()
	spline.knots[k].set(field, value)
	layout.editor_replace_path(id, path.with_spline(spline))


# ── 相机 ──

func show_camera(index: int) -> void:
	if not _page.can_edit_scene() or _page.find_pose(index) == null:
		show_level() if _layout != null else show_nothing()
		return
	var target := _layout
	var pose := _page.find_pose(index)
	if not _form.begin([&"camera", target, index, pose.projection, pose.has_initial_zoom, pose.has_bound, pose.has_bound_edges]):
		return
	var get_pose := func() -> GDCameraPoseSystem.CameraPose: return target.editor_try_get_camera_pose(index).get("pose")
	var edit := func(change: Callable) -> void:
		if _layout == target and _page.can_edit_scene() and get_pose.call() != null:
			target.editor_replace_camera_pose_at(index, change.call(get_pose.call()))
	_live_heading(func() -> String: return get_pose.call().display_name)
	_form.text("显示名", func() -> String: return get_pose.call().display_name, func(v: String) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_display_name(v)))
	_form.text("名称", func() -> String: return get_pose.call().pose_name, func(v: String) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_name(v)), {"tip": "运行时按这个名字取机位"})
	_form.choice("投影", [["透视", PERSPECTIVE], ["正交", ORTHO]], func() -> int: return get_pose.call().projection, func(v: int) -> void:
		var plane := GDCameraPoseSystem.CameraBoundPlane.XY if v == ORTHO else GDCameraPoseSystem.CameraBoundPlane.XZ
		edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_projection(v).with_bound_plane(plane))
	)
	if pose.projection == ORTHO:
		_form.number("最小尺寸", func() -> float: return get_pose.call().orthographic_min_size,
			func(v: float) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_orthographic_zoom_range(v, p.orthographic_max_size)), {"min": 0.0, "step": 0.1})
		_form.number("最大尺寸", func() -> float: return get_pose.call().orthographic_max_size,
			func(v: float) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_orthographic_zoom_range(p.orthographic_min_size, v)), {"min": 0.0, "step": 0.1})
	else:
		_form.number("FOV", func() -> float: return get_pose.call().fov,
			func(v: float) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_pose(p.position, p.euler_angles, v)), {"min": 1.0, "max": 179.0, "step": 0.5, "suffix": "°"})
		_form.number("最近距离", func() -> float: return get_pose.call().zoom_min_distance,
			func(v: float) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_zoom_range(v, p.zoom_max_distance)), {"min": 0.0, "step": 0.1})
		_form.number("最远距离", func() -> float: return get_pose.call().zoom_max_distance,
			func(v: float) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_zoom_range(p.zoom_min_distance, v)), {"min": 0.0, "step": 0.1})
		_form.number("聚焦距离", func() -> float: return get_pose.call().click_focus_zoom_distance,
			func(v: float) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_click_focus_zoom_distance(v)), {"min": 0.0, "step": 0.1, "tip": "点击物体时镜头拉近到的距离"})
	_form.vector3("位置", func() -> Vector3: return get_pose.call().position,
		func(v: Vector3) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_pose(v, p.euler_angles, p.fov)))
	_form.vector3("旋转", func() -> Vector3: return get_pose.call().euler_angles,
		func(v: Vector3) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_pose(p.position, v, p.fov)), 1.0)
	_form.toggle("初始缩放", func() -> bool: return get_pose.call().has_initial_zoom, func(on: bool) -> void:
		edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose:
			return p.with_initial_zoom(GDCameraPoseSystem.CameraPose.DEFAULT_INITIAL_ZOOM_01) if on else p.without_initial_zoom())
	)
	if pose.has_initial_zoom:
		_form.number("缩放比例", func() -> float: return get_pose.call().initial_zoom_01,
			func(v: float) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_initial_zoom(v)), {"min": 0.0, "max": 1.0, "step": 0.01, "tip": "0 最近，1 最远"})
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", GDEditorUi.GAP)
	for button: Button in [
		GDEditorUi.text_button("从主相机刷新", func() -> void: _refresh_from_view(index)),
		GDEditorUi.text_button("应用到主相机", func() -> void: _page.commands.apply_camera(index)),
	]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	_form.custom(actions)
	_add_bound(index, pose, edit)


func _add_bound(index: int, pose: GDCameraPoseSystem.CameraPose, edit: Callable) -> void:
	var get_pose := func() -> GDCameraPoseSystem.CameraPose: return _page.find_pose(index)
	_form.group("活动边界", not pose.has_bound)
	_form.toggle("启用边界", func() -> bool: return get_pose.call().has_bound, func(on: bool) -> void:
		edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return default_bound(p) if on else p.without_bound())
	)
	if pose.has_bound and pose.has_bound_edges:
		for edge: Array in [["左", 0], ["右", 1], ["下", 2], ["上", 3]]:
			_form.number(edge[0], func() -> float: return _edges(get_pose.call())[edge[1]], func(v: float) -> void:
				edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose:
					var edges := _edges(p)
					edges[edge[1]] = v
					return p.with_bound_edges(edges[0], edges[1], edges[2], edges[3]))
			, {"step": 0.5})
		_form.live_note(func() -> String:
			var p: GDCameraPoseSystem.CameraPose = get_pose.call()
			return "左要小于右，下要小于上" if p.bound_left >= p.bound_right or p.bound_bottom >= p.bound_top else ""
		, &"danger")
	elif pose.has_bound:
		_form.vector2("中心", func() -> Vector2: return get_pose.call().bound_center,
			func(v: Vector2) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_bound(v, p.bound_yaw_deg, p.bound_half_extents)))
		_form.number("朝向", func() -> float: return get_pose.call().bound_yaw_deg,
			func(v: float) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_bound(p.bound_center, v, p.bound_half_extents)), {"step": 1.0, "suffix": "°"})
		_form.vector2("半宽 / 半长", func() -> Vector2: return get_pose.call().bound_half_extents,
			func(v: Vector2) -> void: edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return p.with_bound(p.bound_center, p.bound_yaw_deg, v)))
	_form.button("初始化默认边界", func() -> void:
		if not _page.can_edit_scene():
			return
		edit.call(func(p: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose: return default_bound(p))
		_page.doc.commit("初始化默认边界")
	)
	_form.end_group()


static func _edges(pose: GDCameraPoseSystem.CameraPose) -> Array[float]:
	return [pose.bound_left, pose.bound_right, pose.bound_bottom, pose.bound_top]


## 透视相机在 XZ 平面上取以机位为中心的旋转矩形；正交相机在 XY 平面上取四条边。
static func default_bound(pose: GDCameraPoseSystem.CameraPose) -> GDCameraPoseSystem.CameraPose:
	if pose.projection == ORTHO:
		var center := Vector2(pose.position.x, pose.position.y)
		return pose.with_bound_edges(center.x - DEFAULT_BOUND_HALF.x, center.x + DEFAULT_BOUND_HALF.x, center.y - DEFAULT_BOUND_HALF.y, center.y + DEFAULT_BOUND_HALF.y)
	return pose.with_bound(Vector2(pose.position.x, pose.position.z), DEFAULT_BOUND_YAW, DEFAULT_BOUND_HALF).with_bound_plane(GDCameraPoseSystem.CameraBoundPlane.XZ)


func _refresh_from_view(index: int) -> void:
	if not _page.can_edit_scene() or _page.find_pose(index) == null:
		return
	var camera := viewport_camera()
	if camera == null:
		_page.say("没有可用的 3D 视口", &"warn")
		return
	_layout.editor_replace_camera_pose_at(index, pose_from_camera(_page.find_pose(index), camera))
	_page.doc.commit("从主相机刷新")


## 编辑器 3D 视口当前的相机；不在编辑器里时为 null。
static func viewport_camera() -> Camera3D:
	if not Engine.is_editor_hint():
		return null
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	return viewport.get_camera_3d() if viewport != null else null


## 当前场景里的 Camera3D，优先取 current 的那个。
static func scene_camera() -> Camera3D:
	var root := GDLevelSceneDrop.edited_root()
	if root == null:
		return null
	var cameras := root.find_children("*", "Camera3D", true, false)
	if root is Camera3D:
		cameras.push_front(root)
	for camera: Camera3D in cameras:
		if camera.current:
			return camera
	return cameras[0] if not cameras.is_empty() else null


static func pose_from_camera(pose: GDCameraPoseSystem.CameraPose, camera: Camera3D) -> GDCameraPoseSystem.CameraPose:
	var updated := pose.with_pose(camera.global_position, camera.global_rotation_degrees, camera.fov)
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return updated.with_projection(ORTHO).with_orthographic_zoom_range(camera.size, camera.size).with_bound_plane(GDCameraPoseSystem.CameraBoundPlane.XY)
	return updated.with_projection(PERSPECTIVE)


static func apply_pose(pose: GDCameraPoseSystem.CameraPose, camera: Camera3D) -> void:
	camera.global_position = pose.position
	camera.global_rotation_degrees = pose.euler_angles
	if pose.projection == ORTHO:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		var low := pose.orthographic_min_size if pose.has_orthographic_zoom else camera.size
		var high := pose.orthographic_max_size if pose.has_orthographic_zoom else low
		camera.size = lerpf(low, high, pose.initial_zoom_01)
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = pose.fov
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _live_heading(read: Callable) -> void:
	var title := GDEditorUi.title_label("")
	_form.custom(title)
	_form.on_sync(func() -> void: title.text = str(read.call()))
