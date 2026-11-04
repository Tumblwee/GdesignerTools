@tool
class_name GDSkillEditorWindow
extends VBoxContainer

## 单资产 GDSkillRes 的时间轴优先编辑器（对应 TimiMiniGame.Module.Skill.Editor.SkillEditorWindow + NewSkillDialog + SkillEditorL10n）
## 三栏布局：
##   左栏：技能库浏览 + 新建技能弹窗（NewSkillDialog）
##   中栏：统一时间轴（0 -> DurationMs 200ms 标尺、播放头红线、轨道组 Group 折叠/加轨/删组、轨道 Track 点选/加 Clip 菜单、
##         Clip 块拖拽移动 StartMs & 右侧 6px 手柄拉伸 DurationMs & 右键删除、已触发高亮）+ 底部校验结果面板
##   右栏：内联 Inspector（Header / Group / Track / Clip 4 态切换，CameraEffectClip 按 Mode 动态切换相关字段，SpawnProjectile 轨迹子类型下拉）

const DEFAULT_PIXELS_PER_MS := 0.2
const MIN_PIXELS_PER_MS := 0.05
const MAX_PIXELS_PER_MS := 1.0
const TRACK_ROW_HEIGHT := 28.0
const TRACK_LABEL_WIDTH := 130.0
const MIN_CLIP_WIDTH_PX := 34.0

enum SelectionKind {
	NONE = 0,
	HEADER = 1,
	GROUP = 2,
	TRACK = 3,
	CLIP = 4,
}

enum PreviewPhase {
	IDLE = 0,
	PLAYING = 1,
	PAUSED = 2,
	FINISHED = 3,
}

var _selected_skill: GDSkillRes = null
var _all_skills: Array[GDSkillRes] = []

var _selection_kind: int = SelectionKind.NONE
var _sel_group_index: int = -1
var _sel_track_index: int = -1
var _sel_clip_index: int = -1

var _pixels_per_ms: float = DEFAULT_PIXELS_PER_MS
var _phase: int = PreviewPhase.IDLE
var _playhead_ms: float = 0.0
var _group_collapsed_by_name: Dictionary = {} # "uniqueName/groupName" -> bool
var _english_mode: bool = false

# UI 引用
var _play_pause_btn: Button = null
var _stop_btn: Button = null
var _play_state_label: Label = null
var _header_label: Label = null
var _library_title: Label = null
var _library_query: String = ""
var _library_list_box: VBoxContainer = null
var _timeline_canvas: Control = null
var _timeline_groups_box: VBoxContainer = null
var _ruler: MsRuler = null
var _playheads: Array = []
var _inspector_box: VBoxContainer = null
var _validate_box: VBoxContainer = null
var _new_skill_dialog: NewSkillDialog = null

# Clip 拖拽状态
var _dragging_clip: GDSkillClips.SkillClip = null
var _drag_resizing: bool = false
var _drag_start_mouse_x: float = 0.0
var _drag_orig_start_ms: int = 0
var _drag_orig_dur_ms: int = 0

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_process(true)
	_build_ui()
	refresh_library()

func _process(delta: float) -> void:
	if _phase == PreviewPhase.PLAYING and _selected_skill != null:
		GDSkillTypes.SkillClock.advance(delta)
		_playhead_ms += delta * 1000.0
		var total_ms := float(maxi(1, _selected_skill.duration_ms))
		if _playhead_ms >= total_ms:
			_playhead_ms = 0.0
			_phase = PreviewPhase.FINISHED
		_update_transport_visual()
		_sync_playhead_graphics()

func select_skill(skill: GDSkillRes) -> void:
	if _phase == PreviewPhase.IDLE:
		_playhead_ms = 0.0
	_selected_skill = skill
	_selection_kind = SelectionKind.HEADER if skill != null else SelectionKind.NONE
	_sel_group_index = -1
	_sel_track_index = -1
	_sel_clip_index = -1
	if _header_label != null:
		_header_label.text = ("编辑中：%s" % skill.unique_name) if skill != null else "未选中技能"
		GDEditorUi.style_context_label(_header_label)
	rebuild_timeline()
	rebuild_inspector()
	refresh_validate_panel()
	_rebuild_library_rows()

func select_header() -> void:
	if _selected_skill == null:
		return
	_selection_kind = SelectionKind.HEADER
	rebuild_inspector()
	rebuild_timeline()

func select_group(group_index: int) -> void:
	_selection_kind = SelectionKind.GROUP
	_sel_group_index = group_index
	_sel_track_index = -1
	_sel_clip_index = -1
	rebuild_inspector()
	rebuild_timeline()

func select_track(group_index: int, track_index: int) -> void:
	_selection_kind = SelectionKind.TRACK
	_sel_group_index = group_index
	_sel_track_index = track_index
	_sel_clip_index = -1
	rebuild_inspector()
	rebuild_timeline()

func select_clip(group_index: int, track_index: int, clip_index: int) -> void:
	_selection_kind = SelectionKind.CLIP
	_sel_group_index = group_index
	_sel_track_index = track_index
	_sel_clip_index = clip_index
	rebuild_inspector()
	rebuild_timeline()

func refresh_library() -> void:
	_all_skills = GDSkillForgeAndCli.get_all_known_skills()
	if _selected_skill == null and not _all_skills.is_empty():
		select_skill(_all_skills[0])
		return
	_rebuild_library_rows()


