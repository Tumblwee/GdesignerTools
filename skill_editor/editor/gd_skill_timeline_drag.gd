@tool
class_name GDSkillTimelineDrag
extends RefCounted

## 时间轴上的一次拖拽：按下时记下原值，移动时算出吸附后的草稿，松手才写回模型。
## Esc 取消就是丢掉这个对象，模型从头到尾没被碰过。

enum Mode { NONE, SCRUB, END, MOVE, TRIM_LEFT, TRIM_RIGHT, PAN }

const SNAP_PX := 6.0
const GRID_MS := 10.0
const MIN_CLIP_MS := 10

var mode: int = Mode.NONE
var path := PackedInt32Array()
var press := Vector2.ZERO
## 移动超过 3 像素才算拖拽，单击不提交。
var active: bool = false
var start: int = 0
var dur: int = 0
## 目标轨道 [组, 轨道]，竖向拖动会改变它。
var track := PackedInt32Array()
var duration: int = 0
## 吸附参考线所在时刻，-1 表示没有吸附。
var guide_ms: float = -1.0

var _orig_start: int = 0
var _orig_dur: int = 0
var _magnets := PackedFloat32Array()


func _init(p_mode: int = Mode.NONE, p_press: Vector2 = Vector2.ZERO, skill: GDSkillRes = null, p_path := PackedInt32Array(), playhead_ms: float = 0.0) -> void:
	mode = p_mode
	press = p_press
	path = p_path
	active = mode == Mode.SCRUB or mode == Mode.PAN
	if skill == null:
		return
	duration = skill.duration_ms
	var clip := clip_at(skill, path)
	if clip != null:
		_orig_start = clip.start_ms
		_orig_dur = clip.duration_ms
		start = _orig_start
		dur = _orig_dur
		track = path.slice(0, 2)
	_magnets = PackedFloat32Array([0.0, playhead_ms, float(skill.duration_ms)])
	for g in range(skill.groups.size()):
		for t in range(skill.groups[g].tracks.size()):
			var clips: Array = skill.groups[g].tracks[t].clips
			for c in range(clips.size()):
				if path != PackedInt32Array([g, t, c]):
					_magnets.append(clips[c].start_ms)
					_magnets.append(clips[c].start_ms + clips[c].duration_ms)


## delta_ms：水平位移换算的毫秒；at_ms：指针所在时刻；row_track：指针下的轨道（可为空）。
func update(skill: GDSkillRes, delta_ms: float, at_ms: float, row_track: PackedInt32Array, pixels_per_ms: float, snapping: bool) -> void:
	var total := skill.duration_ms
	var end := _orig_start + _orig_dur
	match mode:
		Mode.END:
			duration = maxi(maxi(max_clip_end(skill), MIN_CLIP_MS), roundi(snap(at_ms, pixels_per_ms, snapping)))
		Mode.MOVE:
			start = GDSkillTimelineMath.clamp_start(roundi(_snap_span(_orig_start + delta_ms, pixels_per_ms, snapping)), _orig_dur, total)
			if row_track.size() == 2:
				track = row_track
		Mode.TRIM_RIGHT:
			var new_end := roundi(snap(end + delta_ms, pixels_per_ms, snapping))
			dur = GDSkillTimelineMath.clamp_duration(start, new_end - start, total, MIN_CLIP_MS)
		Mode.TRIM_LEFT:
			start = clampi(roundi(snap(_orig_start + delta_ms, pixels_per_ms, snapping)), 0, end - MIN_CLIP_MS)
			dur = end - start


## 吸附优先级：6 像素内的片段边缘、播放头、0 与总时长，否则 10 ms 网格。
func snap(ms: float, pixels_per_ms: float, snapping: bool) -> float:
	guide_ms = -1.0
	if not snapping:
		return roundf(ms)
	var target := _magnet(ms, pixels_per_ms)
	if is_nan(target):
		return snappedf(ms, GRID_MS)
	guide_ms = target
	return target


## 写回模型。返回撤销步骤名，没有变化时返回空串；跨轨道时 path 改成新位置。
func apply(skill: GDSkillRes) -> String:
	if not active:
		return ""
	if mode == Mode.END:
		if duration == skill.duration_ms:
			return ""
		skill.set_duration(duration)
		return "修改总时长"
	var clip := clip_at(skill, path)
	var origin := path.slice(0, 2)
	if clip == null or (track == origin and start == _orig_start and dur == _orig_dur):
		return ""
	clip.set_timing(start, dur)
	if track != origin:
		skill.groups[origin[0]].tracks[origin[1]].clips.remove_at(path[2])
		var target: Array = skill.groups[track[0]].tracks[track[1]].clips
		target.append(clip)
		path = PackedInt32Array([track[0], track[1], target.size() - 1])
	return "移动片段" if mode == Mode.MOVE else "调整片段时长"


static func clip_at(skill: GDSkillRes, at: PackedInt32Array) -> GDSkillClips.SkillClip:
	if skill == null or at.size() < 3 or at[0] < 0 or at[0] >= skill.groups.size():
		return null
	var tracks: Array = skill.groups[at[0]].tracks
	if at[1] < 0 or at[1] >= tracks.size() or at[2] < 0 or at[2] >= tracks[at[1]].clips.size():
		return null
	return tracks[at[1]].clips[at[2]]


static func max_clip_end(skill: GDSkillRes) -> int:
	var end := 0
	for group: GDSkillRes.SkillTrackGroup in skill.groups:
		for each: GDSkillRes.SkillTrack in group.tracks:
			for clip: GDSkillClips.SkillClip in each.clips:
				end = maxi(end, clip.start_ms + clip.duration_ms)
	return end


## 移动时两端都能吸附，取更近的一端。
func _snap_span(ms: float, pixels_per_ms: float, snapping: bool) -> float:
	guide_ms = -1.0
	if not snapping:
		return roundf(ms)
	var head := _magnet(ms, pixels_per_ms)
	var tail := _magnet(ms + _orig_dur, pixels_per_ms) if _orig_dur > 0 else NAN
	if not is_nan(head) and (is_nan(tail) or absf(head - ms) <= absf(tail - ms - _orig_dur)):
		guide_ms = head
		return head
	if not is_nan(tail):
		guide_ms = tail
		return tail - _orig_dur
	return snappedf(ms, GRID_MS)


func _magnet(ms: float, pixels_per_ms: float) -> float:
	var best := NAN
	var reach := SNAP_PX / pixels_per_ms
	for point in _magnets:
		if absf(point - ms) <= reach and (is_nan(best) or absf(point - ms) < absf(best - ms)):
			best = point
	return best
