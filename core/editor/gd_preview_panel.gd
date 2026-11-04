@tool
class_name GDArchetypePreviewPanel
extends VBoxContainer

## 原型可交互预览面板（对应 TimiMiniGame.Core.Editor.ArchetypePreviewPanel + ArchetypePreviewStage + ArchetypeThumbnailService）
## 支持折叠头「外观预览」、工具栏（来源标签、原点/包围框开关、棋盘格背景开关、重置按钮）、
## 2D/3D 交互（左键环绕 / 右键平移 / 滚轮缩放 / 双击恢复自动取景）。

const PREF_EXPANDED := "Gdesigner.ArchetypePreviewPanel.Expanded"
const PREF_OVERLAY := "Gdesigner.ArchetypePreviewPanel.Overlay"
const PREF_CHECKER := "Gdesigner.ArchetypePreviewPanel.Checker"
const MIN_ZOOM := 0.1
const MAX_ZOOM := 20.0

var _target_archetype: GDArchetypeRes = null
var _expanded: bool = true
var _show_overlay: bool = true
var _show_checker: bool = false

var _yaw_deg: float = 35.0
var _pitch_deg: float = 25.0
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO

var _fold_btn: Button = null
var _body_box: VBoxContainer = null
var _source_label: Label = null
var _overlay_btn: Button = null
var _checker_btn: Button = null
var _reset_btn: Button = null
var _viewport_canvas: Control = null
var _dragging_orbit: bool = false
var _dragging_pan: bool = false

func _init() -> void:
	_expanded = GDHybridPrefs.get_bool(PREF_EXPANDED, true)
	_show_overlay = GDHybridPrefs.get_bool(PREF_OVERLAY, true)
	_show_checker = GDHybridPrefs.get_bool(PREF_CHECKER, false)
	_build_ui()

func bind_archetype(archetype: GDArchetypeRes) -> void:
	if _target_archetype != archetype:
		_target_archetype = archetype
		reset_view()
	_refresh_labels()
	if _viewport_canvas != null:
		_viewport_canvas.queue_redraw()

func reset_view() -> void:
	_yaw_deg = 35.0
	_pitch_deg = 25.0
	_zoom = 1.0
	_pan = Vector2.ZERO
	if _viewport_canvas != null:
		_viewport_canvas.queue_redraw()

func _build_ui() -> void:
	add_theme_constant_override("separation", 4)

	_fold_btn = Button.new()
	_fold_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_fold_btn.text = ("▼ " if _expanded else "▶ ") + "外观预览"
	_fold_btn.pressed.connect(func() -> void:
		_expanded = not _expanded
		GDHybridPrefs.set_bool(PREF_EXPANDED, _expanded)
		_fold_btn.text = ("▼ " if _expanded else "▶ ") + "外观预览"
		_body_box.visible = _expanded
	)
	add_child(_fold_btn)

	_body_box = VBoxContainer.new()
	_body_box.visible = _expanded
	_body_box.add_theme_constant_override("separation", 4)
	add_child(_body_box)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 4)
	_body_box.add_child(toolbar)

	_source_label = Label.new()
	_source_label.text = "无外观"
	_source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_label.clip_text = true
	toolbar.add_child(_source_label)

	_overlay_btn = Button.new()
	_overlay_btn.toggle_mode = true
	_overlay_btn.button_pressed = _show_overlay
	_overlay_btn.text = "原点/包围框"
	_overlay_btn.tooltip_text = "红十字是 Prefab 原点（关卡落点对齐的就是它），蓝框是渲染包围框"
	_overlay_btn.toggled.connect(func(on: bool) -> void:
		_show_overlay = on
		GDHybridPrefs.set_bool(PREF_OVERLAY, on)
		_viewport_canvas.queue_redraw()
	)
	toolbar.add_child(_overlay_btn)

	_checker_btn = Button.new()
	_checker_btn.toggle_mode = true
	_checker_btn.button_pressed = _show_checker
	_checker_btn.text = "棋盘格"
	_checker_btn.tooltip_text = "切换深色 / 棋盘格背景，方便看清半透明边缘"
	_checker_btn.toggled.connect(func(on: bool) -> void:
		_show_checker = on
		GDHybridPrefs.set_bool(PREF_CHECKER, on)
		_viewport_canvas.queue_redraw()
	)
	toolbar.add_child(_checker_btn)

	_reset_btn = Button.new()
	_reset_btn.text = "重置"
	_reset_btn.tooltip_text = "恢复自动取景（也可在预览区双击）"
	_reset_btn.pressed.connect(reset_view)
	toolbar.add_child(_reset_btn)

	_viewport_canvas = Control.new()
	_viewport_canvas.custom_minimum_size = Vector2(200, 180)
	_viewport_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport_canvas.gui_input.connect(_on_viewport_gui_input)
	_viewport_canvas.draw.connect(_on_viewport_draw)
	_body_box.add_child(_viewport_canvas)