func _rebuild_library_rows() -> void:
	if _library_list_box == null:
		return
	if _library_title != null:
		_library_title.text = "技能库    %d" % _all_skills.size()
	GDEditorUi.clear_children(_library_list_box)
	if _all_skills.is_empty():
		_library_list_box.add_child(GDEditorUi.empty_state("还没有技能", [
			"点上方「新建」做一个技能。",
			"选中后，在中间时间轴加组和轨道。",
			"点轨道上的片段，右侧会显示它的参数。",
		]))
		return
	var shown := 0
	for sk in _all_skills:
		var disp := sk.display_name if not sk.display_name.is_empty() else sk.unique_name
		if not GDEditorUi.matches_query("%s %s %d" % [disp, sk.unique_name, sk.skill_id], _library_query):
			continue
		shown += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(GDEditorUi.swatch(GDEditorUi.hue_color(sk.skill_id), 6))
		var btn := Button.new()
		btn.text = "%s\n%s" % [disp, sk.unique_name]
		btn.custom_minimum_size.y = 44
		GDEditorUi.style_list_button(btn, sk == _selected_skill)
		var cap_sk := sk
		btn.pressed.connect(func() -> void: select_skill(cap_sk))
		row.add_child(btn)
		_library_list_box.add_child(row)
	if shown == 0:
		_library_list_box.add_child(GDEditorUi.muted("没有匹配「%s」的技能。" % _library_query.strip_edges()))
	elif _library_title != null and not _library_query.strip_edges().is_empty():
		_library_title.text = "技能库    %d / %d" % [shown, _all_skills.size()]

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	# 顶部工具栏
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	add_child(toolbar)

	var new_btn := Button.new()
	new_btn.text = "新建"
	new_btn.tooltip_text = "新建一个技能资产"
	new_btn.pressed.connect(_open_new_skill_dialog)
	GDEditorUi.style_button(new_btn, "primary")
	toolbar.add_child(new_btn)

	var ref_btn := Button.new()
	ref_btn.text = "刷新"
	ref_btn.pressed.connect(refresh_library)
	GDEditorUi.style_button(ref_btn, "quiet")
	toolbar.add_child(ref_btn)

	var val_btn := Button.new()
	val_btn.text = "校验"
	val_btn.tooltip_text = "检查当前技能的轨道和片段"
	val_btn.pressed.connect(refresh_validate_panel)
	GDEditorUi.style_button(val_btn, "quiet")
	toolbar.add_child(val_btn)

	toolbar.add_child(VSeparator.new())

	_play_pause_btn = Button.new()
	_play_pause_btn.text = "▶ 播放"
	_play_pause_btn.pressed.connect(_toggle_play_pause)
	GDEditorUi.style_button(_play_pause_btn, "primary")
	toolbar.add_child(_play_pause_btn)

	_stop_btn = Button.new()
	_stop_btn.text = "■ 停止"
	_stop_btn.pressed.connect(_stop_preview)
	GDEditorUi.style_button(_stop_btn, "quiet")
	toolbar.add_child(_stop_btn)

	_play_state_label = Label.new()
	_play_state_label.text = "就绪"
	toolbar.add_child(_play_state_label)

	toolbar.add_child(VSeparator.new())

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_header_label = Label.new()
	_header_label.text = "未选中技能"
	GDEditorUi.style_context_label(_header_label)
	toolbar.add_child(_header_label)

	var zoom_lbl := Label.new()
	zoom_lbl.text = "缩放"
	toolbar.add_child(zoom_lbl)

	var zoom_slider := HSlider.new()
	zoom_slider.min_value = MIN_PIXELS_PER_MS
	zoom_slider.max_value = MAX_PIXELS_PER_MS
	zoom_slider.step = 0.01
	zoom_slider.value = _pixels_per_ms
	zoom_slider.custom_minimum_size.x = 100
	zoom_slider.value_changed.connect(func(v: float) -> void:
		_pixels_per_ms = v
		rebuild_timeline()
	)
	toolbar.add_child(zoom_slider)
	GDEditorUi.wrap_toolbar(toolbar)

	# 主体三栏
	var body_split := HSplitContainer.new()
	body_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_split.split_offset = 210
	body_split.resized.connect(func() -> void:
		GDEditorUi.ensure_split_usable(body_split, 180, 480)
	)
	add_child(body_split)

	# 左栏：技能库
	var left_panel := PanelContainer.new()
	left_panel.clip_contents = true
	left_panel.custom_minimum_size.x = 200
	GDEditorUi.apply_panel(left_panel, 10)
	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)
	body_split.add_child(left_panel)

	_library_title = GDEditorUi.section_title("技能库")
	left_vbox.add_child(_library_title)
	var lib_search := GDEditorUi.search_field("搜索技能名或 ID")
	lib_search.text_changed.connect(func(t: String) -> void:
		_library_query = t
		_rebuild_library_rows()
	)
	left_vbox.add_child(lib_search)

	var lib_scroll := ScrollContainer.new()
	lib_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(lib_scroll)

	_library_list_box = VBoxContainer.new()
	_library_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_list_box.add_theme_constant_override("separation", 3)
	lib_scroll.add_child(_library_list_box)
	GDEditorUi.configure_vertical_scroll(lib_scroll, _library_list_box)

	# 中右分割
	var center_right_split := HSplitContainer.new()
	center_right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_right_split.split_offset = 540
	body_split.add_child(center_right_split)

	# 中栏：时间轴 + 校验面板
	var center_panel := PanelContainer.new()
	GDEditorUi.apply_panel(center_panel, 10)
	var center_vbox := VBoxContainer.new()
	center_vbox.add_theme_constant_override("separation", 8)
	center_panel.add_child(center_vbox)
	center_right_split.add_child(center_panel)
	center_vbox.add_child(GDEditorUi.section_title("时间轴"))

	var ops_row := HBoxContainer.new()
	ops_row.add_theme_constant_override("separation", 6)
	var add_grp_btn := Button.new()
	add_grp_btn.text = "+ 组"
	add_grp_btn.tooltip_text = "给当前技能加一组轨道"
	add_grp_btn.pressed.connect(add_group)
	GDEditorUi.style_button(add_grp_btn, "primary")
	ops_row.add_child(add_grp_btn)

	var sel_hdr_btn := Button.new()
	sel_hdr_btn.text = "技能信息"
	sel_hdr_btn.tooltip_text = "编辑名称、消耗、冷却和总时长"
	sel_hdr_btn.pressed.connect(select_header)
	GDEditorUi.style_button(sel_hdr_btn, "quiet")
	ops_row.add_child(sel_hdr_btn)

	var scrub_slider := HSlider.new()
	scrub_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrub_slider.min_value = 0
	scrub_slider.max_value = 5000
	scrub_slider.step = 10
	scrub_slider.tooltip_text = "拖动播放头时刻 (ms)"
	scrub_slider.value_changed.connect(func(v: float) -> void:
		if _selected_skill != null:
			_playhead_ms = clampf(v, 0.0, float(_selected_skill.duration_ms))
			_update_transport_visual()
			_sync_playhead_graphics()
	)
	ops_row.add_child(scrub_slider)
	center_vbox.add_child(ops_row)

	var tl_scroll := ScrollContainer.new()
	tl_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_vbox.add_child(tl_scroll)

	_timeline_groups_box = VBoxContainer.new()
	_timeline_groups_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_groups_box.add_theme_constant_override("separation", 4)
	tl_scroll.add_child(_timeline_groups_box)

	center_vbox.add_child(GDEditorUi.section_title("校验结果"))

	_validate_box = VBoxContainer.new()
	_validate_box.custom_minimum_size.y = 64
	center_vbox.add_child(_validate_box)

	# 右栏：Inspector
	var right_panel := PanelContainer.new()
	right_panel.clip_contents = true
	right_panel.custom_minimum_size.x = 280
	GDEditorUi.apply_panel(right_panel, 10)
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(right_vbox)
	center_right_split.add_child(right_panel)

	right_vbox.add_child(GDEditorUi.section_title("属性"))

	var insp_scroll := ScrollContainer.new()
	insp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(insp_scroll)

	_inspector_box = VBoxContainer.new()
	_inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_box.add_theme_constant_override("separation", 6)
	insp_scroll.add_child(_inspector_box)
	GDEditorUi.configure_vertical_scroll(insp_scroll, _inspector_box)

	_update_transport_visual()

