@tool
class_name GDSkillData
extends RefCounted

## 技能编辑器 (GAS · 单资产 SkillSO 模型) 完整数据结构
## 对应 SkillClipEnums / SkillIdentity / GameplayTagSO / GameplayEffectSO / GameplayEffectModifier / BuiltInTrajectories / 15 类 SkillClip / SkillTrack / SkillTrackGroup / SkillSO

enum SkillTrackKind {
	ANIMATION = 0,
	MOVEMENT = 1,
	HITBOX = 2,
	EFFECT = 3,
	AUDIO = 4,
	CAMERA = 5,
	VFX = 6,
}

enum SkillHitShapeKind {
	SPHERE = 0,
	BOX = 1,
}

enum SkillProjectileDirectionKind {
	TO_TARGET = 0,
	CASTER_FORWARD = 1,
}

enum SkillTeleportModeKind {
	TO_TARGET_SIDE = 0,
	BACK_TO_ORIGIN = 1,
}

enum SkillVfxAnchorKind {
	CASTER_ROOT = 0,
	CASTER_HAND = 1,
	TARGET_ROOT = 2,
}

enum SkillCameraEffectMode {
	PUSH_TO_TARGET = 0,
	PULL_FROM_TARGET = 1,
	SHAKE = 2,
	FOCUS_TARGET = 3,
}

enum SkillCameraTargetKind {
	TARGET = 0,
	SELF = 1,
}

enum SkillVisualMoveSpace {
	LOCAL = 0,
	CASTER_FORWARD = 1,
	TOWARD_TARGET = 2,
}

enum ModifierOp {
	ADD = 0,
	MULTIPLY = 1,
	OVERRIDE = 2,
}

enum AttributeKind {
	NONE = 0,
	HEALTH = 1,
	MANA = 2,
	STAMINA = 3,
	ATTACK_POWER = 4,
	DEFENSE = 5,
	MOVE_SPEED = 6,
}

static func track_kind_name(k: int) -> String:
	match k:
		SkillTrackKind.ANIMATION: return "Animation"
		SkillTrackKind.MOVEMENT: return "Movement"
		SkillTrackKind.HITBOX: return "Hitbox"
		SkillTrackKind.EFFECT: return "Effect"
		SkillTrackKind.AUDIO: return "Audio"
		SkillTrackKind.CAMERA: return "Camera"
		SkillTrackKind.VFX: return "Vfx"
		_: return "Effect"

static func parse_track_kind(raw: String) -> int:
	match raw.strip_edges().to_lower():
		"animation": return SkillTrackKind.ANIMATION
		"movement": return SkillTrackKind.MOVEMENT
		"hitbox": return SkillTrackKind.HITBOX
		"effect": return SkillTrackKind.EFFECT
		"audio": return SkillTrackKind.AUDIO
		"camera": return SkillTrackKind.CAMERA
		"vfx": return SkillTrackKind.VFX
		_: return SkillTrackKind.EFFECT


