@tool
class_name GDSkillTimelineView
extends Control

## 技能时间轴。标尺、组、轨道和片段全部自绘，片段不建子节点。
## 视图只改片段的时间、所在轨道和技能总时长；增删、复制、菜单都经信号交给页面。
## 选中项是路径 [组, 轨道, 片段]，撤销后对象会重建，路径照样有效。

signal selection_changed(path: PackedInt32Array)
## 视图改了模型，页面据此提交一步撤销。
signal edited(label: String, merge: bool)
signal scrubbed(ms: float)
## path：[] 空白、[组]、[组, 轨道]、[组, 轨道, 片段]。
signal context_requested(path: PackedInt32Array, ms: int)
## 组行的 +（加轨道）；轨道行的 + 或双击轨道空白处（在 ms 处加片段）。
signal add_requested(path: PackedInt32Array, ms: int)
signal delete_requested(path: PackedInt32Array)
signal duplicate_requested(path: PackedInt32Array)

const Mode := GDSkillTimelineDrag.Mode
const RULER_H := 26.0
const GROUP_H := 24.0
const TRACK_H := 28.0
const HEADER_W := 170.0
const GRIP := 8.0
const MIN_PPM := 0.02
const MAX_PPM := 4.0
const NUDGE_MS := 10


class Row:
	var path: PackedInt32Array
	var y: float
	var h: float

	func _init(p_path: PackedInt32Array, p_y: float, p_h: float) -> void:
		path = p_path
		y = p_y
		h = p_h


var skill: GDSkillRes = null
var selection := PackedInt32Array()
var playhead_ms: float = 0.0
## 预览开始后，播放头扫过的片段画成已触发。
var show_fired: bool = false
var snap_enabled: bool = true
var pixels_per_ms: float = 0.4

var _rows: Array[Row] = []
var _folded: Dictionary = {}
var _drag := GDSkillTimelineDrag.new()
var _hover := PackedInt32Array()
## 适配之后、用户缩放之前，尺寸变化时保持整段可见。
var _fitted: bool = false
var _hbar := HScrollBar.new()
var _vbar := VScrollBar.new()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(320, 120)
	for bar: ScrollBar in [_hbar, _vbar]:
		bar.value_changed.connect(func(_v: float) -> void: queue_redraw())
		add_child(bar)
	resized.connect(func() -> void: fit() if _fitted else _layout_bars())


## 模型或选中项变了之后调用。
func refresh() -> void:
	_rows.clear()
	var y := 0.0
	for g in range(skill.groups.size() if skill != null else 0):
		_rows.append(Row.new(PackedInt32Array([g]), y, GROUP_H))
		y += GROUP_H
		for t in range(0 if is_folded(g) else skill.groups[g].tracks.size()):
			_rows.append(Row.new(PackedInt32Array([g, t]), y, TRACK_H))
			y += TRACK_H
	_layout_bars()
	queue_redraw()


## follow：播放时播放头走出视图就翻页。
func set_playhead(ms: float, follow: bool = false) -> void:
	playhead_ms = ms
	if follow:
		_scroll_into_view(ms)
	queue_redraw()


func ms_to_x(ms: float) -> float:
	return HEADER_W + ms * pixels_per_ms - _hbar.value


func x_to_ms(x: float) -> float:
	return (x - HEADER_W + _hbar.value) / pixels_per_ms


## 以 anchor_x 处的时刻为不动点缩放；不给 anchor_x 就以视图中央为准。
func zoom_by(factor: float, anchor_x: float = -1.0) -> void:
	var anchor := anchor_x if anchor_x >= HEADER_W else HEADER_W + _time_width() * 0.5
	var ms := x_to_ms(anchor)
	_fitted = false
	pixels_per_ms = clampf(pixels_per_ms * factor, MIN_PPM, MAX_PPM)
	_layout_bars()
	_hbar.value = ms * pixels_per_ms - (anchor - HEADER_W)
	queue_redraw()


## 整个技能刚好放进可见区域。
func fit() -> void:
	_fitted = true
	var span := maxf(100.0, float(skill.duration_ms) if skill != null else 1000.0)
	pixels_per_ms = clampf((_time_width() - 48.0) / span, MIN_PPM, MAX_PPM)
	_layout_bars()
	_hbar.value = 0.0
	queue_redraw()


