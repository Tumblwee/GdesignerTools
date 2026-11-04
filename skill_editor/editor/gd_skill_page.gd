@tool
class_name GDSkillPage
extends GDPage

## 技能编辑器：左边技能列表，中间时间轴，右边属性。
## 每个技能是一份独立文档，各自有撤销历史；文件名始终等于 unique_name，改名会移动文件。

const DEFAULT_CLIP_MS := 200
const ISSUE_TEXT := {
	"skill-name-missing": "技能名不合法", "skill-id-invalid": "ID 不合法", "skill-id-mismatch": "文件名与技能不一致",
	"no-groups": "没有轨道组", "group-missing": "组缺失", "group-name-missing": "组名为空",
	"group-name-duplicate": "组名重复", "clip-missing": "片段缺失", "duration-too-short": "总时长短于片段",
	"ref-missing": "引用缺失",
}

## 技能存放在 <skills_root>/skill。测试时可以指向 user://。
var skills_root: String = GDSkillForge.DEFAULT_MODULE_ROOT

var _skills: Array[GDSkillRes] = []
var _selection := PackedInt32Array()
var _playhead: float = 0.0
var _playing: bool = false
var _previewed: bool = false

var _list: GDLibraryList = null
var _view: GDSkillTimelineView = null
var _empty_host: VBoxContainer = null
var _empty_kind: String = "-"
var _issues_tree: Tree = null
var _inspector: GDSkillInspector = null
var _play_btn: Button = null
var _time_label: Label = null
var _badge: Button = null
## 只在打开了技能时可用的工具栏按钮。
var _skill_tools: Array[Button] = []

var skill: GDSkillRes:
	get:
		return doc.resource as GDSkillRes if doc != null else null


func _build() -> void:
	_play_btn = GDEditorUi.tool_button(&"Play", "播放", toggle_play, GDEditorUi.key(KEY_SPACE))
	_play_btn.shortcut_context = self
	_skill_tools.append(_play_btn)
	_skill_tools.append(GDEditorUi.tool_button(&"Stop", "停止", stop))
	for btn in _skill_tools:
		toolbar.add_child(btn)
	_time_label = GDEditorUi.muted_label("")
	_time_label.custom_minimum_size.x = 110
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toolbar.add_child(_time_label)
	toolbar.add_child(VSeparator.new())
	var snap := GDEditorUi.tool_button(&"Snap", "吸附到网格、片段边缘和播放头，按住 Shift 临时关闭", func() -> void: pass)
	snap.toggle_mode = true
	snap.button_pressed = true
	snap.toggled.connect(func(on: bool) -> void: _view.snap_enabled = on)
	toolbar.add_child(snap)

	_badge = Button.new()
	_badge.flat = true
	_badge.focus_mode = Control.FOCUS_NONE
	_badge.tooltip_text = "显示或隐藏校验结果"
	_badge.pressed.connect(func() -> void: _issues_tree.visible = not _issues_tree.visible)
	toolbar_right.add_child(_badge)
	toolbar_right.add_child(VSeparator.new())
	var fit := GDEditorUi.text_button("适配", func() -> void: _view.fit(), &"flat")
	fit.flat = true
	fit.focus_mode = Control.FOCUS_NONE
	fit.tooltip_text = "整个技能放进视图"
	for btn: Button in [GDEditorUi.tool_button(&"ZoomLess", "缩小", func() -> void: _view.zoom_by(1.0 / 1.5)),
			GDEditorUi.tool_button(&"ZoomMore", "放大", func() -> void: _view.zoom_by(1.5)), fit]:
		_skill_tools.append(btn)
		toolbar_right.add_child(btn)
	toolbar_right.add_child(GDEditorUi.menu_button("", &"GuiTabMenuHl", "更多", [{"text": "刷新技能列表", "do": refresh_library}]))

	_list = GDLibraryList.new("技能", "搜索名称或 ID")
	_list.header.add_child(GDEditorUi.tool_button(&"Add", "新建技能", _new_skill))
	_list.set_empty_state(GDEditorUi.empty_state("还没有技能", "", "新建技能", _new_skill))
	_list.item_selected.connect(select_skill)
	_list.context_requested.connect(_show_skill_menu)
	_list.rename_requested.connect(_rename_skill)
	_list.duplicate_requested.connect(duplicate_skill)
	_list.delete_requested.connect(_confirm_delete_skill)

	_view = GDSkillTimelineView.new()
	_view.selection_changed.connect(func(path: PackedInt32Array) -> void:
		_selection = path
		_inspector.show(skill, _selection)
	)
	_view.edited.connect(func(label: String, merge: bool) -> void: doc.commit(label, merge))
	_view.scrubbed.connect(func(ms: float) -> void:
		_playhead = ms
		_sync_transport()
	)
	_view.context_requested.connect(_show_timeline_menu)
	_view.add_requested.connect(func(path: PackedInt32Array, ms: int) -> void:
		GDEditorUi.context_menu(self, _track_kind_items(path[0]) if path.size() == 1 else clip_menu_items(path[0], path[1], ms))
	)
	_view.delete_requested.connect(_delete_path)
	_view.duplicate_requested.connect(func(path: PackedInt32Array) -> void: duplicate_clip(path[0], path[1], path[2]))
	_empty_host = VBoxContainer.new()
	_empty_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_issues_tree = Tree.new()
	_issues_tree.hide_root = true
	_issues_tree.custom_minimum_size.y = 96
	_issues_tree.visible = false
	_issues_tree.item_selected.connect(_on_issue_selected)
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 0)
	for part: Control in [_view, _empty_host, _issues_tree]:
		center.add_child(part)

	_inspector = GDSkillInspector.new(self)
	set_panes(GDEditorUi.pane(_list), GDEditorUi.pane(center, 0), GDEditorUi.pane(GDEditorUi.scroll_of(_inspector.form)))
	refresh_library()


