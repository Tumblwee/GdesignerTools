@tool
class_name GDCameraPoseEditorWindow
extends Window

## 相机机位配置窗口（对应 TimiMiniGame.SceneEditor.Editor.Scene.CameraPoseEditorWindow）
## 支持：记录当前主相机机位、从关卡场景重建、保存；
## 每条机位：聚焦 (F)、删除、显示名、名称(name)、投影模式 (Perspective/Orthographic)、
## 位置/旋转/FOV、同步主相机当前机位、将当前机位同步到主相机、
## 透视/正交缩放范围 + 点击聚焦距离 + 启用初始 zoom (0..1)、
## 活动边界 XZ (中心/旋转角/半宽半长/同步中心) 与 XY (Left/Right/Bottom/Top/转换四边)。

const DEFAULT_BOUND_YAW_DEG := 45.0
const DEFAULT_BOUND_HALF_EXTENTS := Vector2(100.0, 100.0)

var _layout: GDLevelSceneRes = null
var _list_box: VBoxContainer = null
var _pose_count_label: Label = null
var _status_label: Label = null

## 可选注入的主相机位姿提供器（编辑器 / 测试可注入虚拟主相机）
var main_camera_pos: Vector3 = Vector3(0.0, 15.0, -15.0)
var main_camera_euler: Vector3 = Vector3(-45.0, 0.0, 0.0)
var main_camera_fov: float = 60.0
var main_camera_orthographic: bool = false
var main_camera_ortho_size: float = 12.0

func _init() -> void:
	title = GDSceneEditorL10n.l("相机配置")
	size = Vector2i(500, 620)
	close_requested.connect(hide)
	_build_ui()

func bind_layout(layout: GDLevelSceneRes) -> void:
	_layout = layout
	refresh_ui()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 4)
	root.add_child(toolbar)

	var rec_btn := Button.new()
	rec_btn.text = "记录当前主相机机位"
	rec_btn.pressed.connect(record_current_main_camera)
	toolbar.add_child(rec_btn)

	var rebuild_btn := Button.new()
	rebuild_btn.text = "从关卡场景重建"
	rebuild_btn.pressed.connect(refresh_ui)
	toolbar.add_child(rebuild_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(save_layout)
	toolbar.add_child(save_btn)

	_pose_count_label = Label.new()
	_pose_count_label.text = "相机机位 (0)"
	root.add_child(_pose_count_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_box)
	GDEditorUi.configure_vertical_scroll(scroll, _list_box)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.65))
	root.add_child(_status_label)

func record_current_main_camera() -> int:
	if _layout == null:
		return -1
	var index := _layout.camera_poses.size()
	var disp := "相机 #%d" % index
	var pname := "Camera_%d" % index
	var added_idx := _layout.editor_add_camera_pose(pname, disp, main_camera_pos, main_camera_euler, main_camera_fov)
	if main_camera_orthographic:
		var got := _layout.editor_try_get_camera_pose(added_idx)
		if bool(got.get("ok", false)):
			var p: GDCameraPoseSystem.CameraPose = got["pose"]
			var updated := p.with_projection(GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC) \
				.with_orthographic_zoom_range(main_camera_ortho_size, main_camera_ortho_size) \
				.with_bound_plane(GDCameraPoseSystem.CameraBoundPlane.XY)
			_layout.editor_replace_camera_pose_at(added_idx, updated)
	refresh_ui()
	return added_idx

func refresh_pose_from_main_camera(index: int) -> void:
	if _layout == null:
		return
	var got := _layout.editor_try_get_camera_pose(index)
	if not bool(got.get("ok", false)):
		return
	var src: GDCameraPoseSystem.CameraPose = got["pose"]
	var updated := src.with_pose(main_camera_pos, main_camera_euler, main_camera_fov)
	if main_camera_orthographic:
		updated = updated.with_projection(GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC) \
			.with_orthographic_zoom_range(main_camera_ortho_size, main_camera_ortho_size) \
			.with_bound_plane(GDCameraPoseSystem.CameraBoundPlane.XY)
	_layout.editor_replace_camera_pose_at(index, updated)
	refresh_ui()