## 片段不在可见范围内时滚过去，组被折叠就展开。
func reveal(path: PackedInt32Array) -> void:
	var clip := GDSkillTimelineDrag.clip_at(skill, path)
	if clip == null:
		return
	if is_folded(path[0]):
		toggle_fold(path[0])
	_scroll_into_view(clip.start_ms)
	var row := row_rect(path.slice(0, 2))
	if row.position.y < RULER_H or row.end.y > _rows_bottom():
		_vbar.value += row.position.y - RULER_H
	queue_redraw()


func _scroll_into_view(ms: float) -> void:
	var x := ms_to_x(ms)
	if x < HEADER_W or x > HEADER_W + _time_width() - 32.0:
		_fitted = false
		_hbar.value = ms * pixels_per_ms - _time_width() * 0.2


func is_folded(group_index: int) -> bool:
	return bool(_folded.get(_fold_key(group_index), false))


func toggle_fold(group_index: int) -> void:
	_folded[_fold_key(group_index)] = not is_folded(group_index)
	refresh()


## 行在本控件中的矩形；行被折叠或不存在时为空矩形。
func row_rect(path: PackedInt32Array) -> Rect2:
	for row in _rows:
		if row.path == path:
			return _box(row)
	return Rect2()


func clip_rect(path: PackedInt32Array) -> Rect2:
	var clip := GDSkillTimelineDrag.clip_at(skill, path)
	return _clip_box(row_rect(path.slice(0, 2)), clip.start_ms, clip.duration_ms) if clip != null else Rect2()


# ── 布局与命中 ──

func _layout_bars() -> void:
	var hb := _hbar.get_combined_minimum_size().y
	var vb := _vbar.get_combined_minimum_size().x
	var view_h := maxf(0.0, size.y - RULER_H - hb)
	var content_h: float = _rows.back().y + _rows.back().h if not _rows.is_empty() else 0.0
	_vbar.visible = content_h > view_h
	_vbar.position = Vector2(size.x - vb, RULER_H)
	_vbar.size = Vector2(vb, view_h)
	_vbar.max_value = content_h
	_vbar.page = view_h
	_hbar.position = Vector2(HEADER_W, size.y - hb)
	_hbar.size = Vector2(maxf(0.0, size.x - HEADER_W - (vb if _vbar.visible else 0.0)), hb)
	var content_ms := float(maxi(_shown_duration(), GDSkillTimelineDrag.max_clip_end(skill) if skill != null else 0)) * 1.25 + 200.0
	_hbar.max_value = content_ms * pixels_per_ms
	_hbar.page = _time_width()


func _time_width() -> float:
	return maxf(1.0, size.x - HEADER_W - (_vbar.size.x if _vbar.visible else 0.0))


func _rows_bottom() -> float:
	return size.y - _hbar.size.y


func _shown_duration() -> int:
	if _drag.mode == Mode.END:
		return _drag.duration
	return skill.duration_ms if skill != null else 0


func _fold_key(group_index: int) -> String:
	return "%d/%s" % [skill.get_instance_id(), skill.groups[group_index].group_name]


func _track(path: PackedInt32Array) -> GDSkillRes.SkillTrack:
	return skill.groups[path[0]].tracks[path[1]]


func _box(row: Row) -> Rect2:
	return Rect2(0.0, RULER_H + row.y - _vbar.value, size.x, row.h)


func _clip_box(row: Rect2, start: int, dur: int) -> Rect2:
	var x := ms_to_x(start)
	if dur <= 0:
		return Rect2(x - 7.0, row.position.y + 4.0, 14.0, row.size.y - 8.0)
	return Rect2(x, row.position.y + 4.0, maxf(3.0, dur * pixels_per_ms), row.size.y - 8.0)


func _plus_rect(row_box: Rect2) -> Rect2:
	return Rect2(HEADER_W - 24.0, row_box.position.y + (row_box.size.y - 18.0) * 0.5, 18.0, 18.0)


func _row_at(y: float) -> Row:
	if y < RULER_H or y > _rows_bottom():
		return null
	var content_y := y - RULER_H + _vbar.value
	for row in _rows:
		if content_y >= row.y and content_y < row.y + row.h:
			return row
	return null