func _ready() -> void:
	set_process(_playing)


func activate() -> void:
	if skill == null:
		refresh_library()


func cli_context(command: String) -> PackedStringArray:
	if skill != null and command in ["skill.describe", "skill.validate", "skill.preview.cast"]:
		return PackedStringArray(["--skill", skill.unique_name])
	return PackedStringArray()


func refresh_library() -> void:
	_skills = GDSkillForge.get_all_known_skills(skills_root)
	_skills.sort_custom(func(a: GDSkillRes, b: GDSkillRes) -> bool: return a.skill_id < b.skill_id)
	if skill == null and not _skills.is_empty():
		select_skill(_skills[0])
	else:
		_refresh()


func select_skill(target: GDSkillRes) -> void:
	_playing = false
	set_process(false)
	_playhead = 0.0
	_previewed = false
	_selection = PackedInt32Array()
	open_document(target)
	_view.skill = target
	_view.fit()
	_refresh()


## 选中 [组]、[组, 轨道] 或 [组, 轨道, 片段]；空表示技能本身。
func select_path(path: PackedInt32Array) -> void:
	_selection = path
	_refresh()


func get_selection() -> PackedInt32Array:
	return _selection


func _suggest_save_path(resource: Resource) -> String:
	return _path_for(resource as GDSkillRes, (resource as GDSkillRes).unique_name)


## 存到 unique_name 对应的文件；改过名就把旧文件移进回收站。
func _save(target: GDDocument) -> void:
	var saved := target.resource as GDSkillRes
	var old_path := saved.resource_path
	var path := _path_for(saved, saved.unique_name)
	saved.resource_name = saved.unique_name
	var err := target.save(path)
	if err == OK:
		GDSkillForge.register_in_memory_skill(saved)
		if not old_path.is_empty() and old_path != path:
			_trash(old_path)
	_report_save(target, err)


func _path_for(target: GDSkillRes, unique_name: String) -> String:
	if target != null and not target.resource_path.is_empty():
		return target.resource_path.get_base_dir().path_join(unique_name + ".tres")
	return GDSkillForge.skill_asset_path(unique_name, skills_root)


# ── 刷新 ──

func _refresh() -> void:
	_selection = _resolved(_selection)
	_refresh_list()
	_refresh_center()
	_inspector.show(skill, _selection)
	_refresh_issues()
	_sync_transport()


