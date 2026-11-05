@tool
class_name GDPlanView
extends Control

## 关卡俯视平面图。X 向右、Z 向下，和编辑器的顶视图一致。
## 只画页面填进来的数据并发信号，不碰模型。
## 左键选中、拖动；滚轮以光标为中心缩放；中键平移；F 或右上角按钮显示全部。

## kind 为空表示点在空白处。
signal picked(kind: StringName, key: int)
## index：路径节点序号；实例为 -1。拖动过程中持续发出。
signal moved(kind: StringName, key: int, index: int, xz: Vector2)
signal move_finished(kind: StringName, key: int)
## 原型拖到平面图上松开。
signal dropped(data: Variant, xz: Vector2)
## 右键；kind 为空表示点在空白处。
signal context_requested(kind: StringName, key: int)
## 键盘操作当前选中项。
signal delete_requested
signal rename_requested
signal duplicate_requested

const MARK := &"mark"
const PATH := &"path"
const CAMERA := &"camera"
const PICK_RADIUS := 9.0
const DRAG_THRESHOLD := 3.0
const GRID_STEPS: Array[float] = [1.0, 5.0, 10.0, 50.0, 100.0, 500.0]
const HINT := "滚轮缩放 · 中键平移 · F 显示全部"


class Mark:
	var id: int
	var xz: Vector2
	var color: Color
	var label: String
	var selected: bool

	func _init(p_id: int, p_xz: Vector2, p_color: Color, p_label: String, p_selected: bool) -> void:
		id = p_id
		xz = p_xz
		color = p_color
		label = p_label
		selected = p_selected


class PathLine:
	var id: int
	var knots: PackedVector2Array
	## 曲线采样点，用来画线和点选。
	var curve: PackedVector2Array
	var label: String
	var selected: bool


class CameraMark:
	var index: int
	var xz: Vector2
	## 镜头朝向在 XZ 平面上的单位向量。
	var facing: Vector2
	## 活动边界的多边形；空表示没有边界。
	var bound: PackedVector2Array
	var label: String
	var selected: bool


class Hit:
	var kind: StringName
	var key: int
	var index: int
	var label: String

	func _init(p_kind: StringName, p_key: int, p_index: int, p_label: String) -> void:
		kind = p_kind
		key = p_key
		index = p_index
		label = p_label


var marks: Array[Mark] = []
var paths: Array[PathLine] = []
var cameras: Array[CameraMark] = []
## 路径采样预览点。
var probe: Variant = null
## 非当前关卡编辑场景中仍可平移缩放，但不能选择、拖动或接收原型。
var editable: bool = true:
	set(value):
		editable = value
		if not editable:
			_drag = null
			_dragging = false
			mouse_default_cursor_shape = Control.CURSOR_ARROW

var _scale: float = 24.0 # 像素 / 米
var _pan: Vector2 = Vector2.ZERO # 世界原点在控件里的位置
## 用户缩放或平移过之后，窗口变化不再自动重新取景。
var _navigated: bool = false
var _drag: Hit = null
var _drag_from: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _panning: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(160, 120)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = HINT
	resized.connect(func() -> void:
		if not _navigated:
			fit_all()
		queue_redraw()
	)
	var fit := GDEditorUi.tool_button(&"CenterView", "显示全部（F）", fit_all)
	fit.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fit.offset_left = -34
	fit.offset_right = -6
	fit.offset_top = 6
	add_child(fit)


func set_data(p_marks: Array[Mark], p_paths: Array[PathLine], p_cameras: Array[CameraMark]) -> void:
	marks = p_marks
	paths = p_paths
	cameras = p_cameras
	queue_redraw()