func _clip_at(pos: Vector2) -> PackedInt32Array:
	var row := _row_at(pos.y)
	if row == null or row.path.size() != 2 or pos.x < HEADER_W:
		return PackedInt32Array()
	var clips: Array = _track(row.path).clips
	for c in range(clips.size() - 1, -1, -1):
		if _clip_box(_box(row), clips[c].start_ms, clips[c].duration_ms).grow_individual(0, 4, 0, 4).has_point(pos):
			return PackedInt32Array([row.path[0], row.path[1], c])
	return PackedInt32Array()


## 片段两端各 8 像素是修剪手柄；瞬时片段只能移动。
func _part_at(path: PackedInt32Array, pos: Vector2) -> int:
	var box := clip_rect(path)
	if GDSkillTimelineDrag.clip_at(skill, path).duration_ms <= 0:
		return Mode.MOVE
	var grip := minf(GRIP, box.size.x / 3.0)
	if pos.x <= box.position.x + grip:
		return Mode.TRIM_LEFT
	return Mode.TRIM_RIGHT if pos.x >= box.end.x - grip else Mode.MOVE


func _near_end_marker(pos: Vector2) -> bool:
	return pos.y < RULER_H and absf(pos.x - ms_to_x(skill.duration_ms)) <= 5.0


# ── 输入 ──

func _gui_input(event: InputEvent) -> void:
	if skill == null:
		return
	if event is InputEventMouseButton:
		_on_button(event)
	elif event is InputEventMouseMotion:
		_on_motion(event)
	elif event is InputEventKey and event.pressed:
		_on_key(event)


func _on_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT:
			if mb.pressed:
				_on_wheel(mb)
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_left(mb)
			else:
				_release_left()
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_press_right(mb.position)
		MOUSE_BUTTON_MIDDLE:
			_drag = GDSkillTimelineDrag.new(Mode.PAN if mb.pressed else Mode.NONE, mb.position)
		_:
			return
	accept_event()


func _on_wheel(mb: InputEventMouseButton) -> void:
	var forward := mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_LEFT
	var amount := maxf(1.0, mb.factor)
	if mb.ctrl_pressed or mb.meta_pressed:
		zoom_by(pow(1.15, amount if forward else -amount), mb.position.x)
	elif mb.shift_pressed or mb.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		_hbar.value += (-60.0 if forward else 60.0) * amount
	else:
		_vbar.value += (-TRACK_H if forward else TRACK_H) * amount


func _press_left(mb: InputEventMouseButton) -> void:
	grab_focus()
	var pos := mb.position
	if pos.y < RULER_H:
		if pos.x >= HEADER_W:
			_begin(Mode.END if _near_end_marker(pos) else Mode.SCRUB, pos)
			if _drag.mode == Mode.SCRUB:
				_set_playhead(roundf(clampf(x_to_ms(pos.x), 0.0, skill.duration_ms)))
		return
	var row := _row_at(pos.y)
	var hit := _clip_at(pos)
	if pos.x < HEADER_W:
		_press_header(row, pos, mb.double_click)
	elif not hit.is_empty():
		_select(hit)
		_begin(_part_at(hit, pos), pos, hit)
	elif row != null and row.path.size() == 2 and mb.double_click:
		var ms := GDSkillTimelineDrag.new(Mode.NONE, pos, skill, PackedInt32Array(), playhead_ms).snap(x_to_ms(pos.x), pixels_per_ms, snap_enabled and not mb.shift_pressed)
		add_requested.emit(row.path, roundi(clampf(ms, 0.0, skill.duration_ms)))
	else:
		_select(row.path if row != null and row.path.size() == 1 else PackedInt32Array())


func _press_header(row: Row, pos: Vector2, double_click: bool) -> void:
	if row == null:
		_select(PackedInt32Array())
	elif _plus_rect(_box(row)).has_point(pos):
		add_requested.emit(row.path, roundi(playhead_ms))
	elif row.path.size() == 1 and (pos.x < 24.0 or double_click):
		toggle_fold(row.path[0])
	else:
		_select(row.path)


func _press_right(pos: Vector2) -> void:
	grab_focus()
	var path := _clip_at(pos)
	if path.is_empty():
		var row := _row_at(pos.y)
		path = row.path if row != null else PackedInt32Array()
	_select(path)
	var ms := clampf(x_to_ms(pos.x), 0.0, skill.duration_ms) if pos.x >= HEADER_W else playhead_ms
	context_requested.emit(path, roundi(ms))


func _begin(mode: int, pos: Vector2, path := PackedInt32Array()) -> void:
	_drag = GDSkillTimelineDrag.new(mode, pos, skill, path, playhead_ms)


