@tool
class_name GDSkillClips
extends RefCounted

## 技能时间轴 15 种多态 Clip 与 4 种投射物飞行轨迹（Trajectory）
## 对应 SkillClip + 15 个子类 + SkillProjectileTrajectory (Linear / Parabola / Homing / Bezier) + SkillCustomEvent

# ─────────────────────── Trajectories (4 种) ───────────────────────

class SkillProjectileTrajectory extends Resource:
	func get_trajectory_type() -> String:
		return "Linear"

	func evaluate(t01: float, start_pos: Vector3, end_pos: Vector3) -> Vector3:
		return start_pos.lerp(end_pos, t01)


class LinearTrajectory extends SkillProjectileTrajectory:
	func get_trajectory_type() -> String:
		return "Linear"

	func evaluate(t01: float, start_pos: Vector3, end_pos: Vector3) -> Vector3:
		return start_pos.lerp(end_pos, t01)


class ParabolaTrajectory extends SkillProjectileTrajectory:
	@export var arch_height: float = 2.0

	func get_trajectory_type() -> String:
		return "Parabola"

	func configure(p_arch_height: float) -> void:
		arch_height = maxf(0.0, p_arch_height)

	func evaluate(t01: float, start_pos: Vector3, end_pos: Vector3) -> Vector3:
		var flat := start_pos.lerp(end_pos, t01)
		var lift := 4.0 * arch_height * t01 * (1.0 - t01)
		flat.y += lift
		return flat


class HomingTrajectory extends SkillProjectileTrajectory:
	@export var homing_strength: float = 0.5

	func get_trajectory_type() -> String:
		return "Homing"

	func configure(p_homing_strength: float) -> void:
		homing_strength = clampf(p_homing_strength, 0.0, 1.0)

	func evaluate(t01: float, start_pos: Vector3, end_pos: Vector3) -> Vector3:
		var linear := start_pos.lerp(end_pos, t01)
		var pull := homing_strength * t01
		return linear.lerp(end_pos, pull * (1.0 - t01) + t01 * t01)


class BezierTrajectory extends SkillProjectileTrajectory:
	@export var control_offset: Vector3 = Vector3(0.0, 2.0, 0.0)

	func get_trajectory_type() -> String:
		return "Bezier"

	func configure(p_control_offset: Vector3) -> void:
		control_offset = p_control_offset

	func evaluate(t01: float, start_pos: Vector3, end_pos: Vector3) -> Vector3:
		var mid := (start_pos + end_pos) * 0.5
		var control := mid + control_offset
		var u := 1.0 - t01
		return (u * u) * start_pos + (2.0 * u * t01) * control + (t01 * t01) * end_pos


# ─────────────────────── SkillClip Base & 15 Subclasses ───────────────────────

class SkillClip extends Resource:
	@export var start_ms: int = 0
	@export var duration_ms: int = 0
	@export var display_name: String = ""

	func set_timing(p_start_ms: int, p_duration_ms: int) -> void:
		start_ms = maxi(0, p_start_ms)
		duration_ms = maxi(0, p_duration_ms)

	func set_display_name(p_display_name: String) -> void:
		display_name = p_display_name if p_display_name != null else ""

	func get_clip_short_name() -> String:
		return "Skill"

	func is_logic_clip() -> bool:
		return false


## 1. PlayAnimationClip
class PlayAnimationClip extends SkillClip:
	@export var state_name: String = ""
	@export var crossfade_seconds: float = 0.0

	func get_clip_short_name() -> String:
		return "PlayAnimation"

	func configure(p_state_name: String, p_crossfade_seconds: float) -> void:
		state_name = p_state_name if p_state_name != null else ""
		crossfade_seconds = clampf(p_crossfade_seconds, 0.0, 2.0)


## 2. PlaySfxClip
class PlaySfxClip extends SkillClip:
	@export var clip: AudioStream = null
	@export var volume: float = 1.0

	func get_clip_short_name() -> String:
		return "PlaySfx"

	func configure(p_clip: AudioStream, p_volume: float) -> void:
		clip = p_clip
		volume = clampf(p_volume, 0.0, 1.0)


## 3. SpawnVfxClip
class SpawnVfxClip extends SkillClip:
	@export var vfx_prefab: PackedScene = null
	@export var anchor: int = GDSkillTypes.SkillVfxAnchorKind.CASTER_ROOT

	func get_clip_short_name() -> String:
		return "SpawnVfx"

	func configure(p_vfx_prefab: PackedScene, p_anchor: int) -> void:
		vfx_prefab = p_vfx_prefab
		anchor = p_anchor