func fit_all() -> void:
	_navigated = false
	if size.x < 2.0 or size.y < 2.0:
		return
	var points := PackedVector2Array()
	for mark in marks:
		points.append(mark.xz)
	for line in paths:
		points.append_array(line.knots)
	# 不算相机边界：默认边界有上百米，会把内容缩成一团。
	for cam in cameras:
		points.append(cam.xz)
	var bounds := Rect2(-8, -8, 16, 16)
	if not points.is_empty():
		bounds = Rect2(points[0], Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(point)
	bounds = bounds.grow(maxf(2.0, maxf(bounds.size.x, bounds.size.y) * 0.12))
	_scale = clampf(minf(size.x / bounds.size.x, size.y / bounds.size.y), 0.05, 400.0)
	_pan = size * 0.5 - bounds.get_center() * _scale
	queue_redraw()


func to_screen(xz: Vector2) -> Vector2:
	return _pan + xz * _scale


func to_world(at: Vector2) -> Vector2:
	return (at - _pan) / _scale


## 视野中心的世界坐标，新建的东西放在这里。
func view_center() -> Vector2:
	return to_world(size * 0.5)


func zoom_at(at: Vector2, factor: float) -> void:
	var anchor := to_world(at)
	_navigated = true
	_scale = clampf(_scale * factor, 0.05, 400.0)
	_pan = at - anchor * _scale
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_button(event)
	elif event is InputEventMouseMotion:
		_on_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		if not editable and event.keycode != KEY_F:
			return
		match event.get_keycode_with_modifiers():
			KEY_F:
				fit_all()
			KEY_DELETE:
				delete_requested.emit()
			KEY_F2:
				rename_requested.emit()
			KEY_MASK_CTRL | KEY_D:
				duplicate_requested.emit()
			_:
				return
		accept_event()


func _on_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				zoom_at(event.position, 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			mouse_default_cursor_shape = Control.CURSOR_MOVE if _panning else Control.CURSOR_ARROW
		MOUSE_BUTTON_LEFT:
			if not editable:
				return
			if event.pressed:
				_press(event.position)
			else:
				_release()
		MOUSE_BUTTON_RIGHT:
			if not editable:
				return
			if event.pressed:
				_press(event.position)
				_drag = null
				var hit := hit_test(event.position)
				context_requested.emit(hit.kind if hit != null else &"", hit.key if hit != null else 0)
		_:
			return
	accept_event()


func _press(at: Vector2) -> void:
	if not editable:
		return
	grab_focus()
	var hit := hit_test(at)
	_drag = hit if hit != null and (hit.kind == MARK or (hit.kind == PATH and hit.index >= 0)) else null
	_drag_from = at
	_dragging = false
	picked.emit(hit.kind if hit != null else &"", hit.key if hit != null else 0)


func _release() -> void:
	if _drag != null and _dragging:
		move_finished.emit(_drag.kind, _drag.key)
	_drag = null
	_dragging = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _on_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		_navigated = true
		_pan += event.relative
		queue_redraw()
	elif _drag != null:
		if not _dragging and event.position.distance_to(_drag_from) > DRAG_THRESHOLD:
			_dragging = true
			mouse_default_cursor_shape = Control.CURSOR_DRAG
		if _dragging:
			moved.emit(_drag.kind, _drag.key, _drag.index, to_world(event.position))
	else:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if editable and hit_test(event.position) != null else Control.CURSOR_ARROW
		return
	accept_event()


func _get_tooltip(at: Vector2) -> String:
	var hit := hit_test(at)
	return hit.label if hit != null else HINT


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return editable and GDLevelSceneDrop.is_payload(data)


func _drop_data(at: Vector2, data: Variant) -> void:
	if editable:
		dropped.emit(data, to_world(at))


## 自上而下：选中路径的节点、实例、其他路径的节点、相机、路径线。
func hit_test(at: Vector2) -> Hit:
	var ordered := _paths_in_draw_order()
	if not ordered.is_empty() and ordered[-1].selected:
		var hit := _hit_knot(ordered[-1], at)
		if hit != null:
			return hit
	for i in range(marks.size() - 1, -1, -1):
		if to_screen(marks[i].xz).distance_to(at) <= PICK_RADIUS:
			return Hit.new(MARK, marks[i].id, -1, marks[i].label)
	for i in range(ordered.size() - 1, -1, -1):
		var hit := _hit_knot(ordered[i], at)
		if hit != null:
			return hit
	for cam in cameras:
		if to_screen(cam.xz).distance_to(at) <= PICK_RADIUS + 2.0:
			return Hit.new(CAMERA, cam.index, -1, cam.label)
	for line in paths:
		for k in range(line.curve.size() - 1):
			var nearest := Geometry2D.get_closest_point_to_segment(at, to_screen(line.curve[k]), to_screen(line.curve[k + 1]))
			if nearest.distance_to(at) <= PICK_RADIUS * 0.7:
				return Hit.new(PATH, line.id, -1, line.label)
	return null


func _hit_knot(line: PathLine, at: Vector2) -> Hit:
	for k in range(line.knots.size() - 1, -1, -1):
		if to_screen(line.knots[k]).distance_to(at) <= PICK_RADIUS:
			return Hit.new(PATH, line.id, k, "%s · 节点 %d" % [line.label, k + 1])
	return null


## 选中的路径排在最后：画在最上面，倒序点选时也最先命中。
func _paths_in_draw_order() -> Array[PathLine]:
	var ordered: Array[PathLine] = []
	for line in paths:
		if line.selected:
			ordered.append(line)
		else:
			ordered.push_front(line)
	return ordered


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), GDEditorUi.tone(&"sunken"))
	var step := _draw_grid()
	for cam in cameras:
		if cam.selected and cam.bound.size() >= 3:
			_draw_bound(cam.bound)
	for line in _paths_in_draw_order():
		_draw_path(line)
		if not line.selected:
			_draw_knots(line)
	for cam in cameras:
		_draw_camera(cam)
	for mark in marks:
		_draw_mark(mark)
	for line in paths:
		if line.selected:
			_draw_knots(line)
	if probe is Vector2:
		var at := to_screen(probe)
		draw_circle(at, 4.5, GDEditorUi.tone(&"accent"))
		draw_arc(at, 8.0, 0.0, TAU, 24, GDEditorUi.tone(&"accent"), 1.5, true)
	for mark in marks:
		if mark.selected:
			_draw_label(to_screen(mark.xz) + Vector2(12, -10), mark.label)
	for line in paths:
		if line.selected and not line.knots.is_empty():
			_draw_label(to_screen(line.knots[0]) + Vector2(10, -12), line.label)
	for cam in cameras:
		if cam.selected:
			_draw_label(to_screen(cam.xz) + Vector2(12, -10), cam.label)
	var font := get_theme_default_font()
	draw_string(font, Vector2(8, size.y - 8), "网格 %d 米" % int(step), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(), GDEditorUi.tone(&"muted"))