func _on_motion(mm: InputEventMouseMotion) -> void:
	var pos := mm.position
	match _drag.mode:
		Mode.NONE:
			_update_hover(pos)
			return
		Mode.PAN:
			_hbar.value -= mm.relative.x
			_vbar.value -= mm.relative.y
		Mode.SCRUB:
			_set_playhead(roundf(clampf(x_to_ms(pos.x), 0.0, skill.duration_ms)))
		_:
			if not _drag.active and pos.distance_to(_drag.press) < 3.0:
				return
			_drag.active = true
			var row := _row_at(pos.y)
			var row_track := row.path if row != null and row.path.size() == 2 else PackedInt32Array()
			_drag.update(skill, (pos.x - _drag.press.x) / pixels_per_ms, x_to_ms(pos.x), row_track, pixels_per_ms, snap_enabled and not mm.shift_pressed)
			if _drag.mode == Mode.END:
				_layout_bars()
	accept_event()
	queue_redraw()


## 松手时才写模型，整个拖拽只提交一次。
func _release_left() -> void:
	var done := _drag
	_drag = GDSkillTimelineDrag.new()
	queue_redraw()
	var origin := done.path
	var label := done.apply(skill)
	if label.is_empty():
		return
	if done.path != origin:
		_select(done.path)
	edited.emit(label, false)


func _on_key(key: InputEventKey) -> void:
	if key.keycode == KEY_ESCAPE:
		if _drag.mode != Mode.NONE:
			_drag = GDSkillTimelineDrag.new()
			queue_redraw()
		elif not selection.is_empty():
			_select(PackedInt32Array())
		else:
			return
		accept_event()
		return
	match key.get_keycode_with_modifiers():
		KEY_DELETE:
			if not selection.is_empty() and not key.echo:
				delete_requested.emit(selection)
		KEY_MASK_CTRL | KEY_D, KEY_MASK_META | KEY_D:
			if selection.size() == 3 and not key.echo:
				duplicate_requested.emit(selection)
		KEY_LEFT, KEY_RIGHT, KEY_MASK_SHIFT | KEY_LEFT, KEY_MASK_SHIFT | KEY_RIGHT:
			_nudge((NUDGE_MS * 10 if key.shift_pressed else NUDGE_MS) * (-1 if key.keycode == KEY_LEFT else 1))
		KEY_HOME:
			_set_playhead(0.0)
		KEY_END:
			_set_playhead(skill.duration_ms)
		_:
			return
	accept_event()


func _nudge(step_ms: int) -> void:
	var clip := GDSkillTimelineDrag.clip_at(skill, selection)
	if clip == null:
		return
	var start := GDSkillTimelineMath.clamp_start(clip.start_ms + step_ms, clip.duration_ms, skill.duration_ms)
	if start != clip.start_ms:
		clip.set_timing(start, clip.duration_ms)
		edited.emit("微移片段", true)


func _set_playhead(ms: float) -> void:
	set_playhead(ms)
	scrubbed.emit(ms)


func _select(path: PackedInt32Array) -> void:
	selection = path
	queue_redraw()
	selection_changed.emit(path)


func _update_hover(pos: Vector2) -> void:
	var row := _row_at(pos.y)
	var path := row.path if row != null else PackedInt32Array()
	if path != _hover:
		_hover = path
		queue_redraw()
	var hit := _clip_at(pos)
	var shape := Control.CURSOR_ARROW
	if _near_end_marker(pos):
		shape = Control.CURSOR_HSIZE
	elif not hit.is_empty():
		shape = Control.CURSOR_MOVE if _part_at(hit, pos) == Mode.MOVE else Control.CURSOR_HSIZE
	elif row != null and pos.x < HEADER_W and _plus_rect(_box(row)).has_point(pos):
		shape = Control.CURSOR_POINTING_HAND
	mouse_default_cursor_shape = shape


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not _hover.is_empty():
		_hover = PackedInt32Array()
		queue_redraw()


