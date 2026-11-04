@tool
class_name GDSkillInspector
extends RefCounted

## 技能页右栏：没选中时是技能信息，否则是选中的组、轨道或片段。
## 片段字段来自 GDSkillForge.get_field_defs；相机按模式、投射物按轨迹类型换表单结构。

const TRAJECTORIES := ["Linear", "Parabola", "Homing", "Bezier"]
const CAMERA_FIELDS := {
	GDSkillTypes.SkillCameraEffectMode.PUSH_TO_TARGET: ["mode", "target", "zoom01"],
	GDSkillTypes.SkillCameraEffectMode.PULL_FROM_TARGET: ["mode", "target", "zoom01"],
	GDSkillTypes.SkillCameraEffectMode.SHAKE: ["mode", "amplitude", "frequency"],
	GDSkillTypes.SkillCameraEffectMode.FOCUS_TARGET: ["mode", "target"],
}
const REF_FILTERS := {
	"AudioStream": "*.wav, *.ogg, *.mp3 ; 音频",
	"PackedScene": "*.tscn, *.scn ; 场景",
	"Texture2D": "*.png, *.jpg, *.webp, *.svg ; 图片",
}
const FIELD_LABELS := {
	"state_name": "动画状态", "crossfade_seconds": "过渡秒数", "clip": "音频", "volume": "音量",
	"vfx_prefab": "特效", "anchor": "挂点", "display_prefab": "展示场景", "icon_override": "图标",
	"head_offset_y": "头顶高度", "display_seconds": "展示秒数", "mode": "模式", "target": "作用对象",
	"zoom01": "推拉程度", "amplitude": "振幅", "frequency": "频率", "offset": "偏移", "space": "坐标系",
	"move_duration_seconds": "位移秒数", "return_to_origin": "回到原位", "stop_frames": "停顿帧数",
	"reference_fps": "参考帧率", "time_scale": "时间缩放", "exempt_caster": "施法者不停", "exempt_target": "目标不停",
	"color": "颜色", "flash_seconds": "闪白秒数", "shake_duration_seconds": "抖动秒数", "prefab": "投射物",
	"speed": "速度", "direction": "方向", "reversed": "反向", "landing_offset": "落点偏移",
	"base_damage": "基础伤害", "coefficient": "系数", "damage_tag": "伤害标签", "shape": "形状",
	"radius_or_half_extent": "半径", "filter_tag": "过滤标签", "effect": "效果", "is_instant": "瞬时",
	"offset_from_target": "目标距离", "origin_recall_key": "召回键", "align_to_ground": "贴地",
	"arch_height": "弧高", "homing_strength": "追踪强度", "control_offset": "控制点偏移",
}

var form := GDForm.new()

var _page: GDSkillPage = null
var _identity_rejected: bool = false
var _identity_changed: bool = false


func _init(page: GDSkillPage) -> void:
	_page = page
	form.committed.connect(_on_committed)


func show(skill: GDSkillRes, path: PackedInt32Array) -> void:
	if skill == null:
		form.clear()
		return
	match path.size():
		1:
			_group(skill.groups[path[0]])
		2:
			_track(skill.groups[path[0]].tracks[path[1]])
		3:
			_clip(skill, skill.groups[path[0]].tracks[path[1]].clips[path[2]])
		_:
			_header(skill)


func _on_committed(label: String, merge: bool) -> void:
	if _page.doc == null:
		return
	if _identity_rejected:
		_identity_rejected = false
		return
	_page.doc.commit("修改%s" % label, merge)
	if _identity_changed:
		_identity_changed = false
		_page.save_current()