## 网格间距按缩放取 1 / 5 / 10 米……，保证线不会挤在一起。返回所用间距。
func _draw_grid() -> float:
	var step: float = GRID_STEPS[-1]
	for candidate in GRID_STEPS:
		if candidate * _scale >= 14.0:
			step = candidate
			break
	var minor := GDEditorUi.tone(&"border")
	var major := Color(GDEditorUi.tone(&"text"), 0.12)
	var top_left := to_world(Vector2.ZERO)
	var bottom_right := to_world(size)
	var x := floorf(top_left.x / step) * step
	while x <= bottom_right.x:
		var sx := to_screen(Vector2(x, 0)).x
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), major if is_zero_approx(fmod(x, step * 10.0)) else minor)
		x += step
	var z := floorf(top_left.y / step) * step
	while z <= bottom_right.y:
		var sy := to_screen(Vector2(0, z)).y
		draw_line(Vector2(0, sy), Vector2(size.x, sy), major if is_zero_approx(fmod(z, step * 10.0)) else minor)
		z += step
	var origin := to_screen(Vector2.ZERO)
	draw_line(Vector2(0, origin.y), Vector2(size.x, origin.y), Color(GDEditorUi.tone(&"danger"), 0.55), 1.5)
	draw_line(Vector2(origin.x, 0), Vector2(origin.x, size.y), Color(GDEditorUi.tone(&"accent"), 0.55), 1.5)
	return step


func _draw_bound(bound: PackedVector2Array) -> void:
	var screen := PackedVector2Array()
	for point in bound:
		screen.append(to_screen(point))
	draw_colored_polygon(screen, Color(GDEditorUi.tone(&"accent"), 0.07))
	screen.append(screen[0])
	draw_polyline(screen, Color(GDEditorUi.tone(&"accent"), 0.8), 1.5, true)


func _draw_path(line: PathLine) -> void:
	var color := GDEditorUi.tone(&"accent") if line.selected else GDEditorUi.tone(&"ok")
	var screen := PackedVector2Array()
	for point in line.curve:
		screen.append(to_screen(point))
	if screen.size() >= 2:
		draw_polyline(screen, color, 3.0 if line.selected else 2.0, true)


## 节点手柄：第一个实心，表示路径起点。
func _draw_knots(line: PathLine) -> void:
	var color := GDEditorUi.tone(&"accent") if line.selected else GDEditorUi.tone(&"ok")
	var half := 4.5 if line.selected else 3.5
	for k in range(line.knots.size()):
		var rect := Rect2(to_screen(line.knots[k]) - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(rect, color if k == 0 else GDEditorUi.tone(&"surface"))
		draw_rect(rect, color, false, 1.5)


func _draw_camera(cam: CameraMark) -> void:
	var at := to_screen(cam.xz)
	var forward := cam.facing.normalized() if cam.facing.length() > 0.01 else Vector2.UP
	var side := Vector2(-forward.y, forward.x)
	var reach := 1.3 if cam.selected else 1.0
	var tri := PackedVector2Array([at + forward * 11.0 * reach, at - forward * 6.0 * reach + side * 7.0 * reach, at - forward * 6.0 * reach - side * 7.0 * reach])
	var color := GDEditorUi.tone(&"accent") if cam.selected else GDEditorUi.tone(&"muted")
	draw_colored_polygon(tri, color)
	tri.append(tri[0])
	draw_polyline(tri, GDEditorUi.tone(&"text") if cam.selected else Color(GDEditorUi.tone(&"text"), 0.4), 1.0, true)


func _draw_mark(mark: Mark) -> void:
	var at := to_screen(mark.xz)
	var radius := 7.0 if mark.selected else 5.0
	draw_circle(at, radius, mark.color)
	draw_arc(at, radius, 0.0, TAU, 24, Color(GDEditorUi.tone(&"text"), 0.45), 1.0, true)
	if mark.selected:
		draw_arc(at, radius + 3.5, 0.0, TAU, 32, GDEditorUi.tone(&"text"), 1.5, true)


func _draw_label(at: Vector2, text: String) -> void:
	if text.is_empty():
		return
	var font := get_theme_default_font()
	var font_size := _font_size()
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box := Rect2(at - Vector2(4, extent.y - 2), extent + Vector2(8, 4))
	draw_rect(box, Color(GDEditorUi.tone(&"surface"), 0.88))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GDEditorUi.tone(&"text"))


func _font_size() -> int:
	return maxi(10, get_theme_default_font_size() - 2)