func _get_tooltip(at: Vector2) -> String:
	if skill == null:
		return ""
	var hit := _clip_at(at)
	if not hit.is_empty():
		var clip := GDSkillTimelineDrag.clip_at(skill, hit)
		var timing := "瞬时" if clip.duration_ms <= 0 else "时长 %d ms" % clip.duration_ms
		return "%s\n起始 %d ms · %s" % [_clip_name(clip), clip.start_ms, timing]
	var row := _row_at(at.y)
	if row != null and at.x < HEADER_W and _plus_rect(_box(row)).has_point(at):
		return "添加轨道" if row.path.size() == 1 else "在播放头添加片段"
	return "拖动改总时长" if _near_end_marker(at) else ""


static func _clip_name(clip: GDSkillClips.SkillClip) -> String:
	return clip.display_name if not clip.display_name.is_empty() else GDSkillForge.get_display_name(clip.get_clip_short_name())


# ── 绘制 ──
## 从下往上画：行底、片段、标记线，再盖上固定的表头列和标尺，滚动内容不会露出来。

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), GDEditorUi.tone(&"sunken"))
	if skill == null:
		return
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	_draw_rows()
	for instants in [false, true]:
		for row in _rows:
			var clips: Array = _track(row.path).clips if row.path.size() == 2 else []
			for c in range(clips.size()):
				var path := PackedInt32Array([row.path[0], row.path[1], c])
				if (clips[c].duration_ms <= 0) == instants and (not _drag.active or path != _drag.path):
					_draw_clip(row.path, clips[c], clips[c].start_ms, clips[c].duration_ms, path == selection, font, font_size, _next_start(clips, c))
	var dragged := GDSkillTimelineDrag.clip_at(skill, _drag.path)
	if _drag.active and dragged != null:
		_draw_clip(_drag.track, dragged, _drag.start, _drag.dur, true, font, font_size, INF)
	_draw_markers()
	_draw_headers(font, font_size)
	_draw_ruler(font, font_size)


func _draw_rows() -> void:
	var end_x := clampf(ms_to_x(_shown_duration()), HEADER_W, size.x)
	var last := RULER_H
	for row in _rows:
		var box := _box(row)
		last = box.end.y
		if row.path.size() == 1:
			draw_rect(Rect2(HEADER_W, box.position.y, size.x - HEADER_W, box.size.y), GDEditorUi.tone(&"raised"))
		else:
			draw_rect(Rect2(HEADER_W, box.position.y, end_x - HEADER_W, box.size.y), GDEditorUi.tone(&"surface"))
		if row.path == selection:
			draw_rect(box, Color(GDEditorUi.tone(&"accent"), 0.14))
		draw_line(Vector2(HEADER_W, box.end.y - 0.5), Vector2(size.x, box.end.y - 0.5), GDEditorUi.tone(&"border"))
	var major := GDSkillTimelinePaint.major_step(pixels_per_ms)
	var ms := ceilf(x_to_ms(HEADER_W) / major) * major
	while ms_to_x(ms) < end_x:
		draw_line(Vector2(ms_to_x(ms), RULER_H), Vector2(ms_to_x(ms), minf(last, _rows_bottom())), Color(GDEditorUi.tone(&"text"), 0.05))
		ms += major


## 同轨下一个片段的起点。名字只写到那里为止，避免互相压字。
func _next_start(clips: Array, index: int) -> float:
	var start: int = clips[index].start_ms
	var next := INF
	for c in range(clips.size()):
		if clips[c].start_ms > start or (clips[c].start_ms == start and c < index and clips[c].duration_ms <= 0):
			next = minf(next, clips[c].start_ms)
	return next


func _draw_clip(track_path: PackedInt32Array, clip: GDSkillClips.SkillClip, start: int, dur: int, selected: bool, font: Font, font_size: int, next_ms: float) -> void:
	var row := row_rect(track_path)
	if row.end.y < RULER_H or row.position.y > _rows_bottom():
		return
	var fill := GDSkillTimelinePaint.kind_color(_track(track_path).kind)
	var fired := show_fired and start <= playhead_ms
	var box := _clip_box(row, start, dur)
	var next_x := ms_to_x(next_ms)
	if dur <= 0:
		var center := Vector2(ms_to_x(start), box.get_center().y)
		GDSkillTimelinePaint.diamond(self, center, fill, selected, fired, _clip_name(clip), next_x - center.x - 16.0, font, font_size - 1)
	else:
		var text_x := maxf(box.position.x, HEADER_W) + 6.0
		GDSkillTimelinePaint.span(self, box, fill, selected, fired, _clip_name(clip), text_x, minf(box.end.x, next_x) - text_x - 4.0, font, font_size - 1)