func _header(s: GDSkillRes) -> void:
	if not form.begin([s, &"header"]):
		return
	form.heading("技能")
	form.live_note(func() -> String: return s.unique_name, &"muted")
	form.text("名称", func() -> String: return s.skill_name, func(v: String) -> void: _try_identity(s, v, str(s.skill_id)))
	form.text("ID", func() -> String: return str(s.skill_id), func(v: String) -> void: _try_identity(s, s.skill_name, v))
	form.text("显示名", func() -> String: return s.display_name, func(v: String) -> void: s.display_name = v)
	form.text("描述", func() -> String: return s.description, func(v: String) -> void: s.description = v, {"multiline": true})
	form.text("消耗属性", func() -> String: return s.cost.attribute_name, func(v: String) -> void: s.set_cost(v, s.cost.amount))
	form.number("消耗数值", func() -> float: return s.cost.amount, func(v: float) -> void: s.set_cost(s.cost.attribute_name, v), {"min": 0.0, "step": 1.0})
	form.text("冷却分组", func() -> String: return s.cooldown.cd_group, func(v: String) -> void: s.set_cooldown(v, s.cooldown.duration_seconds))
	form.number("冷却时长", func() -> float: return s.cooldown.duration_seconds, func(v: float) -> void: s.set_cooldown(s.cooldown.cd_group, v), {"min": 0.0, "step": 0.1, "suffix": "s"})
	form.integer("总时长", func() -> int: return s.duration_ms, func(v: int) -> void:
		s.set_duration(maxi(v, GDSkillTimelineDrag.max_clip_end(s))), {"min": 10, "step": 10, "suffix": "ms"})


## 名称和 ID 决定文件名：合法且不冲突才写入，提交后立即保存，文件随之改名。
func _try_identity(s: GDSkillRes, skill_name: String, id_text: String) -> void:
	var error := _page.identity_error(s, skill_name, id_text)
	if not error.is_empty():
		_identity_rejected = true
		_page.say(error, &"danger")
		return
	s.skill_name = skill_name
	s.skill_id = id_text.to_int()
	_identity_changed = true


func _group(group: GDSkillRes.SkillTrackGroup) -> void:
	if form.begin([group]):
		form.heading("组", "%d 条轨道" % group.tracks.size())
		form.text("组名", func() -> String: return group.group_name, func(v: String) -> void: group.group_name = v)


func _track(track: GDSkillRes.SkillTrack) -> void:
	if not form.begin([track]):
		return
	form.heading("轨道", "%d 个片段" % track.clips.size())
	var kinds: Array = []
	for kind: int in GDSkillTypes.SkillTrackKind.values():
		kinds.append([GDSkillTypes.track_kind_label(kind), kind])
	form.choice("类别", kinds, func() -> int: return track.kind, func(v: int) -> void:
		if track.track_name == GDSkillTypes.track_kind_name(track.kind):
			track.track_name = GDSkillTypes.track_kind_name(v)
		track.kind = v
	)
	form.text("轨名", func() -> String: return track.track_name, func(v: String) -> void: track.track_name = v)


func _clip(skill: GDSkillRes, clip: GDSkillClips.SkillClip) -> void:
	var short_name := clip.get_clip_short_name()
	var camera := clip as GDSkillClips.CameraEffectClip
	var projectile := clip as GDSkillClips.SpawnProjectileClip
	var key: Array = [clip]
	if camera != null:
		key.append(camera.mode)
	if projectile != null:
		key.append(projectile.trajectory.get_trajectory_type() if projectile.trajectory != null else "")
	if not form.begin(key):
		return
	form.heading(GDSkillForge.get_display_name(short_name), short_name)
	form.integer("起始", func() -> int: return clip.start_ms, func(v: int) -> void:
		clip.set_timing(GDSkillTimelineMath.clamp_start(v, clip.duration_ms, skill.duration_ms), clip.duration_ms), {"min": 0, "step": 10, "suffix": "ms"})
	form.integer("时长", func() -> int: return clip.duration_ms, func(v: int) -> void:
		clip.set_timing(clip.start_ms, GDSkillTimelineMath.clamp_duration(clip.start_ms, v, skill.duration_ms, 0)), {"min": 0, "step": 10, "suffix": "ms"})
	form.text("显示名", func() -> String: return clip.display_name, func(v: String) -> void: clip.display_name = v)
	var only: Array = CAMERA_FIELDS.get(camera.mode, []) if camera != null else []
	for def in GDSkillForge.get_field_defs(short_name):
		if only.is_empty() or only.has(str(def["prop"])):
			_field(clip, def)
	if projectile != null:
		_trajectory(projectile)
	var remove := form.button("删除片段", func() -> void: _page.delete_selection(), &"danger")
	remove.size_flags_horizontal = Control.SIZE_SHRINK_END