func apply_pose_to_main_camera(index: int) -> void:
	if _layout == null:
		return
	var got := _layout.editor_try_get_camera_pose(index)
	if not bool(got.get("ok", false)):
		return
	var pose: GDCameraPoseSystem.CameraPose = got["pose"]
	main_camera_pos = pose.position
	main_camera_euler = pose.euler_angles
	if pose.projection == GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC:
		main_camera_orthographic = true
		var min_s := pose.orthographic_min_size if pose.has_orthographic_zoom else 12.0
		var max_s := pose.orthographic_max_size if pose.has_orthographic_zoom else min_s
		main_camera_ortho_size = lerpf(min_s, max_s, pose.initial_zoom_01)
	else:
		main_camera_orthographic = false
		main_camera_fov = pose.fov
	if _status_label != null:
		_status_label.text = "已同步机位 #%d 到主相机" % index

func init_default_bound(index: int) -> void:
	if _layout == null:
		return
	var got := _layout.editor_try_get_camera_pose(index)
	if not bool(got.get("ok", false)):
		return
	var pose: GDCameraPoseSystem.CameraPose = got["pose"]
	if pose.projection == GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC:
		var c := Vector2(pose.position.x, pose.position.y)
		var updated := pose.with_bound_edges(
			c.x - DEFAULT_BOUND_HALF_EXTENTS.x,
			c.x + DEFAULT_BOUND_HALF_EXTENTS.x,
			c.y - DEFAULT_BOUND_HALF_EXTENTS.y,
			c.y + DEFAULT_BOUND_HALF_EXTENTS.y
		)
		_layout.editor_replace_camera_pose_at(index, updated)
	else:
		var xz_center := Vector2(pose.position.x, pose.position.z)
		var updated := pose.with_bound(xz_center, DEFAULT_BOUND_YAW_DEG, DEFAULT_BOUND_HALF_EXTENTS) \
			.with_bound_plane(GDCameraPoseSystem.CameraBoundPlane.XZ)
		_layout.editor_replace_camera_pose_at(index, updated)
	refresh_ui()

func save_layout() -> void:
	if _layout == null:
		return
	if not _layout.resource_path.is_empty():
		ResourceSaver.save(_layout, _layout.resource_path)
	if _status_label != null:
		_status_label.text = "机位已保存"

func refresh_ui() -> void:
	if _list_box == null:
		return
	GDEditorUi.clear_children(_list_box)

	if _layout == null:
		_pose_count_label.text = "未绑定 Layout。"
		return

	_pose_count_label.text = "相机机位 (%d)" % _layout.camera_poses.size()
	if _layout.camera_poses.is_empty():
		var hint := Label.new()
		hint.text = "还没有机位。点上方「记录当前主相机机位」新增。"
		_list_box.add_child(hint)
		return

	for i in range(_layout.camera_poses.size()):
		var pose = _layout.camera_poses[i]
		if pose != null:
			_draw_pose_card(i, pose)