func _sync_playhead_graphics() -> void:
	if _ruler != null and is_instance_valid(_ruler):
		_ruler.playhead = _playhead_ms
		_ruler.queue_redraw()
	for item in _playheads:
		var mark := item as PlayheadMark
		if mark != null and is_instance_valid(mark):
			mark.playhead = _playhead_ms
			mark.queue_redraw()


static func _track_color(kind: int) -> Color:
	match kind:
		GDSkillTypes.SkillTrackKind.ANIMATION:
			return Color(0.38, 0.66, 0.95)
		GDSkillTypes.SkillTrackKind.MOVEMENT:
			return Color(0.36, 0.75, 0.5)
		GDSkillTypes.SkillTrackKind.HITBOX:
			return Color(0.9, 0.4, 0.36)
		GDSkillTypes.SkillTrackKind.EFFECT:
			return Color(0.66, 0.5, 0.95)
		GDSkillTypes.SkillTrackKind.AUDIO:
			return Color(0.95, 0.72, 0.32)
		GDSkillTypes.SkillTrackKind.CAMERA:
			return Color(0.4, 0.78, 0.82)
		GDSkillTypes.SkillTrackKind.VFX:
			return Color(0.9, 0.48, 0.72)
		_:
			return Color(0.6, 0.64, 0.7)


class MsRuler extends Control:
	var total_ms: int = 1000
	var ppm: float = 0.2
	var playhead: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.y = 22

	func _draw() -> void:
		var font := get_theme_default_font()
		var step := 200
		if ppm < 0.1:
			step = 1000
		elif ppm > 0.45:
			step = 100
		var ms := 0
		while ms <= total_ms:
			var x := float(ms) * ppm
			draw_line(Vector2(x, size.y - 7), Vector2(x, size.y), Color(1, 1, 1, 0.28), 1.0)
			if font != null:
				font.draw_string(get_canvas_item(), Vector2(x + 2, 12), str(ms), HORIZONTAL_ALIGNMENT_LEFT, 48.0, 10, Color(0.7, 0.74, 0.8))
			ms += step
		var px := playhead * ppm
		draw_line(Vector2(px, 0), Vector2(px, size.y), Color(1.0, 0.32, 0.36), 1.5)


class PlayheadMark extends Control:
	var playhead: float = 0.0
	var ppm: float = 0.2

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var px := playhead * ppm
		draw_line(Vector2(px, 0), Vector2(px, size.y), Color(1.0, 0.32, 0.36), 1.5)
		draw_colored_polygon(PackedVector2Array([
			Vector2(px - 4, 0), Vector2(px + 4, 0), Vector2(px, 6)
		]), Color(1.0, 0.32, 0.36))


class ClipBlock extends Control:
	var clip: GDSkillClips.SkillClip = null
	var fill: Color = Color(0.4, 0.6, 0.9)
	var selected: bool = false
	var ppm: float = 0.2
	var label_text: String = ""
	var pick: Callable = Callable()
	var commit: Callable = Callable()
	var _mode: int = 0
	var _moved: bool = false
	var _grab_x: float = 0.0
	var _orig_start: int = 0
	var _orig_dur: int = 40

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "拖动改开始时间，拖右边缘改时长"

	func _draw() -> void:
		var bg := fill.lightened(0.12) if selected else fill
		var border := Color.WHITE if selected else Color(0, 0, 0, 0.35)
		GDEditorUi.paint_round_rect(self, Rect2(Vector2.ZERO, size), bg, border, 4, 2 if selected else 1)
		draw_rect(Rect2(Vector2(size.x - 5, 4), Vector2(2, maxf(4.0, size.y - 8))), Color(1, 1, 1, 0.75))
		var font := get_theme_default_font()
		if font != null:
			font.draw_string(get_canvas_item(), Vector2(6, size.y * 0.72), label_text, HORIZONTAL_ALIGNMENT_LEFT, maxf(8.0, size.x - 12.0), 11, Color(0.98, 0.99, 1.0))

	func _gui_input(event: InputEvent) -> void:
		if clip == null:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if mb.pressed:
				_mode = 2 if mb.position.x >= size.x - 8.0 else 1
				_moved = false
				_grab_x = mb.global_position.x
				_orig_start = clip.start_ms
				_orig_dur = maxi(40, clip.duration_ms)
				mouse_default_cursor_shape = Control.CURSOR_HSIZE if _mode == 2 else Control.CURSOR_MOVE
			else:
				if _moved:
					if commit.is_valid():
						commit.call()
				elif pick.is_valid():
					pick.call()
				_mode = 0
			accept_event()
		elif event is InputEventMouseMotion and _mode != 0:
			var mm := event as InputEventMouseMotion
			var dx := mm.global_position.x - _grab_x
			if absf(dx) > 2.0:
				_moved = true
			var delta_ms := int(round(dx / maxf(0.02, ppm)))
			if _mode == 1:
				var next_start := maxi(0, _orig_start + delta_ms)
				clip.set_timing(next_start, _orig_dur)
				position.x = float(next_start) * ppm
			else:
				var next_dur := maxi(40, _orig_dur + delta_ms)
				clip.set_timing(_orig_start, next_dur)
				size.x = maxf(28.0, float(next_dur) * ppm)
			queue_redraw()
			accept_event()