func _field(clip: GDSkillClips.SkillClip, def: Dictionary) -> void:
	var prop := str(def["prop"])
	var label := str(FIELD_LABELS.get(prop, prop.capitalize()))
	var read := func() -> Variant: return clip.get(prop)
	var write := func(v: Variant) -> void: clip.set(prop, v)
	match str(def["kind"]):
		"String":
			form.text(label, read, write)
		"Float":
			form.number(label, read, write, {"step": 0.01})
		"Int":
			form.integer(label, read, write)
		"Bool":
			form.toggle(label, read, write)
		"EnumInt":
			var items: Array = []
			for value: String in def.get("enumValues", []):
				items.append([value, items.size()])
			form.choice(label, items, read, write)
		"Vec3":
			form.vector3(label, read, write)
		"Color":
			_color(label, read, write)
		"ObjectRef":
			_resource(label, clip, prop, str(def.get("refType", "Resource")))


func _trajectory(projectile: GDSkillClips.SpawnProjectileClip) -> void:
	var items: Array = []
	for name_text: String in TRAJECTORIES:
		items.append([name_text, items.size()])
	form.choice("轨迹", items, func() -> int: return TRAJECTORIES.find(projectile.trajectory.get_trajectory_type()), func(v: int) -> void:
		match v:
			1: projectile.trajectory = GDSkillClips.ParabolaTrajectory.new()
			2: projectile.trajectory = GDSkillClips.HomingTrajectory.new()
			3: projectile.trajectory = GDSkillClips.BezierTrajectory.new()
			_: projectile.trajectory = GDSkillClips.LinearTrajectory.new()
	)
	form.auto(projectile.trajectory, {"labels": FIELD_LABELS})


func _color(label: String, read: Callable, write: Callable) -> void:
	var picker := ColorPickerButton.new()
	picker.color = read.call()
	picker.custom_minimum_size.y = 26
	picker.popup_closed.connect(func() -> void:
		if picker.color != read.call():
			write.call(picker.color)
			form.committed.emit(label, false)
	)
	form.row(label, picker)


## 资源引用：路径输入框加选择文件，只接受对应类型的资源。
func _resource(label: String, target: Object, prop: String, ref_type: String) -> void:
	var path_of := func() -> String:
		var current: Resource = target.get(prop)
		return current.resource_path if current != null else ""
	var edit := LineEdit.new()
	edit.placeholder_text = "res://"
	edit.text = path_of.call()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var apply := func(path: String) -> void:
		path = path.strip_edges()
		if path == path_of.call():
			return
		var loaded: Resource = ResourceLoader.load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
		if not path.is_empty() and not ref_matches(loaded, ref_type):
			_page.say("不是 %s 资源：%s" % [ref_type, path], &"danger")
			edit.text = path_of.call()
			return
		target.set(prop, loaded)
		form.committed.emit(label, false)
	edit.text_submitted.connect(apply)
	edit.focus_exited.connect(func() -> void: apply.call(edit.text))
	var line := HBoxContainer.new()
	line.add_child(edit)
	line.add_child(GDEditorUi.tool_button(&"Load", "选择文件", func() -> void:
		var filter := str(REF_FILTERS.get(ref_type, "*.tres, *.res ; 资源"))
		GDDialogs.open_file(_page, "选择%s" % label, PackedStringArray([filter]), func(path: String) -> void:
			edit.text = path
			apply.call(path)
		)
	))
	form.row(label, line, ref_type)


static func ref_matches(res: Resource, ref_type: String) -> bool:
	if res == null:
		return false
	match ref_type:
		"GameplayTagRes":
			return res is GDGameplayTagRes
		"GameplayEffectRes":
			return res is GDGameplayEffectRes
	return res.is_class(ref_type)
