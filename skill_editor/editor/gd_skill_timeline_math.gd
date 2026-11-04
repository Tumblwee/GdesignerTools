@tool
class_name GDSkillTimelineMath
extends RefCounted

## 技能时间轴编辑器数学（对应 SkillTimelineEditorMath）：拖拽起点 / 时长钳制与回放定位。

## 起点钳在 [0, total - clip_duration]。
static func clamp_start(start_ms: int, clip_duration_ms: int, total_duration_ms: int) -> int:
	return clampi(start_ms, 0, maxi(0, total_duration_ms - maxi(0, clip_duration_ms)))

## 时长钳在 [min_ms, total - start]（上限不小于 min_ms）。
static func clamp_duration(start_ms: int, new_duration_ms: int, total_duration_ms: int, min_ms: int) -> int:
	var mn := maxi(0, min_ms)
	return clampi(new_duration_ms, mn, maxi(mn, total_duration_ms - maxi(0, start_ms)))

## 播放头之前（含）最近一个已触发 Clip 的起点；没有则 0。
static func nearest_fired_clip_start(dispatch_order: Array, playhead_ms: int) -> int:
	var best := 0
	for item in dispatch_order:
		if item is GDSkillClips.SkillClip and item.start_ms <= playhead_ms and item.start_ms > best:
			best = item.start_ms
	return best