func rebuild_timeline() -> void:
	if _timeline_groups_box == null:
		return
	_ruler = null
	_playheads.clear()
	GDEditorUi.clear_children(_timeline_groups_box)

	if _selected_skill == null:
		_timeline_groups_box.add_child(GDEditorUi.empty_state("时间轴是空的", [
			"在左侧选一个技能，或点「新建」。",
			"用「+ 组」增加轨道组，再在轨道上加片段。",
			"拖动片段改开始时间，拖右边缘改时长。",
		]))
		return

	var total_dur_ms := maxi(1, _selected_skill.duration_ms)

	var ruler_row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.custom_minimum_size.x = TRACK_LABEL_WIDTH
	ruler_row.add_child(spacer)
	_ruler = MsRuler.new()
	_ruler.total_ms = total_dur_ms
	_ruler.ppm = _pixels_per_ms
	_ruler.playhead = _playhead_ms
	_ruler.custom_minimum_size = Vector2(float(total_dur_ms) * _pixels_per_ms + 48.0, 22)
	ruler_row.add_child(_ruler)
	_timeline_groups_box.add_child(ruler_row)

	# 各轨道组
	for g_idx in range(_selected_skill.groups.size()):
		var grp = _selected_skill.groups[g_idx]
		if grp == null:
			continue
		_timeline_groups_box.add_child(_build_group_view(g_idx, grp, total_dur_ms))

func _build_group_view(g_idx: int, grp: GDSkillRes.SkillTrackGroup, total_dur_ms: int) -> Control:
	var panel := PanelContainer.new()
	GDEditorUi.style_card(panel, _selection_kind == SelectionKind.GROUP and _sel_group_index == g_idx)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var collapse_key := "%s/%s" % [_selected_skill.unique_name, grp.group_name]
	var collapsed: bool = bool(_group_collapsed_by_name.get(collapse_key, false))

	var hdr := HBoxContainer.new()
	var fold_btn := Button.new()
	fold_btn.text = ">" if collapsed else "v"
	fold_btn.pressed.connect(func() -> void:
		_group_collapsed_by_name[collapse_key] = not collapsed
		rebuild_timeline()
	)
	hdr.add_child(fold_btn)

	var grp_btn := Button.new()
	grp_btn.text = grp.group_name if not grp.group_name.is_empty() else ("Group %d" % g_idx)
	grp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grp_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _selection_kind == SelectionKind.GROUP and _sel_group_index == g_idx:
		grp_btn.modulate = Color(0.5, 0.85, 1.0)
	grp_btn.pressed.connect(func() -> void: select_group(g_idx))
	hdr.add_child(grp_btn)

	var add_trk_menu := MenuButton.new()
	add_trk_menu.text = "+ 轨"
	var tp := add_trk_menu.get_popup()
	for k in range(7):
		tp.add_item(GDSkillTypes.track_kind_name(k), k)
	tp.id_pressed.connect(func(kind_id: int) -> void:
		add_track(g_idx, kind_id)
	)
	hdr.add_child(add_trk_menu)

	var rm_grp_btn := Button.new()
	rm_grp_btn.text = "X"
	rm_grp_btn.pressed.connect(func() -> void: remove_group(g_idx))
	hdr.add_child(rm_grp_btn)
	vbox.add_child(hdr)

	if not collapsed:
		for t_idx in range(grp.tracks.size()):
			var trk = grp.tracks[t_idx]
			if trk != null:
				vbox.add_child(_build_track_row(g_idx, t_idx, trk, total_dur_ms))

	return panel

func _build_track_row(g_idx: int, t_idx: int, trk: GDSkillRes.SkillTrack, total_dur_ms: int) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = TRACK_ROW_HEIGHT

	var label_box := HBoxContainer.new()
	label_box.custom_minimum_size.x = TRACK_LABEL_WIDTH
	label_box.add_theme_constant_override("separation", 4)
	label_box.add_child(GDEditorUi.swatch(_track_color(trk.kind), 6))

	var trk_btn := Button.new()
	trk_btn.flat = true
	trk_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	trk_btn.clip_text = true
	trk_btn.text = trk.track_name if not trk.track_name.is_empty() else GDSkillTypes.track_kind_name(trk.kind)
	trk_btn.tooltip_text = GDSkillTypes.track_kind_name(trk.kind)
	trk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _selection_kind == SelectionKind.TRACK and _sel_group_index == g_idx and _sel_track_index == t_idx:
		trk_btn.add_theme_color_override("font_color", Color(0.65, 0.86, 1.0))
	trk_btn.pressed.connect(func() -> void: select_track(g_idx, t_idx))
	label_box.add_child(trk_btn)

	var add_clip_menu := MenuButton.new()
	add_clip_menu.text = "+"
	add_clip_menu.tooltip_text = "添加 Clip"
	var cp := add_clip_menu.get_popup()
	for i in range(GDSkillForgeAndCli.ALL_CLIP_TYPES.size()):
		var sn: String = GDSkillForgeAndCli.ALL_CLIP_TYPES[i]
		cp.add_item("%s (%s)" % [GDSkillForgeAndCli.get_display_name(sn), sn], i)
	cp.id_pressed.connect(func(idx: int) -> void:
		add_clip(g_idx, t_idx, GDSkillForgeAndCli.ALL_CLIP_TYPES[idx])
	)
	label_box.add_child(add_clip_menu)
	row.add_child(label_box)

	var clip_area := Control.new()
	clip_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_area.custom_minimum_size = Vector2(float(total_dur_ms) * _pixels_per_ms + 48.0, TRACK_ROW_HEIGHT)
	clip_area.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(clip_area)

	for c_idx in range(trk.clips.size()):
		var clip = trk.clips[c_idx]
		if clip == null:
			continue
		var disp: String = clip.display_name if not clip.display_name.is_empty() else clip.get_clip_short_name()
		var block := ClipBlock.new()
		block.clip = clip
		block.fill = _track_color(trk.kind)
		block.ppm = _pixels_per_ms
		block.label_text = disp
		block.selected = _selection_kind == SelectionKind.CLIP and _sel_group_index == g_idx and _sel_track_index == t_idx and _sel_clip_index == c_idx
		block.position = Vector2(float(clip.start_ms) * _pixels_per_ms, 3.0)
		block.size = Vector2(maxf(MIN_CLIP_WIDTH_PX, float(maxi(clip.duration_ms, 40)) * _pixels_per_ms), TRACK_ROW_HEIGHT - 6.0)
		var cap_c := c_idx
		block.pick = func() -> void: select_clip(g_idx, t_idx, cap_c)
		block.commit = func() -> void:
			select_clip(g_idx, t_idx, cap_c)
			refresh_validate_panel()
		clip_area.add_child(block)

	var head := PlayheadMark.new()
	head.ppm = _pixels_per_ms
	head.playhead = _playhead_ms
	clip_area.add_child(head)
	_playheads.append(head)

	return row