## 4. ShowSkillIconClip
class ShowSkillIconClip extends SkillClip:
	@export var display_prefab: PackedScene = null
	@export var icon_override: Texture2D = null
	@export var head_offset_y: float = 2.0
	@export var display_seconds: float = 1.5

	func get_clip_short_name() -> String:
		return "ShowSkillIcon"

	func configure(p_display_prefab: PackedScene, p_icon_override: Texture2D, p_head_offset_y: float, p_display_seconds: float) -> void:
		display_prefab = p_display_prefab
		icon_override = p_icon_override
		head_offset_y = maxf(0.0, p_head_offset_y)
		display_seconds = maxf(0.0, p_display_seconds)


## 5. CameraEffectClip
class CameraEffectClip extends SkillClip:
	@export var mode: int = GDSkillTypes.SkillCameraEffectMode.PUSH_TO_TARGET
	@export var target: int = GDSkillTypes.SkillCameraTargetKind.TARGET
	@export var zoom01: float = 0.3
	@export var amplitude: float = 0.5
	@export var frequency: float = 20.0

	var duration_seconds: float:
		get:
			return float(duration_ms) / 1000.0

	func get_clip_short_name() -> String:
		return "CameraEffect"

	func configure(
		p_mode: int,
		p_zoom01: float,
		p_amplitude: float,
		p_frequency: float,
		p_target: int = GDSkillTypes.SkillCameraTargetKind.TARGET
	) -> void:
		mode = p_mode
		target = p_target
		zoom01 = clampf(p_zoom01, 0.0, 1.0)
		amplitude = maxf(0.0, p_amplitude)
		frequency = maxf(0.0, p_frequency)


## 6. VisualMoveClip
class VisualMoveClip extends SkillClip:
	@export var offset: Vector3 = Vector3(0.0, 0.0, 1.0)
	@export var space: int = GDSkillTypes.SkillVisualMoveSpace.CASTER_FORWARD
	@export var move_duration_seconds: float = 0.15
	@export var return_to_origin: bool = true

	func get_clip_short_name() -> String:
		return "VisualMove"

	func configure(p_offset: Vector3, p_space: int, p_move_duration_sec: float, p_return_to_origin: bool) -> void:
		offset = p_offset
		space = p_space
		move_duration_seconds = maxf(0.0, p_move_duration_sec)
		return_to_origin = p_return_to_origin


## 7. HitStopClip
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

	func get_clip_short_name() -> String:
		return "HitStop"

	func configure(
		p_stop_frames: int,
		p_time_scale: float,
		p_exempt_caster: bool,
		p_exempt_target: bool,
		p_ref_fps: float = DEFAULT_REFERENCE_FPS
	) -> void:
		stop_frames = maxi(0, p_stop_frames)
		reference_fps = p_ref_fps if p_ref_fps > 0.0 else DEFAULT_REFERENCE_FPS
		time_scale = clampf(p_time_scale, 0.0, 1.0)
		exempt_caster = p_exempt_caster
		exempt_target = p_exempt_target


## 8. HitFlashClip (Logic rank 0)
class HitFlashClip extends SkillClip:
	@export var color: Color = Color(1.0, 0.25, 0.2, 1.0)
	@export var flash_seconds: float = 0.3

	func get_clip_short_name() -> String:
		return "HitFlash"

	func is_logic_clip() -> bool:
		return true

	func configure(p_color: Color, p_flash_seconds: float) -> void:
		color = p_color
		flash_seconds = maxf(0.05, p_flash_seconds)


## 9. TargetShakeClip (Logic rank 0)
class TargetShakeClip extends SkillClip:
	@export var amplitude: float = 0.2
	@export var shake_duration_seconds: float = 0.25

	func get_clip_short_name() -> String:
		return "TargetShake"

	func is_logic_clip() -> bool:
		return true

	func configure(p_amplitude: float, p_shake_duration_sec: float) -> void:
		amplitude = maxf(0.0, p_amplitude)
		shake_duration_seconds = maxf(0.05, p_shake_duration_sec)