## SkillIdentity：技能资产身份拼法与解析单源 (Skill_{Name}_{Id})
class SkillIdentity extends RefCounted:
	const EXPLORE_NAME := "Explore"
	const ASSET_PREFIX := "Skill_"
	const LEGACY_SUFFIX := "_Skill"

	static func to_asset_name(p_name: String, p_id: int) -> String:
		return "%s%s_%d" % [ASSET_PREFIX, p_name if p_name != null else "", p_id]

	static func is_valid_name(p_name: String) -> bool:
		if p_name == null or p_name.is_empty():
			return false
		var c0 := p_name.unicode_at(0)
		if not ((c0 >= 65 and c0 <= 90) or (c0 >= 97 and c0 <= 122) or c0 == 95):
			return false
		for i in range(1, p_name.length()):
			var c := p_name.unicode_at(i)
			if not ((c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
				return false
		return true

	static func try_parse_asset_name(asset_name: String) -> Dictionary:
		if asset_name == null or not asset_name.begins_with(ASSET_PREFIX):
			return {"ok": false, "name": "", "id": 0}
		var rest := asset_name.substr(ASSET_PREFIX.length())
		if rest.ends_with(LEGACY_SUFFIX):
			var middle := rest.substr(0, rest.length() - LEGACY_SUFFIX.length())
			var split_res := try_split_compact_name(middle)
			if bool(split_res.get("ok", false)):
				return split_res
			if is_valid_name(middle):
				return {"ok": true, "name": middle, "id": 0}
			return {"ok": false, "name": "", "id": 0}
		return try_split_name_and_trailing_id(rest)

	static func try_split_compact_name(compact: String) -> Dictionary:
		if compact == null or compact.is_empty():
			return {"ok": false, "name": "", "id": 0}
		var last_letter := compact.length() - 1
		while last_letter >= 0:
			var c := compact.unicode_at(last_letter)
			if c >= 48 and c <= 57:
				last_letter -= 1
			else:
				break
		if last_letter < 0 or last_letter == compact.length() - 1:
			return {"ok": false, "name": "", "id": 0}
		var n := compact.substr(0, last_letter + 1)
		if not is_valid_name(n):
			return {"ok": false, "name": "", "id": 0}
		var num_str := compact.substr(last_letter + 1)
		if not num_str.is_valid_int():
			return {"ok": false, "name": "", "id": 0}
		var id := num_str.to_int()
		if id < 0:
			return {"ok": false, "name": "", "id": 0}
		return {"ok": true, "name": n, "id": id}

	static func try_split_name_and_trailing_id(name_and_id: String) -> Dictionary:
		if name_and_id == null or name_and_id.is_empty():
			return {"ok": false, "name": "", "id": 0}
		var last := name_and_id.rfind("_")
		if last <= 0 or last >= name_and_id.length() - 1:
			return {"ok": false, "name": "", "id": 0}
		var id_part := name_and_id.substr(last + 1)
		if not id_part.is_valid_int():
			return {"ok": false, "name": "", "id": 0}
		var id := id_part.to_int()
		if id < 0:
			return {"ok": false, "name": "", "id": 0}
		var n := name_and_id.substr(0, last)
		if not is_valid_name(n):
			return {"ok": false, "name": "", "id": 0}
		return {"ok": true, "name": n, "id": id}

	static func try_normalize(raw_name: String, raw_id: int) -> Dictionary:
		var n := (raw_name if raw_name != null else "").strip_edges()
		var id := raw_id
		var split_res := try_split_compact_name(n)
		if bool(split_res.get("ok", false)):
			var s_name := str(split_res["name"])
			var s_id := int(split_res["id"])
			if raw_id == 0 or raw_id == s_id:
				n = s_name
				id = s_id
			else:
				return {"ok": false, "name": "", "id": 0}
		var ok := is_valid_name(n) and id >= 0
		return {"ok": ok, "name": n, "id": id}


## GAS 共享资产：GameplayTagRes & GameplayEffectRes
class GameplayTagRes extends Resource:
	@export var tag_name: String = ""
	@export var parent_tag: GameplayTagRes = null
	@export_multiline var description: String = ""

	func _init(p_tag_name: String = "", p_parent: GameplayTagRes = null, p_desc: String = "") -> void:
		tag_name = p_tag_name
		parent_tag = p_parent
		description = p_desc
		if not p_tag_name.is_empty():
			resource_name = p_tag_name

	func is_descendant_of(other: GameplayTagRes) -> bool:
		if other == null:
			return false
		var cursor: GameplayTagRes = self
		var safety := 64
		while cursor != null and safety > 0:
			safety -= 1
			if cursor == other:
				return true
			cursor = cursor.parent_tag
		return false


class GameplayEffectModifier extends Resource:
	@export var attribute_name: String = "HP"
	@export var op: int = ModifierOp.ADD
	@export var magnitude: float = 0.0

	func _init(p_attr: String = "HP", p_op: int = ModifierOp.ADD, p_mag: float = 0.0) -> void:
		attribute_name = p_attr
		op = p_op
		magnitude = p_mag


class GameplayEffectRes extends Resource:
	@export var duration: float = 0.0
	@export var period: float = 0.0
	@export var modifiers: Array[GameplayEffectModifier] = []
	@export var granted_tags: Array[GameplayTagRes] = []


## 投射物飞行轨迹多态体系（对应 SkillProjectileTrajectory 及 4 个内置子类）
class SkillProjectileTrajectory extends Resource:
	func get_trajectory_type() -> String:
		return "Linear"

	func evaluate(t01: float, start_pos: Vector3, end_pos: Vector3) -> Vector3:
		return start_pos.lerp(end_pos, t01)


class LinearTrajectory extends SkillProjectileTrajectory:
	func get_trajectory_type() -> String:
		return "Linear"


class ParabolaTrajectory extends SkillProjectileTrajectory:
	@export var arch_height: float = 2.0

	func get_trajectory_type() -> String:
		return "Parabola"

	func configure(p_arch_height: float) -> void:
		arch_height = maxf(0.0, p_arch_height)

	func evaluate(t01: float, start_pos: Vector3, end_pos: Vector3) -> Vector3:
		var flat := start_pos.lerp(end_pos, t01)
		flat.y += 4.0 * arch_height * t01 * (1.0 - t01)
		return flat


class HomingTrajectory extends SkillProjectileTrajectory:
	@export var homing_strength: float = 0.5

	func get_trajectory_type() -> String:
		return "Homing"

	func configure(p_strength: float) -> void:
		homing_strength = clampf(p_strength, 0.0, 1.0)

	func evaluate(t01: float, start_pos: Vector3, end_pos: Vector3) -> Vector3:
		var linear := start_pos.lerp(end_pos, t01)
		var pull := homing_strength * t01
		return linear.lerp(end_pos, pull * (1.0 - t01) + t01 * t01)


class BezierTrajectory extends SkillProjectileTrajectory:
	@export var control_offset: Vector3 = Vector3(0.0, 2.0, 0.0)

	func get_trajectory_type() -> String:
		return "Bezier"

	func configure(p_offset: Vector3) -> void:
		control_offset = p_offset

	func evaluate(t01: float, start_pos: Vector3, end_pos: Vector3) -> Vector3:
		var mid := (start_pos + end_pos) * 0.5
		var control := mid + control_offset
		var u := 1.0 - t01
		return (u * u) * start_pos + (2.0 * u * t01) * control + (t01 * t01) * end_pos


## 15 类 SkillClip 子类（统一时间轴全局 StartMs）
class SkillClip extends Resource:
	@export var start_ms: int = 0
	@export var duration_ms: int = 0
	@export var display_name: String = ""

	func set_timing(p_start_ms: int, p_duration_ms: int) -> void:
		start_ms = maxi(0, p_start_ms)
		duration_ms = maxi(0, p_duration_ms)

	func set_display_name(p_display_name: String) -> void:
		display_name = p_display_name if p_display_name != null else ""

	func get_short_name() -> String:
		return "SkillClip"


class PlayAnimationClip extends SkillClip:
	@export var state_name: String = ""
	@export var crossfade_seconds: float = 0.0

	func get_short_name() -> String:
		return "PlayAnimation"

	func configure(p_state_name: String, p_crossfade: float) -> void:
		state_name = p_state_name if p_state_name != null else ""
		crossfade_seconds = clampf(p_crossfade, 0.0, 2.0)


class TeleportClip extends SkillClip:
	@export var mode: int = SkillTeleportModeKind.TO_TARGET_SIDE
	@export var offset_from_target: float = 1.5
	@export var origin_recall_key: String = "Default"
	@export var align_to_ground: bool = true

	func get_short_name() -> String:
		return "Teleport"

	func configure(p_mode: int, p_offset: float, p_recall_key: String, p_align: bool) -> void:
		mode = p_mode
		offset_from_target = maxf(0.0, p_offset)
		origin_recall_key = p_recall_key if p_recall_key != null and not p_recall_key.is_empty() else "Default"
		align_to_ground = p_align


class VisualMoveClip extends SkillClip:
	@export var offset: Vector3 = Vector3(0.0, 0.0, 1.0)
	@export var space: int = SkillVisualMoveSpace.CASTER_FORWARD
	@export var move_duration_seconds: float = 0.15
	@export var return_to_origin: bool = true

	func get_short_name() -> String:
		return "VisualMove"

	func configure(p_offset: Vector3, p_space: int, p_move_dur: float, p_return: bool) -> void:
		offset = p_offset
		space = p_space
		move_duration_seconds = maxf(0.0, p_move_dur)
		return_to_origin = p_return


class CheckHitClip extends SkillClip:
	@export var shape: int = SkillHitShapeKind.SPHERE
	@export var radius_or_half_extent: Vector3 = Vector3.ONE
	@export var filter_tag: GameplayTagRes = null

	func get_short_name() -> String:
		return "CheckHit"

	func configure(p_shape: int, p_radius_or_ext: Vector3, p_filter_tag: GameplayTagRes) -> void:
		shape = p_shape
		radius_or_half_extent = p_radius_or_ext
		filter_tag = p_filter_tag


class SpawnProjectileClip extends SkillClip:
	@export var prefab: Resource = null
	@export var speed: float = 10.0
	@export var direction: int = SkillProjectileDirectionKind.TO_TARGET
	@export var trajectory: SkillProjectileTrajectory = LinearTrajectory.new()
	@export var reversed: bool = false
	@export var landing_offset: Vector3 = Vector3.ZERO

	func get_short_name() -> String:
		return "SpawnProjectile"

	func configure(p_prefab: Resource, p_speed: float, p_dir: int) -> void:
		prefab = p_prefab
		speed = p_speed
		direction = p_dir

	func configure_trajectory(p_traj: SkillProjectileTrajectory, p_reversed: bool) -> void:
		if p_traj != null:
			trajectory = p_traj
		reversed = p_reversed

	func configure_landing_offset(p_offset: Vector3) -> void:
		landing_offset = p_offset


class DealDamageClip extends SkillClip:
	@export var base_damage: int = 0
	@export var coefficient: float = 1.0
	@export var damage_tag: GameplayTagRes = null

	func get_short_name() -> String:
		return "DealDamage"

	func configure(p_base_damage: int, p_coeff: float, p_damage_tag: GameplayTagRes) -> void:
		base_damage = p_base_damage
		coefficient = p_coeff
		damage_tag = p_damage_tag


class ApplyEffectClip extends SkillClip:
	@export var effect: GameplayEffectRes = null
	@export var is_instant: bool = false

	func get_short_name() -> String:
		return "ApplyEffect"

	func configure(p_effect: GameplayEffectRes, p_instant: bool) -> void:
		effect = p_effect
		is_instant = p_instant


class HitFlashClip extends SkillClip:
	@export var color: Color = Color(1.0, 0.25, 0.2, 1.0)
	@export var flash_seconds: float = 0.3

	func get_short_name() -> String:
		return "HitFlash"

	func configure(p_color: Color, p_flash_sec: float) -> void:
		color = p_color
		flash_seconds = maxf(0.05, p_flash_sec)


class TargetShakeClip extends SkillClip:
	@export var amplitude: float = 0.2
	@export var shake_duration_seconds: float = 0.25

	func get_short_name() -> String:
		return "TargetShake"

	func configure(p_amp: float, p_dur: float) -> void:
		amplitude = maxf(0.0, p_amp)
		shake_duration_seconds = maxf(0.05, p_dur)


class SkillCustomEvent extends Resource:
	@export var event_id: String = ""
	@export var float_param: float = 0.0
	@export var string_param: String = ""
	@export var vector_param: Vector3 = Vector3.ZERO

	func configure(p_id: String, p_float: float, p_str: String, p_vec: Vector3) -> void:
		event_id = p_id if p_id != null else ""
		float_param = p_float
		string_param = p_str if p_str != null else ""
		vector_param = p_vec


class PushEventClip extends SkillClip:
	@export var events: Array[SkillCustomEvent] = []

	func get_short_name() -> String:
		return "PushEvent"

	func configure(p_events: Array[SkillCustomEvent]) -> void:
		events = p_events if p_events != null else []


class PlaySfxClip extends SkillClip:
	@export var clip: Resource = null
	@export var volume: float = 1.0

	func get_short_name() -> String:
		return "PlaySfx"

	func configure(p_clip: Resource, p_volume: float) -> void:
		clip = p_clip
		volume = clampf(p_volume, 0.0, 1.0)


class CameraEffectClip extends SkillClip:
	@export var mode: int = SkillCameraEffectMode.PUSH_TO_TARGET
	@export var target: int = SkillCameraTargetKind.TARGET
	@export var zoom01: float = 0.3
	@export var amplitude: float = 0.5
	@export var frequency: float = 20.0

	var duration_seconds: float:
		get:
			return float(duration_ms) / 1000.0

	func get_short_name() -> String:
		return "CameraEffect"

	func configure(p_mode: int, p_zoom01: float, p_amp: float, p_freq: float, p_target: int = SkillCameraTargetKind.TARGET) -> void:
		mode = p_mode
		target = p_target
		zoom01 = clampf(p_zoom01, 0.0, 1.0)
		amplitude = maxf(0.0, p_amp)
		frequency = maxf(0.0, p_freq)


class HitStopClip extends SkillClip:
	const DEFAULT_REFERENCE_FPS := 60.0

	@export var stop_frames: int = 3
	@export var reference_fps: float = DEFAULT_REFERENCE_FPS
	@export var time_scale: float = 0.0
	@export var exempt_caster: bool = false
	@export var exempt_target: bool = false

	var stop_duration_seconds: float:
		get:
			var fps := reference_fps if reference_fps > 0.0 else DEFAULT_REFERENCE_FPS
			return float(maxi(0, stop_frames)) / fps

	func get_short_name() -> String:
		return "HitStop"

	func configure(p_frames: int, p_time_scale: float, p_exempt_caster: bool, p_exempt_target: bool, p_fps: float = DEFAULT_REFERENCE_FPS) -> void:
		stop_frames = maxi(0, p_frames)
		reference_fps = p_fps if p_fps > 0.0 else DEFAULT_REFERENCE_FPS
		time_scale = clampf(p_time_scale, 0.0, 1.0)
		exempt_caster = p_exempt_caster
		exempt_target = p_exempt_target


class SpawnVfxClip extends SkillClip:
	@export var vfx_prefab: Resource = null
	@export var anchor: int = SkillVfxAnchorKind.CASTER_ROOT

	func get_short_name() -> String:
		return "SpawnVfx"

	func configure(p_prefab: Resource, p_anchor: int) -> void:
		vfx_prefab = p_prefab
		anchor = p_anchor


class ShowSkillIconClip extends SkillClip:
	@export var display_prefab: Resource = null
	@export var icon_override: Texture2D = null
	@export var head_offset_y: float = 2.0
	@export var display_seconds: float = 1.5

	func get_short_name() -> String:
		return "ShowSkillIcon"

	func configure(p_prefab: Resource, p_icon: Texture2D, p_offset_y: float, p_seconds: float) -> void:
		display_prefab = p_prefab
		icon_override = p_icon
		head_offset_y = maxf(0.0, p_offset_y)
		display_seconds = maxf(0.0, p_seconds)


## SkillCost / SkillCooldown / SkillTrack / SkillTrackGroup / SkillRes (SkillSO)
class SkillCost extends Resource:
	@export var attribute_name: String = "Mana"
	@export var amount: float = 0.0

	var has_cost: bool:
		get:
			return amount > 0.0

	func _init(p_attr: String = "Mana", p_amount: float = 0.0) -> void:
		attribute_name = p_attr if p_attr != null and not p_attr.is_empty() else "Mana"
		amount = p_amount


class SkillCooldown extends Resource:
	@export var cd_group: String = "Default"
	@export var duration_seconds: float = 0.0

	var has_cooldown: bool:
		get:
			return duration_seconds > 0.0

	func _init(p_group: String = "Default", p_dur: float = 0.0) -> void:
		cd_group = p_group if p_group != null and not p_group.is_empty() else "Default"
		duration_seconds = p_dur


class SkillTrack extends Resource:
	@export var kind: int = SkillTrackKind.EFFECT
	@export var track_name: String = ""
	@export var clips: Array[SkillClip] = []

	func _init(p_kind: int = SkillTrackKind.EFFECT, p_name: String = "") -> void:
		kind = p_kind
		track_name = p_name if not p_name.is_empty() else GDSkillData.track_kind_name(p_kind)

	func add_clip(clip: SkillClip) -> void:
		if clip != null:
			clips.append(clip)

	func configure(p_kind: int, p_name: String) -> void:
		kind = p_kind
		track_name = p_name if not p_name.is_empty() else GDSkillData.track_kind_name(p_kind)


class SkillTrackGroup extends Resource:
	@export var group_name: String = ""
	@export var tracks: Array[SkillTrack] = []

	func _init(p_name: String = "") -> void:
		group_name = p_name if p_name != null else ""

	func add_track(track: SkillTrack) -> void:
		if track != null:
			tracks.append(track)

	func configure(p_name: String) -> void:
		group_name = p_name if p_name != null else ""


class SkillRes extends Resource:
	@export var skill_name: String = "New"
	@export var skill_id: int = 0
	@export var display_name: String = ""
	@export_multiline var description: String = ""
	@export var icon: Texture2D = null
	@export var cost: SkillCost = SkillCost.new()
	@export var cooldown: SkillCooldown = SkillCooldown.new()
	@export var required_tags: Array[GameplayTagRes] = []
	@export var blocked_tags: Array[GameplayTagRes] = []
	@export var duration_ms: int = 1000
	@export var groups: Array[SkillTrackGroup] = []

	var unique_name: String:
		get:
			return SkillIdentity.to_asset_name(skill_name, skill_id)

	func configure_header(p_name: String, p_id: int, p_display: String, p_desc: String) -> void:
		skill_name = p_name if p_name != null else ""
		skill_id = maxi(0, p_id)
		display_name = p_display if p_display != null else ""
		description = p_desc if p_desc != null else ""
		resource_name = unique_name
		emit_changed()

	func set_icon(p_icon: Texture2D) -> void:
		icon = p_icon
		emit_changed()

	func set_cost(p_attr: String, p_amount: float) -> void:
		cost = SkillCost.new(p_attr, p_amount)
		emit_changed()

	func set_cooldown(p_group: String, p_dur: float) -> void:
		cooldown = SkillCooldown.new(p_group, p_dur)
		emit_changed()

	func set_tags(req: Array[GameplayTagRes], blk: Array[GameplayTagRes]) -> void:
		required_tags = req if req != null else []
		blocked_tags = blk if blk != null else []
		emit_changed()

	func set_duration(p_dur_ms: int) -> void:
		duration_ms = maxi(0, p_dur_ms)
		emit_changed()

	func add_group(group: SkillTrackGroup) -> void:
		if group != null:
			groups.append(group)
			emit_changed()

	func clear_groups() -> void:
		groups.clear()
		emit_changed()