# ─────────────────────── Inspector 构建（4 态 + CameraEffect 按模式切换） ───────────────────────

func rebuild_inspector() -> void:
	if _inspector_box == null:
		return
	GDEditorUi.clear_children(_inspector_box)

	if _selected_skill == null:
		_inspector_box.add_child(GDEditorUi.empty_state("这里显示选中项", [
			"先在左侧选中一个技能。",
			"点「技能信息」改名称、消耗和冷却。",
			"点时间轴上的组、轨道或片段改细节。",
		]))
		return

	match _selection_kind:
		SelectionKind.HEADER:
			_build_header_inspector()
		SelectionKind.GROUP:
			_build_group_inspector()
		SelectionKind.TRACK:
			_build_track_inspector()
		SelectionKind.CLIP:
			_build_clip_inspector()
		_:
			_inspector_box.add_child(GDEditorUi.muted("点时间轴上的组、轨道或片段，或点「技能信息」。"))

func _build_header_inspector() -> void:
	var sk := _selected_skill
	_inspector_box.add_child(GDEditorUi.section_title("技能信息"))
	_inspector_box.add_child(GDEditorUi.muted(sk.unique_name))

	_add_prop_line_edit("Name", sk.skill_name, func(t: String) -> void:
		sk.configure_header(t.strip_edges(), sk.skill_id, sk.display_name, sk.description)
		refresh_validate_panel()
		rebuild_inspector()
	)
	_add_prop_int_spin("ID", sk.skill_id, 0, 999999, func(v: int) -> void:
		sk.configure_header(sk.skill_name, v, sk.display_name, sk.description)
		refresh_validate_panel()
		rebuild_inspector()
	)
	_add_prop_line_edit("显示名", sk.display_name, func(t: String) -> void:
		sk.configure_header(sk.skill_name, sk.skill_id, t, sk.description)
		refresh_library()
	)
	_add_prop_line_edit("描述", sk.description, func(t: String) -> void:
		sk.configure_header(sk.skill_name, sk.skill_id, sk.display_name, t)
	)
	_add_prop_line_edit("消耗属性", sk.cost.attribute_name if sk.cost != null else "Mana", func(t: String) -> void:
		sk.set_cost(t, sk.cost.amount if sk.cost != null else 0.0)
	)
	_add_prop_float_spin("消耗数值", sk.cost.amount if sk.cost != null else 0.0, 0.0, 99999.0, func(v: float) -> void:
		sk.set_cost(sk.cost.attribute_name if sk.cost != null else "Mana", v)
	)
	_add_prop_line_edit("冷却分组", sk.cooldown.cd_group if sk.cooldown != null else "Default", func(t: String) -> void:
		sk.set_cooldown(t, sk.cooldown.duration_seconds if sk.cooldown != null else 0.0)
	)
	_add_prop_float_spin("冷却时长(s)", sk.cooldown.duration_seconds if sk.cooldown != null else 0.0, 0.0, 9999.0, func(v: float) -> void:
		sk.set_cooldown(sk.cooldown.cd_group if sk.cooldown != null else "Default", v)
	)
	_add_prop_int_spin("总时长(ms)", sk.duration_ms, 0, 600000, func(v: int) -> void:
		sk.set_duration(v)
		rebuild_timeline()
		refresh_validate_panel()
	)

func _build_group_inspector() -> void:
	if _sel_group_index < 0 or _sel_group_index >= _selected_skill.groups.size():
		return
	var grp = _selected_skill.groups[_sel_group_index]
	var hdr := Label.new()
	hdr.text = "组 [%d]" % _sel_group_index
	_inspector_box.add_child(hdr)

	_add_prop_line_edit("组名", grp.group_name, func(t: String) -> void:
		grp.configure(t)
		rebuild_timeline()
		refresh_validate_panel()
	)

func _build_track_inspector() -> void:
	if _sel_group_index < 0 or _sel_group_index >= _selected_skill.groups.size():
		return
	var grp = _selected_skill.groups[_sel_group_index]
	if _sel_track_index < 0 or _sel_track_index >= grp.tracks.size():
		return
	var trk = grp.tracks[_sel_track_index]

	var hdr := Label.new()
	hdr.text = "轨 [%d.%d]" % [_sel_group_index, _sel_track_index]
	_inspector_box.add_child(hdr)

	var kind_row := HBoxContainer.new()
	var kl := Label.new()
	kl.text = "类别"
	kl.custom_minimum_size.x = 96
	kind_row.add_child(kl)
	var k_opt := OptionButton.new()
	for k in range(7):
		k_opt.add_item(GDSkillTypes.track_kind_name(k), k)
	k_opt.selected = trk.kind
	k_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k_opt.item_selected.connect(func(idx: int) -> void:
		trk.configure(idx, trk.track_name)
		rebuild_timeline()
	)
	kind_row.add_child(k_opt)
	_inspector_box.add_child(kind_row)

	_add_prop_line_edit("轨名", trk.track_name, func(t: String) -> void:
		trk.configure(trk.kind, t)
		rebuild_timeline()
	)

	var del_btn := Button.new()
	del_btn.text = "删除此轨"
	del_btn.pressed.connect(func() -> void: remove_track(_sel_group_index, _sel_track_index))
	_inspector_box.add_child(del_btn)