func _draw_pose_card(index: int, pose: GDCameraPoseSystem.CameraPose) -> void:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	_list_box.add_child(panel)

	var top_row := HBoxContainer.new()
	var idx_lbl := Label.new()
	idx_lbl.text = "#%d  %s (%s)" % [index, pose.display_name, pose.pose_name]
	idx_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(idx_lbl)

	var sync_from_btn := Button.new()
	sync_from_btn.text = "同步主相机当前机位"
	sync_from_btn.pressed.connect(func() -> void: refresh_pose_from_main_camera(index))
	top_row.add_child(sync_from_btn)

	var sync_to_btn := Button.new()
	sync_to_btn.text = "同步到主相机"
	sync_to_btn.pressed.connect(func() -> void: apply_pose_to_main_camera(index))
	top_row.add_child(sync_to_btn)

	var del_btn := Button.new()
	del_btn.text = "删除"
	del_btn.pressed.connect(func() -> void:
		_layout.editor_remove_camera_pose_at(index)
		refresh_ui()
	)
	top_row.add_child(del_btn)
	vbox.add_child(top_row)

	# 名称与显示名
	var name_row := HBoxContainer.new()
	var disp_e := LineEdit.new()
	disp_e.text = pose.display_name
	disp_e.placeholder_text = "显示名"
	disp_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disp_e.text_submitted.connect(func(t: String) -> void:
		_layout.editor_replace_camera_pose_at(index, pose.with_display_name(t))
		refresh_ui()
	)
	name_row.add_child(disp_e)

	var key_e := LineEdit.new()
	key_e.text = pose.pose_name
	key_e.placeholder_text = "业务键 (name)"
	key_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_e.text_submitted.connect(func(t: String) -> void:
		_layout.editor_replace_camera_pose_at(index, pose.with_name(t))
		refresh_ui()
	)
	name_row.add_child(key_e)

	var proj_opt := OptionButton.new()
	proj_opt.add_item("Perspective", GDCameraPoseSystem.CameraProjectionMode.PERSPECTIVE)
	proj_opt.add_item("Orthographic", GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC)
	proj_opt.selected = pose.projection
	proj_opt.item_selected.connect(func(sel: int) -> void:
		var plane := GDCameraPoseSystem.CameraBoundPlane.XY if sel == GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC else GDCameraPoseSystem.CameraBoundPlane.XZ
		_layout.editor_replace_camera_pose_at(index, pose.with_projection(sel).with_bound_plane(plane))
		refresh_ui()
	)
	name_row.add_child(proj_opt)
	vbox.add_child(name_row)

	# 位姿与缩放摘要
	var pose_info := Label.new()
	if pose.projection == GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC:
		pose_info.text = "Pos:(%.1f, %.1f, %.1f) Rot:(%.1f, %.1f, %.1f) OrthoSize:[%.1f, %.1f]" % [
			pose.position.x, pose.position.y, pose.position.z,
			pose.euler_angles.x, pose.euler_angles.y, pose.euler_angles.z,
			pose.orthographic_min_size, pose.orthographic_max_size
		]
	else:
		pose_info.text = "Pos:(%.1f, %.1f, %.1f) Rot:(%.1f, %.1f, %.1f) FOV:%.1f Zoom:[%.2f, %.2f] ClickFocus:%.2f" % [
			pose.position.x, pose.position.y, pose.position.z,
			pose.euler_angles.x, pose.euler_angles.y, pose.euler_angles.z,
			pose.fov, pose.zoom_min_distance, pose.zoom_max_distance, pose.click_focus_zoom_distance
		]
	vbox.add_child(pose_info)

	# 初始 Zoom 行
	var iz_row := HBoxContainer.new()
	var iz_cb := CheckBox.new()
	iz_cb.text = "启用初始 zoom"
	iz_cb.button_pressed = pose.has_initial_zoom
	iz_cb.toggled.connect(func(on: bool) -> void:
		if on:
			_layout.editor_replace_camera_pose_at(index, pose.with_initial_zoom(GDCameraPoseSystem.CameraPose.DEFAULT_INITIAL_ZOOM_01))
		else:
			_layout.editor_replace_camera_pose_at(index, pose.without_initial_zoom())
		refresh_ui()
	)
	iz_row.add_child(iz_cb)

	if pose.has_initial_zoom:
		var iz_slider := HSlider.new()
		iz_slider.min_value = 0.0
		iz_slider.max_value = 1.0
		iz_slider.step = 0.01
		iz_slider.value = pose.initial_zoom_01
		iz_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		iz_slider.value_changed.connect(func(v: float) -> void:
			_layout.editor_replace_camera_pose_at(index, pose.with_initial_zoom(v))
		)
		iz_row.add_child(iz_slider)
	vbox.add_child(iz_row)

	# 活动边界区块
	var bnd_row := HBoxContainer.new()
	var bnd_lbl := Label.new()
	bnd_lbl.text = "活动边界"
	bnd_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bnd_row.add_child(bnd_lbl)

	if not pose.has_bound:
		var init_bnd_btn := Button.new()
		init_bnd_btn.text = "初始化为默认"
		init_bnd_btn.pressed.connect(func() -> void: init_default_bound(index))
		bnd_row.add_child(init_bnd_btn)
		vbox.add_child(bnd_row)
	else:
		var clr_bnd_btn := Button.new()
		clr_bnd_btn.text = "清除"
		clr_bnd_btn.pressed.connect(func() -> void:
			_layout.editor_replace_camera_pose_at(index, pose.without_bound())
			refresh_ui()
		)
		bnd_row.add_child(clr_bnd_btn)
		vbox.add_child(bnd_row)

		var bnd_detail := Label.new()
		if pose.projection == GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC:
			bnd_detail.text = "XY 边界: Left=%.1f Right=%.1f Bottom=%.1f Top=%.1f" % [
				pose.bound_left, pose.bound_right, pose.bound_bottom, pose.bound_top
			]
			if pose.bound_left >= pose.bound_right or pose.bound_bottom >= pose.bound_top:
				bnd_detail.text += " [错误：必须满足 Left < Right 且 Bottom < Top]"
				bnd_detail.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		else:
			bnd_detail.text = "XZ 边界: Center=(%.1f, %.1f) Yaw=%.1f° HalfExtents=(%.1f, %.1f)" % [
				pose.bound_center.x, pose.bound_center.y, pose.bound_yaw_deg,
				pose.bound_half_extents.x, pose.bound_half_extents.y
			]
		vbox.add_child(bnd_detail)