## 10. PushEventClip + SkillCustomEvent (Logic rank 0)
class SkillCustomEvent extends Resource:
	@export var event_id: String = ""
	@export var float_param: float = 0.0
	@export var string_param: String = ""
	@export var vector_param: Vector3 = Vector3.ZERO

	func configure(p_event_id: String, p_float: float, p_string: String, p_vec: Vector3) -> void:
		event_id = p_event_id if p_event_id != null else ""
		float_param = p_float
		string_param = p_string if p_string != null else ""
		vector_param = p_vec


class PushEventClip extends SkillClip:
	@export var events: Array[SkillCustomEvent] = []

	func get_clip_short_name() -> String:
		return "PushEvent"

	func is_logic_clip() -> bool:
		return true

	func configure(p_events: Array[SkillCustomEvent]) -> void:
		events = p_events if p_events != null else []


## 11. SpawnProjectileClip (Logic rank 0)
class SpawnProjectileClip extends SkillClip:
	@export var prefab: PackedScene = null
	@export var speed: float = 10.0
	@export var direction: int = GDSkillTypes.SkillProjectileDirectionKind.TO_TARGET
	@export var trajectory: SkillProjectileTrajectory = LinearTrajectory.new()
	@export var reversed: bool = false
	@export var landing_offset: Vector3 = Vector3.ZERO

	func get_clip_short_name() -> String:
		return "SpawnProjectile"

	func is_logic_clip() -> bool:
		return true

	func configure(p_prefab: PackedScene, p_speed: float, p_direction: int) -> void:
		prefab = p_prefab
		speed = p_speed
		direction = p_direction

	func configure_trajectory(p_trajectory: SkillProjectileTrajectory, p_reversed: bool) -> void:
		if p_trajectory != null:
			trajectory = p_trajectory
		reversed = p_reversed

	func configure_landing_offset(p_offset: Vector3) -> void:
		landing_offset = p_offset


## 12. DealDamageClip (Logic rank 0)
class DealDamageClip extends SkillClip:
	@export var base_damage: int = 0
	@export var coefficient: float = 1.0
	@export var damage_tag: GDSkillTypes.GameplayTagRes = null

	func get_clip_short_name() -> String:
		return "DealDamage"

	func is_logic_clip() -> bool:
		return true

	func configure(p_base_damage: int, p_coefficient: float, p_damage_tag: GDSkillTypes.GameplayTagRes = null) -> void:
		base_damage = p_base_damage
		coefficient = p_coefficient
		damage_tag = p_damage_tag


## 13. CheckHitClip (Logic rank 0)
class CheckHitClip extends SkillClip:
	@export var shape: int = GDSkillTypes.SkillHitShapeKind.SPHERE
	@export var radius_or_half_extent: Vector3 = Vector3.ONE
	@export var filter_tag: GDSkillTypes.GameplayTagRes = null

	func get_clip_short_name() -> String:
		return "CheckHit"

	func is_logic_clip() -> bool:
		return true

	func configure(p_shape: int, p_radius_or_half_extent: Vector3, p_filter_tag: GDSkillTypes.GameplayTagRes = null) -> void:
		shape = p_shape
		radius_or_half_extent = p_radius_or_half_extent
		filter_tag = p_filter_tag


## 14. ApplyEffectClip (Logic rank 0)
class ApplyEffectClip extends SkillClip:
	@export var effect: GDSkillTypes.GameplayEffectRes = null
	@export var is_instant: bool = false

	func get_clip_short_name() -> String:
		return "ApplyEffect"

	func is_logic_clip() -> bool:
		return true

	func configure(p_effect: GDSkillTypes.GameplayEffectRes, p_is_instant: bool) -> void:
		effect = p_effect
		is_instant = p_is_instant


## 15. TeleportClip (Logic rank 0)
class TeleportClip extends SkillClip:
	@export var mode: int = GDSkillTypes.SkillTeleportModeKind.TO_TARGET_SIDE
	@export var offset_from_target: float = 1.5
	@export var origin_recall_key: String = "Default"
	@export var align_to_ground: bool = true

	func get_clip_short_name() -> String:
		return "Teleport"

	func is_logic_clip() -> bool:
		return true

	func configure(p_mode: int, p_offset_from_target: float, p_recall_key: String, p_align_to_ground: bool) -> void:
		mode = p_mode
		offset_from_target = maxf(0.0, p_offset_from_target)
		origin_recall_key = p_recall_key if p_recall_key != null else "Default"
		align_to_ground = p_align_to_ground