func _draw_markers() -> void:
	var bottom := _rows_bottom()
	var end_x := ms_to_x(_shown_duration())
	if end_x < size.x:
		var from := maxf(end_x, HEADER_W)
		draw_rect(Rect2(from, RULER_H, size.x - from, bottom - RULER_H), Color(GDEditorUi.tone(&"sunken"), 0.5))
		draw_line(Vector2(end_x, RULER_H), Vector2(end_x, bottom), GDEditorUi.tone(&"muted"))
	if _drag.guide_ms >= 0.0 and _drag.active:
		var guide_x := ms_to_x(_drag.guide_ms)
		draw_line(Vector2(guide_x, RULER_H), Vector2(guide_x, bottom), GDEditorUi.tone(&"accent"))
	var head_x := ms_to_x(playhead_ms)
	if head_x >= HEADER_W:
		draw_line(Vector2(head_x, RULER_H), Vector2(head_x, bottom), GDEditorUi.tone(&"danger"), 1.5)


func _draw_headers(font: Font, font_size: int) -> void:
	draw_rect(Rect2(0, RULER_H, HEADER_W, size.y - RULER_H), GDEditorUi.tone(&"surface"))
	for row in _rows:
		var box := Rect2(0, _box(row).position.y, HEADER_W, row.h)
		var baseline := box.get_center().y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		var label := ""
		if row.path.size() == 1:
			draw_rect(box, GDEditorUi.tone(&"raised"))
			GDSkillTimelinePaint.fold_arrow(self, Vector2(12, box.get_center().y), is_folded(row.path[0]))
			label = skill.groups[row.path[0]].group_name
		else:
			draw_rect(Rect2(14, box.position.y + 6, 3, box.size.y - 12), GDSkillTimelinePaint.kind_color(_track(row.path).kind))
			label = GDSkillTimelinePaint.track_label(_track(row.path))
		font.draw_string(get_canvas_item(), Vector2(24, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, HEADER_W - 54, font_size, GDEditorUi.tone(&"text"))
		if row.path == selection:
			draw_rect(box, Color(GDEditorUi.tone(&"accent"), 0.14))
		if row.path == _hover:
			GDSkillTimelinePaint.plus(self, _plus_rect(box))
		draw_line(Vector2(0, box.end.y - 0.5), Vector2(HEADER_W, box.end.y - 0.5), GDEditorUi.tone(&"border"))
	draw_line(Vector2(HEADER_W - 0.5, RULER_H), Vector2(HEADER_W - 0.5, size.y), GDEditorUi.tone(&"border"))


## 标尺：刻度、超出总时长的暗区、总时长手柄、播放头三角。左上角盖住滚到表头下的刻度。
func _draw_ruler(font: Font, font_size: int) -> void:
	draw_rect(Rect2(0, 0, size.x, RULER_H), GDEditorUi.tone(&"surface"))
	var end_x := ms_to_x(_shown_duration())
	if end_x < size.x:
		draw_rect(Rect2(end_x, 0, size.x - end_x, RULER_H), Color(GDEditorUi.tone(&"sunken"), 0.5))
	GDSkillTimelinePaint.ticks(self, ms_to_x, x_to_ms(HEADER_W), size.x, pixels_per_ms, RULER_H, end_x, font, maxi(10, font_size - 2))
	if end_x < size.x:
		var handle := GDEditorUi.tone(&"text") if _drag.mode == Mode.END else GDEditorUi.tone(&"muted")
		GDEditorUi.paint_round_rect(self, Rect2(end_x - 3, 5, 6, RULER_H - 10), handle, Color(0, 0, 0, 0), 2, 0)
	var head_x := ms_to_x(playhead_ms)
	draw_colored_polygon(PackedVector2Array([Vector2(head_x - 6, RULER_H - 11), Vector2(head_x + 6, RULER_H - 11), Vector2(head_x, RULER_H)]), GDEditorUi.tone(&"danger"))
	draw_rect(Rect2(0, 0, HEADER_W, RULER_H), GDEditorUi.tone(&"surface"))
	draw_line(Vector2(0, RULER_H - 0.5), Vector2(size.x, RULER_H - 0.5), GDEditorUi.tone(&"border"))
	draw_line(Vector2(HEADER_W - 0.5, 0), Vector2(HEADER_W - 0.5, RULER_H), GDEditorUi.tone(&"border"))