func _refresh_list() -> void:
	var rows: Array = []
	for item in _skills:
		rows.append({
			"key": item,
			"text": item.display_name if not item.display_name.is_empty() else item.skill_name,
			"detail": "#%d" % item.skill_id,
			"color": GDEditorUi.hue_color(item.skill_id),
			"tooltip": item.unique_name,
		})
	_list.set_items([{"title": "", "items": rows}])
	_list.select_key(skill)


func _refresh_center() -> void:
	var kind := "none" if skill == null else ("empty" if skill.groups.is_empty() else "")
	_view.visible = kind.is_empty()
	_empty_host.visible = not kind.is_empty()
	if kind != _empty_kind:
		_empty_kind = kind
		GDEditorUi.clear_children(_empty_host)
		if kind == "none":
			_empty_host.add_child(GDEditorUi.empty_state("没有选中技能"))
		elif kind == "empty":
			_empty_host.add_child(GDEditorUi.empty_state("还没有轨道组", "", "添加组", add_group))
	_view.skill = skill
	_view.selection = _selection
	_view.refresh()


func _refresh_issues() -> void:
	_badge.visible = skill != null
	_issues_tree.clear()
	if skill == null:
		_issues_tree.visible = false
		return
	var issues := GDSkillValidation.SkillAssetValidator.validate(skill)
	var root := _issues_tree.create_item()
	for issue in issues:
		var item := root.create_child()
		item.set_text(0, "%s　%s" % [ISSUE_TEXT.get(issue.code, issue.code), issue.detail])
		item.set_custom_color(0, GDEditorUi.tone(&"danger"))
		item.set_metadata(0, issue.path)
		item.set_selectable(0, not issue.path.is_empty())
	if issues.is_empty():
		root.create_child().set_text(0, "校验通过")
	_badge.text = "✓ 校验通过" if issues.is_empty() else "✕ %d 个问题" % issues.size()
	var tone := GDEditorUi.tone(&"ok" if issues.is_empty() else &"danger")
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_badge.add_theme_color_override(state, tone)


func _on_issue_selected() -> void:
	var path: Variant = _issues_tree.get_selected().get_metadata(0)
	if path is PackedInt32Array and not path.is_empty():
		# 刷新会重建这棵树，不能在它自己的信号里做。
		select_path.call_deferred(path)
		_view.reveal.call_deferred(path)


# ── 播放 ──

func toggle_play() -> void:
	if skill == null:
		return
	if not _playing and _playhead >= skill.duration_ms:
		_playhead = 0.0
	_playing = not _playing
	_previewed = true
	set_process(_playing)
	_sync_transport()


func stop() -> void:
	_playing = false
	_previewed = false
	_playhead = 0.0
	set_process(false)
	_sync_transport()


func is_playing() -> bool:
	return _playing


func get_playhead() -> float:
	return _playhead


func _process(delta: float) -> void:
	if skill == null:
		stop()
		return
	_playhead = minf(_playhead + delta * 1000.0, skill.duration_ms)
	if _playhead >= skill.duration_ms:
		_playing = false
		set_process(false)
	_sync_transport()


func _sync_transport() -> void:
	var icon_name := &"Pause" if _playing else &"Play"
	var tex := GDEditorUi.icon(icon_name)
	if tex != null:
		_play_btn.icon = tex
	else:
		_play_btn.text = str(GDEditorUi.GLYPHS[icon_name])
	_play_btn.tooltip_text = "暂停" if _playing else "播放"
	for btn in _skill_tools:
		btn.disabled = skill == null
	var total := float(skill.duration_ms) if skill != null else 0.0
	_time_label.text = "%.2f s / %.2f s" % [_playhead / 1000.0, total / 1000.0]
	_view.show_fired = _previewed
	_view.set_playhead(_playhead, _playing)