func _build_clip_inspector() -> void:
	var clip := _get_clip_at(_sel_group_index, _sel_track_index, _sel_clip_index)
	if clip == null:
		return
	var short_name := clip.get_clip_short_name()
	var hdr := Label.new()
	hdr.text = "Clip：%s" % short_name
	_inspector_box.add_child(hdr)

	var total_ms := maxi(1, _selected_skill.duration_ms)
	_add_prop_int_spin("起始 (ms)", clip.start_ms, 0, total_ms, func(v: int) -> void:
		var clamped := GDSkillEditorMathAndValidator.SkillTimelineEditorMath.clamp_start(v, clip.duration_ms, total_ms)
		clip.set_timing(clamped, clip.duration_ms)
		rebuild_timeline()
		refresh_validate_panel()
	)
	_add_prop_int_spin("时长 (ms)", clip.duration_ms, 0, total_ms, func(v: int) -> void:
		clip.set_timing(clip.start_ms, maxi(0, v))
		rebuild_timeline()
		refresh_validate_panel()
	)
	_add_prop_line_edit("显示名", clip.display_name, func(t: String) -> void:
		clip.set_display_name(t)
		rebuild_timeline()
	)

	# CameraEffectClip 专属按 Mode 切换显示字段
	if clip is GDSkillClips.CameraEffectClip:
		var cam := clip as GDSkillClips.CameraEffectClip
		var m_row := HBoxContainer.new()
		var ml := Label.new()
		ml.text = "模式"
		ml.custom_minimum_size.x = 96
		m_row.add_child(ml)
		var m_opt := OptionButton.new()
		m_opt.add_item("PushToTarget", GDSkillTypes.SkillCameraEffectMode.PUSH_TO_TARGET)
		m_opt.add_item("PullFromTarget", GDSkillTypes.SkillCameraEffectMode.PULL_FROM_TARGET)
		m_opt.add_item("Shake", GDSkillTypes.SkillCameraEffectMode.SHAKE)
		m_opt.add_item("FocusTarget", GDSkillTypes.SkillCameraEffectMode.FOCUS_TARGET)
		m_opt.selected = cam.mode
		m_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m_opt.item_selected.connect(func(idx: int) -> void:
			cam.mode = idx
			call_deferred("rebuild_inspector")
		)
		m_row.add_child(m_opt)
		_inspector_box.add_child(m_row)

		match cam.mode:
			GDSkillTypes.SkillCameraEffectMode.PUSH_TO_TARGET, GDSkillTypes.SkillCameraEffectMode.PULL_FROM_TARGET:
				_add_prop_int_spin("作用对象 (0=Target,1=Self)", cam.target, 0, 1, func(v: int) -> void: cam.target = v)
				_add_prop_float_spin("Zoom 档位 [0,1]", cam.zoom01, 0.0, 1.0, func(v: float) -> void: cam.zoom01 = v)
			GDSkillTypes.SkillCameraEffectMode.FOCUS_TARGET:
				_add_prop_int_spin("作用对象 (0=Target,1=Self)", cam.target, 0, 1, func(v: int) -> void: cam.target = v)
			GDSkillTypes.SkillCameraEffectMode.SHAKE:
				_add_prop_float_spin("振幅", cam.amplitude, 0.0, 100.0, func(v: float) -> void: cam.amplitude = v)
				_add_prop_float_spin("频率", cam.frequency, 0.0, 200.0, func(v: float) -> void: cam.frequency = v)
	else:
		# 通用字段平铺
		var defs := GDSkillForgeAndCli.get_field_defs(short_name)
		for def in defs:
			var prop := str(def["prop"])
			var key := str(def["key"])
			var kind := str(def["kind"])
			var cur_val = clip.get(prop)
			match kind:
				"String":
					_add_prop_line_edit(key, str(cur_val), func(t: String) -> void: clip.set(prop, t))
				"Int":
					_add_prop_int_spin(key, int(cur_val), -99999, 99999, func(v: int) -> void: clip.set(prop, v))
				"Float":
					_add_prop_float_spin(key, float(cur_val), -99999.0, 99999.0, func(v: float) -> void: clip.set(prop, v))
				"Bool":
					var cb := CheckBox.new()
					cb.text = key
					cb.button_pressed = bool(cur_val)
					cb.toggled.connect(func(on: bool) -> void: clip.set(prop, on))
					_inspector_box.add_child(cb)
				"EnumInt":
					var evs: Array = def.get("enumValues", [])
					var er := HBoxContainer.new()
					var el := Label.new()
					el.text = key
					el.custom_minimum_size.x = 96
					er.add_child(el)
					var eo := OptionButton.new()
					for e_i in range(evs.size()):
						eo.add_item(str(evs[e_i]), e_i)
					eo.selected = clampi(int(cur_val), 0, maxi(0, evs.size() - 1))
					eo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					eo.item_selected.connect(func(idx: int) -> void: clip.set(prop, idx))
					er.add_child(eo)
					_inspector_box.add_child(er)

		# SpawnProjectile 轨迹子类型选择器
		if clip is GDSkillClips.SpawnProjectileClip:
			var sp := clip as GDSkillClips.SpawnProjectileClip
			var tr_row := HBoxContainer.new()
			var tr_lbl := Label.new()
			tr_lbl.text = "Trajectory"
			tr_lbl.custom_minimum_size.x = 96
			tr_row.add_child(tr_lbl)
			var tr_opt := OptionButton.new()
			var t_names := ["Linear", "Parabola", "Homing", "Bezier"]
			var cur_t := sp.trajectory.get_trajectory_type() if sp.trajectory != null else "Linear"
			var sel_t := 0
			for i in range(t_names.size()):
				tr_opt.add_item(t_names[i], i)
				if t_names[i] == cur_t:
					sel_t = i
			tr_opt.selected = sel_t
			tr_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tr_opt.item_selected.connect(func(idx: int) -> void:
				match idx:
					1: sp.trajectory = GDSkillClips.ParabolaTrajectory.new()
					2: sp.trajectory = GDSkillClips.HomingTrajectory.new()
					3: sp.trajectory = GDSkillClips.BezierTrajectory.new()
					_: sp.trajectory = GDSkillClips.LinearTrajectory.new()
				call_deferred("rebuild_inspector")
			)
			tr_row.add_child(tr_opt)
			_inspector_box.add_child(tr_row)

	var del_btn := Button.new()
	del_btn.text = "删除此片段"
	del_btn.pressed.connect(func() -> void: remove_clip(_sel_group_index, _sel_track_index, _sel_clip_index))
	GDEditorUi.style_button(del_btn, "danger")
	_inspector_box.add_child(del_btn)