func _refresh_labels() -> void:
	if _source_label == null:
		return
	if _target_archetype == null:
		_source_label.text = "无外观"
		return
	if not _target_archetype.preview_prefab_address.is_empty():
		_source_label.text = "3D · 预览 Prefab（%s）" % _target_archetype.preview_prefab_address
	elif not _target_archetype.manufactured_prefab_address.is_empty():
		_source_label.text = "3D · 实例 Prefab（%s）" % _target_archetype.manufactured_prefab_address
	else:
		_source_label.text = "无外观"

func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click:
				reset_view()
				accept_event()
				return
			_dragging_orbit = mb.pressed
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_pan = mb.pressed
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom * 1.1, MIN_ZOOM, MAX_ZOOM)
			_viewport_canvas.queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom / 1.1, MIN_ZOOM, MAX_ZOOM)
			_viewport_canvas.queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_orbit:
			_yaw_deg += mm.relative.x * 0.5
			_pitch_deg = clampf(_pitch_deg + mm.relative.y * 0.5, -89.0, 89.0)
			_viewport_canvas.queue_redraw()
			accept_event()
		elif _dragging_pan:
			_pan += mm.relative
			_viewport_canvas.queue_redraw()
			accept_event()

func _on_viewport_draw() -> void:
	var rect := Rect2(Vector2.ZERO, _viewport_canvas.size)
	if _show_checker:
		var cell := 16.0
		var cols := ceili(rect.size.x / cell)
		var rows := ceili(rect.size.y / cell)
		var col_a := Color(0.30, 0.30, 0.32, 1.0)
		var col_b := Color(0.22, 0.22, 0.24, 1.0)
		for r in range(rows):
			for c in range(cols):
				var p := Vector2(c * cell, r * cell)
				var s := Vector2(minf(cell, rect.size.x - p.x), minf(cell, rect.size.y - p.y))
				_viewport_canvas.draw_rect(Rect2(p, s), col_a if (r + c) % 2 == 0 else col_b)
	else:
		_viewport_canvas.draw_rect(rect, Color(0.16, 0.16, 0.18, 1.0))

	var has_source := _target_archetype != null and (
		not _target_archetype.preview_prefab_address.is_empty() or
		not _target_archetype.manufactured_prefab_address.is_empty()
	)
	var center := rect.size * 0.5 + _pan
	var font := ThemeDB.fallback_font
	if not has_source:
		if font != null:
			_viewport_canvas.draw_string(
				font,
				Vector2(12, rect.size.y * 0.5),
				"未找到可显示的外观（请配置预览或实例 Prefab）",
				HORIZONTAL_ALIGNMENT_LEFT,
				rect.size.x - 24,
				12,
				Color(0.65, 0.65, 0.68)
			)
		return

	# 绘制 3D 线框投影示意与原点/包围框
	var scale_px := 36.0 * _zoom
	var yaw_rad := deg_to_rad(_yaw_deg)
	var pitch_rad := deg_to_rad(_pitch_deg)
	var basis := Basis.from_euler(Vector3(pitch_rad, yaw_rad, 0.0))

	var corners: Array[Vector2] = []
	var raw_pts: Array[Vector3] = [
		Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1),
	]
	for pt in raw_pts:
		var rotated := basis * pt
		corners.append(center + Vector2(rotated.x, -rotated.y) * scale_px)

	# 实体缩略主体色块
	_viewport_canvas.draw_circle(center, scale_px * 0.65, Color(0.28, 0.48, 0.72, 0.45))

	if _show_overlay:
		var bounds_col := Color(0.35, 0.8, 1.0, 0.85)
		for i in range(4):
			_viewport_canvas.draw_line(corners[i], corners[(i + 1) % 4], bounds_col, 1.5)
			_viewport_canvas.draw_line(corners[i + 4], corners[(i + 1) % 4 + 4], bounds_col, 1.5)
			_viewport_canvas.draw_line(corners[i], corners[i + 4], bounds_col, 1.5)

		var origin_col := Color(1.0, 0.35, 0.3, 0.95)
		var arm := scale_px * 0.35
		_viewport_canvas.draw_line(center + Vector2(-arm, 0), center + Vector2(arm, 0), origin_col, 2.0)
		_viewport_canvas.draw_line(center + Vector2(0, -arm), center + Vector2(0, arm), origin_col, 2.0)

	if font != null and _target_archetype != null:
		var title := _target_archetype.display_name if not _target_archetype.display_name.is_empty() else "Archetype#%d" % _target_archetype.stable_id
		_viewport_canvas.draw_string(
			font,
			Vector2(8, rect.size.y - 8),
			"%s  (Yaw:%.0f° Pitch:%.0f° Zoom:%.2fx)" % [title, _yaw_deg, _pitch_deg, _zoom],
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 16,
			11,
			Color(0.85, 0.85, 0.88)
		)
