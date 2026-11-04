@tool
class_name GDCameraPoseSystem
extends RefCounted

## 相机机位数据模型与场景代理标记（对应 CameraProjectionMode / CameraBoundPlane / CameraPose / CameraPoseMarker）

enum CameraProjectionMode {
	PERSPECTIVE = 0,
	ORTHOGRAPHIC = 1,
}

enum CameraBoundPlane {
	XZ = 0,
	XY = 1,
}


class CameraPose extends Resource:
	const DEFAULT_ZOOM_MIN_DISTANCE := 23.26
	const DEFAULT_ZOOM_MAX_DISTANCE := 93.03
	const DEFAULT_INITIAL_ZOOM_01 := 0.5
	const UNSET_INITIAL_ZOOM := -1.0

	@export var pose_name: String = ""
	@export var display_name: String = ""
	@export var position: Vector3 = Vector3.ZERO
	@export var euler_angles: Vector3 = Vector3.ZERO
	@export var fov: float = 60.0
	@export var projection: int = CameraProjectionMode.PERSPECTIVE
	@export var orthographic_min_size: float = 0.0
	@export var orthographic_max_size: float = 0.0

	@export var zoom_min_distance: float = DEFAULT_ZOOM_MIN_DISTANCE
	@export var zoom_max_distance: float = DEFAULT_ZOOM_MAX_DISTANCE
	@export var click_focus_zoom_distance: float = DEFAULT_ZOOM_MIN_DISTANCE
	@export var raw_initial_zoom_01: float = UNSET_INITIAL_ZOOM

	@export var has_bound: bool = false
	@export var bound_center: Vector2 = Vector2.ZERO
	@export var bound_yaw_deg: float = 45.0
	@export var bound_half_extents: Vector2 = Vector2(100.0, 100.0)
	@export var bound_plane: int = CameraBoundPlane.XZ
	@export var has_bound_edges: bool = false
	@export var raw_bound_left: float = 0.0
	@export var raw_bound_right: float = 0.0
	@export var raw_bound_bottom: float = 0.0
	@export var raw_bound_top: float = 0.0

	var has_orthographic_zoom: bool:
		get:
			return orthographic_min_size > 0.0 and orthographic_max_size > 0.0

	var has_initial_zoom: bool:
		get:
			return raw_initial_zoom_01 >= 0.0

	var initial_zoom_01: float:
		get:
			return raw_initial_zoom_01 if has_initial_zoom else DEFAULT_INITIAL_ZOOM_01

	var bound_left: float:
		get:
			return raw_bound_left if has_bound_edges else bound_center.x - absf(bound_half_extents.x)

	var bound_right: float:
		get:
			return raw_bound_right if has_bound_edges else bound_center.x + absf(bound_half_extents.x)

	var bound_bottom: float:
		get:
			return raw_bound_bottom if has_bound_edges else bound_center.y - absf(bound_half_extents.y)

	var bound_top: float:
		get:
			return raw_bound_top if has_bound_edges else bound_center.y + absf(bound_half_extents.y)

	var rotation: Quaternion:
		get:
			return Quaternion.from_euler(Vector3(deg_to_rad(euler_angles.x), deg_to_rad(euler_angles.y), deg_to_rad(euler_angles.z)))

	func _init(
		p_pos: Vector3 = Vector3.ZERO,
		p_euler: Vector3 = Vector3.ZERO,
		p_fov: float = 60.0
	) -> void:
		position = p_pos
		euler_angles = p_euler
		fov = p_fov

	func with_name(new_name: String) -> CameraPose:
		var copy := _clone_shell()
		copy.pose_name = new_name if new_name != null else ""
		return copy

	func with_display_name(new_display_name: String) -> CameraPose:
		var copy := _clone_shell()
		copy.display_name = new_display_name if new_display_name != null else ""
		return copy

	func with_pose(p_pos: Vector3, p_euler: Vector3, p_fov: float) -> CameraPose:
		var copy := _clone_shell()
		copy.position = p_pos
		copy.euler_angles = p_euler
		copy.fov = p_fov
		return copy

	func with_projection(p_projection: int) -> CameraPose:
		var copy := _clone_shell()
		copy.projection = p_projection
		return copy

	func with_orthographic_zoom_range(min_size: float, max_size: float) -> CameraPose:
		var copy := _clone_shell()
		var mn := maxf(0.01, min_size)
		copy.orthographic_min_size = mn
		copy.orthographic_max_size = maxf(mn, max_size)
		return copy

	func with_zoom_range(min_dist: float, max_dist: float) -> CameraPose:
		var copy := _clone_shell()
		var mn := maxf(0.01, min_dist)
		var mx := maxf(mn, max_dist)
		copy.zoom_min_distance = mn
		copy.zoom_max_distance = mx
		return copy

	func with_click_focus_zoom_distance(dist: float) -> CameraPose:
		var copy := _clone_shell()
		copy.click_focus_zoom_distance = maxf(0.01, dist)
		return copy

	func with_initial_zoom(zoom01: float) -> CameraPose:
		var copy := _clone_shell()
		copy.raw_initial_zoom_01 = clampf(zoom01, 0.0, 1.0)
		return copy

	func without_initial_zoom() -> CameraPose:
		var copy := _clone_shell()
		copy.raw_initial_zoom_01 = UNSET_INITIAL_ZOOM
		return copy

	func with_bound(center: Vector2, yaw_deg: float, half_extents: Vector2) -> CameraPose:
		var copy := _clone_shell()
		copy.has_bound = true
		copy.has_bound_edges = false
		copy.bound_center = center
		copy.bound_yaw_deg = yaw_deg
		copy.bound_half_extents = Vector2(maxf(0.01, half_extents.x), maxf(0.01, half_extents.y))
		return copy

	func with_bound_edges(left: float, right: float, bottom: float, top: float) -> CameraPose:
		var copy := _clone_shell()
		copy.has_bound = true
		copy.has_bound_edges = true
		copy.bound_plane = CameraBoundPlane.XY
		copy.raw_bound_left = left
		copy.raw_bound_right = right
		copy.raw_bound_bottom = bottom
		copy.raw_bound_top = top
		return copy

	func with_bound_plane(plane: int) -> CameraPose:
		var copy := _clone_shell()
		copy.bound_plane = plane
		return copy

	func without_bound() -> CameraPose:
		var copy := _clone_shell()
		copy.has_bound = false
		return copy

	func editor_init_identity(p_name: String, p_display_name: String) -> void:
		pose_name = p_name if p_name != null else ""
		display_name = p_display_name if p_display_name != null else ""

	func _clone_shell() -> CameraPose:
		var copy := CameraPose.new(position, euler_angles, fov)
		copy.pose_name = pose_name
		copy.display_name = display_name
		copy.projection = projection
		copy.orthographic_min_size = orthographic_min_size
		copy.orthographic_max_size = orthographic_max_size
		copy.zoom_min_distance = zoom_min_distance
		copy.zoom_max_distance = zoom_max_distance
		copy.click_focus_zoom_distance = click_focus_zoom_distance
		copy.raw_initial_zoom_01 = raw_initial_zoom_01
		copy.has_bound = has_bound
		copy.bound_center = bound_center
		copy.bound_yaw_deg = bound_yaw_deg
		copy.bound_half_extents = bound_half_extents
		copy.bound_plane = bound_plane
		copy.has_bound_edges = has_bound_edges
		copy.raw_bound_left = raw_bound_left
		copy.raw_bound_right = raw_bound_right
		copy.raw_bound_bottom = raw_bound_bottom
		copy.raw_bound_top = raw_bound_top
		return copy


class CameraPoseMarker extends Node3D:
	@export var pose_index: int = 0