func refresh_validate_panel() -> void:
	if _validate_box == null:
		return
	GDEditorUi.clear_children(_validate_box)
	if _selected_skill == null:
		return
	var issues := GDSkillEditorMathAndValidator.SkillAssetValidator.validate(_selected_skill)
	if issues.is_empty():
		var ok_lbl := Label.new()
		ok_lbl.text = "✔ 校验通过（无问题）"
		ok_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		_validate_box.add_child(ok_lbl)
		return
	for iss in issues:
		var err_lbl := Label.new()
		err_lbl.text = "[X] " + iss.format_issue()
		err_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		_validate_box.add_child(err_lbl)

# ─────────────────────── 结构编辑与播放状态机 ───────────────────────

func add_group() -> void:
	if _selected_skill == null:
		return
	var grp := GDSkillRes.SkillTrackGroup.new("Group%d" % _selected_skill.groups.size())
	_selected_skill.add_group(grp)
	select_group(_selected_skill.groups.size() - 1)
	refresh_validate_panel()

func remove_group(group_index: int) -> void:
	if _selected_skill == null or group_index < 0 or group_index >= _selected_skill.groups.size():
		return
	_selected_skill.groups.remove_at(group_index)
	_selection_kind = SelectionKind.HEADER
	_sel_group_index = -1
	rebuild_timeline()
	rebuild_inspector()
	refresh_validate_panel()

func add_track(group_index: int, kind: int) -> void:
	if _selected_skill == null or group_index < 0 or group_index >= _selected_skill.groups.size():
		return
	var grp = _selected_skill.groups[group_index]
	grp.add_track(GDSkillRes.SkillTrack.new(kind))
	select_track(group_index, grp.tracks.size() - 1)
	refresh_validate_panel()

func remove_track(group_index: int, track_index: int) -> void:
	if _selected_skill == null or group_index < 0 or group_index >= _selected_skill.groups.size():
		return
	var grp = _selected_skill.groups[group_index]
	if track_index < 0 or track_index >= grp.tracks.size():
		return
	grp.tracks.remove_at(track_index)
	_selection_kind = SelectionKind.GROUP
	_sel_track_index = -1
	rebuild_timeline()
	rebuild_inspector()
	refresh_validate_panel()

func add_clip(group_index: int, track_index: int, clip_short_name: String) -> void:
	if _selected_skill == null or group_index < 0 or group_index >= _selected_skill.groups.size():
		return
	var grp = _selected_skill.groups[group_index]
	if track_index < 0 or track_index >= grp.tracks.size():
		return
	var trk = grp.tracks[track_index]
	var clip := GDSkillForgeAndCli.create_clip_instance(clip_short_name)
	if clip == null:
		return
	clip.set_display_name(GDSkillForgeAndCli.get_display_name(clip_short_name))
	clip.set_timing(0, 0)
	trk.add_clip(clip)
	select_clip(group_index, track_index, trk.clips.size() - 1)
	refresh_validate_panel()

func remove_clip(group_index: int, track_index: int, clip_index: int) -> void:
	if _selected_skill == null or group_index < 0 or group_index >= _selected_skill.groups.size():
		return
	var grp = _selected_skill.groups[group_index]
	if track_index < 0 or track_index >= grp.tracks.size():
		return
	var trk = grp.tracks[track_index]
	if clip_index < 0 or clip_index >= trk.clips.size():
		return
	trk.clips.remove_at(clip_index)
	_selection_kind = SelectionKind.TRACK
	_sel_clip_index = -1
	rebuild_timeline()
	rebuild_inspector()
	refresh_validate_panel()

func _get_clip_at(g_idx: int, t_idx: int, c_idx: int) -> GDSkillClips.SkillClip:
	if _selected_skill == null or g_idx < 0 or g_idx >= _selected_skill.groups.size():
		return null
	var grp = _selected_skill.groups[g_idx]
	if grp == null or t_idx < 0 or t_idx >= grp.tracks.size():
		return null
	var trk = grp.tracks[t_idx]
	if trk == null or c_idx < 0 or c_idx >= trk.clips.size():
		return null
	return trk.clips[c_idx]

func _toggle_play_pause() -> void:
	if _selected_skill == null:
		return
	match _phase:
		PreviewPhase.IDLE, PreviewPhase.FINISHED:
			_playhead_ms = 0.0
			GDSkillTypes.SkillClock.reset_for_test()
			_phase = PreviewPhase.PLAYING
		PreviewPhase.PLAYING:
			# 暂停吸附到最近已触发的 Clip 起点
			var order := GDSkillRuntime.SkillRunner.build_dispatch_order(_selected_skill)
			_playhead_ms = float(GDSkillEditorMathAndValidator.SkillTimelineEditorMath.nearest_fired_clip_start(order, roundi(_playhead_ms)))
			_phase = PreviewPhase.PAUSED
		PreviewPhase.PAUSED:
			_phase = PreviewPhase.PLAYING
	_update_transport_visual()
	rebuild_timeline()

func _stop_preview() -> void:
	_phase = PreviewPhase.IDLE
	_playhead_ms = 0.0
	_update_transport_visual()
	rebuild_timeline()