func identity_error(s: GDSkillRes, skill_name: String, id_text: String) -> String:
	if not GDSkillTypes.SkillIdentity.is_valid_name(skill_name):
		return "技能名只能用英文字母、数字和下划线，且不以数字开头"
	if not id_text.is_valid_int() or id_text.to_int() < 0:
		return "ID 必须是非负整数"
	var unique_name := GDSkillTypes.SkillIdentity.to_asset_name(skill_name, id_text.to_int())
	if s != null and unique_name == s.unique_name:
		return ""
	for other in _skills:
		if other != s and other.unique_name == unique_name:
			return "已有技能 %s" % unique_name
	var path := _path_for(s, unique_name)
	return "文件已存在：%s" % path if FileAccess.file_exists(path) else ""


# ── 结构编辑 ──

func add_group() -> void:
	if skill == null:
		return
	var taken := skill.groups.map(func(g: GDSkillRes.SkillTrackGroup) -> String: return g.group_name)
	var index := skill.groups.size() + 1
	while taken.has("Group%d" % index):
		index += 1
	skill.groups.append(GDSkillRes.SkillTrackGroup.new("Group%d" % index))
	_selection = PackedInt32Array([skill.groups.size() - 1])
	doc.commit("添加组")


func add_track(g: int, kind: int) -> void:
	var group: GDSkillRes.SkillTrackGroup = skill.groups[g]
	group.add_track(GDSkillRes.SkillTrack.new(kind))
	_selection = PackedInt32Array([g, group.tracks.size() - 1])
	doc.commit("添加轨道")


## start_ms 为 -1 时放在播放头。瞬时类片段时长为 0，其余默认 200 ms。
func add_clip(g: int, t: int, short_name: String, start_ms: int = -1) -> GDSkillClips.SkillClip:
	var clip := GDSkillForge.create_clip_instance(short_name)
	if clip == null:
		return null
	var total := skill.duration_ms
	var dur := 0 if GDSkillForge.is_instant_clip_type(short_name) else mini(DEFAULT_CLIP_MS, total)
	var start := roundi(_playhead) if start_ms < 0 else start_ms
	clip.set_timing(GDSkillTimelineMath.clamp_start(start, dur, total), dur)
	clip.display_name = GDSkillForge.get_display_name(short_name)
	var track := _track_of(PackedInt32Array([g, t]))
	track.add_clip(clip)
	_selection = PackedInt32Array([g, t, track.clips.size() - 1])
	doc.commit("添加片段")
	return clip


func remove_clip(g: int, t: int, c: int) -> void:
	_track_of(PackedInt32Array([g, t])).clips.remove_at(c)
	_selection = PackedInt32Array([g, t])
	doc.commit("删除片段")


func duplicate_clip(g: int, t: int, c: int) -> void:
	var track := _track_of(PackedInt32Array([g, t]))
	var source: GDSkillClips.SkillClip = track.clips[c]
	var copy: GDSkillClips.SkillClip = GDSkillRes.codec().decode(GDSkillRes.codec().encode(source))
	var start := source.start_ms + maxi(source.duration_ms, GDSkillTimelineDrag.MIN_CLIP_MS)
	copy.set_timing(GDSkillTimelineMath.clamp_start(start, copy.duration_ms, skill.duration_ms), copy.duration_ms)
	track.clips.insert(c + 1, copy)
	_selection = PackedInt32Array([g, t, c + 1])
	doc.commit("复制片段")


func remove_track(g: int, t: int) -> void:
	skill.groups[g].tracks.remove_at(t)
	_selection = PackedInt32Array([g])
	doc.commit("删除轨道")


func move_track(g: int, t: int, step: int) -> void:
	var tracks: Array = skill.groups[g].tracks
	var track: Variant = tracks.pop_at(t)
	tracks.insert(t + step, track)
	_selection = PackedInt32Array([g, t + step])
	doc.commit("移动轨道")


func remove_group(g: int) -> void:
	skill.groups.remove_at(g)
	_selection = PackedInt32Array()
	doc.commit("删除组")


func delete_selection() -> void:
	_delete_path(_selection)


func _delete_path(path: PackedInt32Array) -> void:
	match path.size():
		1: remove_group(path[0])
		2: remove_track(path[0], path[1])
		3: remove_clip(path[0], path[1], path[2])