func _update_transport_visual() -> void:
	if _play_pause_btn == null or _play_state_label == null:
		return
	_play_pause_btn.text = "⏸ 暂停" if _phase == PreviewPhase.PLAYING else "▶ 播放"
	var ms := roundi(_playhead_ms)
	match _phase:
		PreviewPhase.IDLE:
			_play_state_label.text = "就绪"
		PreviewPhase.PLAYING:
			_play_state_label.text = "预览中 %dms" % ms
		PreviewPhase.PAUSED:
			_play_state_label.text = "已暂停 %dms" % ms
		PreviewPhase.FINISHED:
			_play_state_label.text = "播放完毕"

func _add_prop_line_edit(label_text: String, val: String, on_changed: Callable) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 96
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.text = val
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(t: String) -> void: on_changed.call(t))
	row.add_child(edit)
	_inspector_box.add_child(row)

func _add_prop_int_spin(label_text: String, val: int, min_v: int, max_v: int, on_changed: Callable) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 96
	row.add_child(lbl)
	var sb := SpinBox.new()
	sb.step = 1
	sb.min_value = min_v
	sb.max_value = max_v
	sb.value = val
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.value_changed.connect(func(v: float) -> void: on_changed.call(roundi(v)))
	row.add_child(sb)
	_inspector_box.add_child(row)

func _add_prop_float_spin(label_text: String, val: float, min_v: float, max_v: float, on_changed: Callable) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 96
	row.add_child(lbl)
	var sb := SpinBox.new()
	sb.step = 0.05
	sb.min_value = min_v
	sb.max_value = max_v
	sb.value = val
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.value_changed.connect(func(v: float) -> void: on_changed.call(v))
	row.add_child(sb)
	_inspector_box.add_child(row)

func _open_new_skill_dialog() -> void:
	if _new_skill_dialog == null:
		_new_skill_dialog = NewSkillDialog.new()
		add_child(_new_skill_dialog)
		_new_skill_dialog.skill_created.connect(func(so: GDSkillRes) -> void:
			refresh_library()
			select_skill(so)
		)
	_new_skill_dialog.popup_centered()


## 「新建技能」弹窗（对应 NewSkillDialog）
class NewSkillDialog extends Window:
	signal skill_created(skill: GDSkillRes)

	const DEFAULT_SKILL_DIR := "res://game_res/skill"

	var _name_edit: LineEdit = null
	var _id_spin: SpinBox = null
	var _display_edit: LineEdit = null
	var _desc_edit: TextEdit = null
	var _dir_edit: LineEdit = null
	var _preview_label: Label = null
	var _create_btn: Button = null

	func _init() -> void:
		title = "新建技能"
		size = Vector2i(440, 320)
		close_requested.connect(hide)
		_build_ui()
		_update_preview()

	func _build_ui() -> void:
		var root := VBoxContainer.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		root.add_theme_constant_override("separation", 6)
		add_child(root)

		_name_edit = GDCoreAtomEditorWidgets.AtomCreatorWindow._add_labeled_line_edit(root, "技能名", "NewSkill")
		_name_edit.text_changed.connect(func(_t: String) -> void: _update_preview())

		var id_row := HBoxContainer.new()
		var id_lbl := Label.new()
		id_lbl.text = "技能 ID"
		id_lbl.custom_minimum_size.x = 110
		id_row.add_child(id_lbl)
		_id_spin = SpinBox.new()
		_id_spin.step = 1
		_id_spin.min_value = 0
		_id_spin.max_value = 999999
		_id_spin.value = 0
		_id_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_id_spin.value_changed.connect(func(_v: float) -> void: _update_preview())
		id_row.add_child(_id_spin)
		root.add_child(id_row)

		_display_edit = GDCoreAtomEditorWidgets.AtomCreatorWindow._add_labeled_line_edit(root, "显示名", "")
		_dir_edit = GDCoreAtomEditorWidgets.AtomCreatorWindow._add_labeled_line_edit(root, "保存目录", DEFAULT_SKILL_DIR)

		_desc_edit = TextEdit.new()
		_desc_edit.placeholder_text = "技能描述（可选）"
		_desc_edit.custom_minimum_size.y = 48
		root.add_child(_desc_edit)

		_preview_label = Label.new()
		_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(_preview_label)

		var btn_row := HBoxContainer.new()
		btn_row.alignment = BoxContainer.ALIGNMENT_END
		var cancel_btn := Button.new()
		cancel_btn.text = "取消"
		cancel_btn.pressed.connect(hide)
		btn_row.add_child(cancel_btn)

		_create_btn = Button.new()
		_create_btn.text = "创建"
		_create_btn.pressed.connect(_try_create)
		btn_row.add_child(_create_btn)
		root.add_child(btn_row)

	func _update_preview() -> void:
		var sname := _name_edit.text.strip_edges()
		var sid := roundi(_id_spin.value)
		var ok := GDSkillTypes.SkillIdentity.is_valid_name(sname) and sid >= 0
		_create_btn.disabled = not ok
		if ok:
			var cid := GDSkillTypes.SkillIdentity.to_asset_name(sname, sid)
			_preview_label.text = "UniqueName：%s\n路径：%s/%s.tres" % [cid, _dir_edit.text.trim_suffix("/"), cid]
			_preview_label.add_theme_color_override("font_color", Color(0.6, 0.88, 0.7))
		else:
			_preview_label.text = "技能名只能包含字母、数字、下划线且非数字开头；ID 必须 ≥ 0。"
			_preview_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))

	func _try_create() -> void:
		var sname := _name_edit.text.strip_edges()
		var sid := roundi(_id_spin.value)
		if not GDSkillTypes.SkillIdentity.is_valid_name(sname) or sid < 0:
			return
		var so := GDSkillRes.new()
		var disp := _display_edit.text.strip_edges()
		so.configure_header(sname, sid, disp if not disp.is_empty() else sname, _desc_edit.text)
		so.set_duration(1000)
		so.add_group(GDSkillRes.SkillTrackGroup.new("Cast"))
		so.resource_name = so.unique_name
		GDSkillForgeAndCli.register_in_memory_skill(so)
		skill_created.emit(so)
		hide()