func _rename_row(path: PackedInt32Array) -> void:
	var target: Object = skill.groups[path[0]] if path.size() == 1 else _track_of(path)
	var prop := "group_name" if path.size() == 1 else "track_name"
	GDDialogs.prompt(self, "重命名", "组名" if path.size() == 1 else "轨名", str(target.get(prop)), func(value: String) -> void:
		target.set(prop, value)
		doc.commit("重命名")
	, func(value: String) -> String: return "名字不能为空" if value.strip_edges().is_empty() else "")


func _resolved(path: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if skill == null or path.is_empty() or path[0] < 0 or path[0] >= skill.groups.size():
		return out
	out.append(path[0])
	var tracks: Array = skill.groups[path[0]].tracks
	if path.size() < 2 or path[1] < 0 or path[1] >= tracks.size():
		return out
	out.append(path[1])
	if path.size() >= 3 and path[2] >= 0 and path[2] < tracks[path[1]].clips.size():
		out.append(path[2])
	return out


func _track_of(path: PackedInt32Array) -> GDSkillRes.SkillTrack:
	return skill.groups[path[0]].tracks[path[1]]


func _clip_of(path: PackedInt32Array) -> GDSkillClips.SkillClip:
	return _track_of(path).clips[path[2]]


# ── 菜单 ──

## 先列这类轨道推荐的片段，其余放进“其他”。
func clip_menu_items(g: int, t: int, ms: int) -> Array:
	var recommended := GDSkillForge.clip_types_for_kind(_track_of(PackedInt32Array([g, t])).kind)
	var items: Array = []
	var others: Array = []
	for short_name in GDSkillForge.clip_types():
		var entry := {"text": GDSkillForge.get_display_name(short_name), "do": func() -> void: add_clip(g, t, short_name, ms)}
		(items if recommended.has(short_name) else others).append(entry)
	if items.is_empty():
		return others
	items.append(null)
	items.append({"text": "其他", "items": others})
	return items


func _track_kind_items(g: int) -> Array:
	var items: Array = []
	for kind: int in GDSkillTypes.SkillTrackKind.values():
		items.append({"text": GDSkillTypes.track_kind_label(kind), "do": func() -> void: add_track(g, kind)})
	return items


func _show_timeline_menu(path: PackedInt32Array, ms: int) -> void:
	match path.size():
		0:
			GDEditorUi.context_menu(self, [{"text": "添加组", "do": add_group}])
		1:
			GDEditorUi.context_menu(self, [
				{"text": "添加轨道", "items": _track_kind_items(path[0])},
				{"text": "重命名…", "do": func() -> void: _rename_row(path)},
				null,
				{"text": "删除组", "do": func() -> void: remove_group(path[0]), "shortcut": GDEditorUi.key(KEY_DELETE)},
			])
		2:
			var count: int = skill.groups[path[0]].tracks.size()
			GDEditorUi.context_menu(self, [
				{"text": "添加片段", "items": clip_menu_items(path[0], path[1], ms)},
				{"text": "重命名…", "do": func() -> void: _rename_row(path)},
				null,
				{"text": "上移", "do": func() -> void: move_track(path[0], path[1], -1), "disabled": path[1] == 0},
				{"text": "下移", "do": func() -> void: move_track(path[0], path[1], 1), "disabled": path[1] >= count - 1},
				null,
				{"text": "删除轨道", "do": func() -> void: remove_track(path[0], path[1]), "shortcut": GDEditorUi.key(KEY_DELETE)},
			])
		3:
			GDEditorUi.context_menu(self, [
				{"text": "复制", "do": func() -> void: duplicate_clip(path[0], path[1], path[2]), "shortcut": GDEditorUi.key(KEY_D, true)},
				{"text": "删除", "do": func() -> void: remove_clip(path[0], path[1], path[2]), "shortcut": GDEditorUi.key(KEY_DELETE)},
			])


# ── 技能库 ──

func _show_skill_menu(key: Variant) -> void:
	if key == null:
		GDEditorUi.context_menu(self, [{"text": "新建技能…", "do": _new_skill}])
		return
	var target: GDSkillRes = key
	GDEditorUi.context_menu(self, [
		{"text": "重命名…", "do": func() -> void: _rename_skill(target), "shortcut": GDEditorUi.key(KEY_F2)},
		{"text": "复制", "do": func() -> void: duplicate_skill(target), "shortcut": GDEditorUi.key(KEY_D, true)},
		null,
		{"text": "从磁盘删除…", "do": func() -> void: _confirm_delete_skill(target), "shortcut": GDEditorUi.key(KEY_DELETE)},
	])


func _new_skill() -> void:
	GDDialogs.form(self, "新建技能", [
		{"key": "name", "label": "技能名", "value": "NewSkill", "placeholder": "英文标识符"},
		{"key": "id", "label": "ID", "value": str(_next_id())},
		{"key": "display", "label": "显示名", "value": "新技能"},
	], func(values: Dictionary) -> void:
		create_skill(str(values["name"]), str(values["id"]).to_int(), str(values["display"]))
	, func(values: Dictionary) -> String:
		return identity_error(null, str(values["name"]), str(values["id"]))
	)


## 新技能：1 秒、一个 Cast 组、一条轨道，立即存盘并选中。
func create_skill(skill_name: String, skill_id: int, display: String) -> GDSkillRes:
	var created := GDSkillRes.new()
	created.configure_header(skill_name, skill_id, display if not display.is_empty() else skill_name, "")
	created.set_duration(1000)
	var group := GDSkillRes.SkillTrackGroup.new("Cast")
	group.add_track(GDSkillRes.SkillTrack.new(GDSkillTypes.SkillTrackKind.ANIMATION))
	created.add_group(group)
	_adopt(created)
	return created


func duplicate_skill(source: GDSkillRes) -> GDSkillRes:
	var copy := GDSkillRes.new()
	copy.configure_header(source.skill_name, _next_id(), "%s 副本" % doc_title(source), source.description)
	copy.codec_data = source.codec_data
	copy.duration_ms = source.duration_ms
	copy.icon = source.icon
	copy.set_tags(source.required_tags.duplicate(), source.blocked_tags.duplicate())
	_adopt(copy)
	return copy


func _adopt(created: GDSkillRes) -> void:
	created.resource_name = created.unique_name
	_skills.append(created)
	select_skill(created)
	save_current()


func _rename_skill(target: GDSkillRes) -> void:
	GDDialogs.form(self, "重命名技能", [
		{"key": "name", "label": "技能名", "value": target.skill_name},
		{"key": "id", "label": "ID", "value": str(target.skill_id)},
		{"key": "display", "label": "显示名", "value": target.display_name},
	], func(values: Dictionary) -> void:
		rename_skill(target, str(values["name"]), str(values["id"]).to_int(), str(values["display"]))
	, func(values: Dictionary) -> String:
		return identity_error(target, str(values["name"]), str(values["id"]))
	)


## 改名会得到新的 unique_name，文件跟着移动；撤销后再保存会移回去。
func rename_skill(target: GDSkillRes, skill_name: String, skill_id: int, display: String) -> void:
	if target != skill:
		select_skill(target)
	target.skill_name = skill_name
	target.skill_id = skill_id
	target.display_name = display
	doc.commit("重命名技能")
	save_current()


func _confirm_delete_skill(target: GDSkillRes) -> void:
	GDDialogs.confirm(self, "删除技能", "「%s」的文件会移到回收站。" % doc_title(target), "删除", func() -> void: delete_skill_from_disk(target))


func delete_skill_from_disk(target: GDSkillRes) -> void:
	var title := doc_title(target)
	var index := _skills.find(target)
	if not target.resource_path.is_empty():
		_trash(target.resource_path)
		target.resource_path = ""
	GDSkillForge.unregister_in_memory_skill(target)
	_skills.erase(target)
	close_document(target)
	if skill == null:
		select_skill(_skills[mini(index, _skills.size() - 1)] if not _skills.is_empty() else null)
	else:
		_refresh()
	say("已将「%s」移到回收站" % title)


func _trash(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if OS.move_to_trash(absolute) != OK:
		DirAccess.remove_absolute(absolute)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)


func _next_id() -> int:
	var highest := 1000
	for item in _skills:
		highest = maxi(highest, item.skill_id)
	return highest + 1
