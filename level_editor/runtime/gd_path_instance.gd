@tool
class_name GDPathSystem
extends RefCounted

## 场景路径数据模型与运行时采样注册表（对应 PathInstance / RuntimePath / PathRuntimeRegistry / PathLayoutLoader）
## PathId 从 20000 起单调递增（与 placement 10000、archetype 1000 区段互不重叠）。

class SplineKnot extends Resource:
	@export var position: Vector3 = Vector3.ZERO
	@export var tangent_in: Vector3 = Vector3.ZERO
	@export var tangent_out: Vector3 = Vector3.ZERO
	@export var rotation: Quaternion = Quaternion.IDENTITY

	func _init(
		p_pos: Vector3 = Vector3.ZERO,
		p_tan_in: Vector3 = Vector3.ZERO,
		p_tan_out: Vector3 = Vector3.ZERO,
		p_rot: Quaternion = Quaternion.IDENTITY
	) -> void:
		position = p_pos
		tangent_in = p_tan_in
		tangent_out = p_tan_out
		rotation = p_rot

	func clone_knot() -> SplineKnot:
		return SplineKnot.new(position, tangent_in, tangent_out, rotation)


class SplineData extends Resource:
	@export var knots: Array[SplineKnot] = []
	@export var closed: bool = false

	var count: int:
		get:
			return knots.size()

	func add_knot(knot: SplineKnot) -> void:
		if knot != null:
			knots.append(knot)

	func clear_knots() -> void:
		knots.clear()

	func clone_spline() -> SplineData:
		var s := SplineData.new()
		s.closed = closed
		for k in knots:
			if k != null:
				s.knots.append(k.clone_knot())
		return s

	func to_curve3d() -> Curve3D:
		var c := Curve3D.new()
		for k in knots:
			if k != null:
				c.add_point(k.position, k.tangent_in, k.tangent_out)
		if closed and knots.size() >= 2 and knots[0] != null:
			c.add_point(knots[0].position, knots[0].tangent_in, knots[0].tangent_out)
		return c

	func get_length() -> float:
		if knots.size() < 2:
			return 0.0
		var c := to_curve3d()
		return c.get_baked_length()

	func evaluate_position(t01: float) -> Vector3:
		if knots.is_empty():
			return Vector3.ZERO
		if knots.size() == 1:
			return knots[0].position
		var c := to_curve3d()
		var total_len := c.get_baked_length()
		if total_len <= 0.0001:
			return knots[0].position
		return c.sample_baked(clampf(t01, 0.0, 1.0) * total_len)

	func evaluate_tangent(t01: float) -> Vector3:
		if knots.size() < 2:
			return Vector3.FORWARD
		var eps := 0.01
		var t_a := clampf(t01 - eps, 0.0, 1.0)
		var t_b := clampf(t01 + eps, 0.0, 1.0)
		var dir := evaluate_position(t_b) - evaluate_position(t_a)
		return dir.normalized() if dir.length_squared() > 0.00001 else Vector3.FORWARD

	static func build_default_spline(center: Vector3 = Vector3.ZERO, is_2d: bool = false) -> SplineData:
		var c := center
		var rot := Quaternion.IDENTITY
		if is_2d:
			c.z = 0.0
		var s := SplineData.new()
		s.add_knot(SplineKnot.new(c + Vector3(-2.0, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO, rot))
		s.add_knot(SplineKnot.new(c + Vector3(2.0, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO, rot))
		return s


class PathInstance extends Resource:
	@export var path_id: int = 0
	@export var path_name: String = ""
	@export var display_name: String = ""
	@export var path_type_keyword: int = 0
	@export var spline: SplineData = SplineData.new()
	@export var speed: float = 1.0
	@export var attribute_overrides: Array[GDPlacementData.PlacementAttributeOverride] = []

	var closed: bool:
		get:
			return spline != null and spline.closed

	var knot_count: int:
		get:
			return spline.count if spline != null else 0

	func _init(
		p_path_id: int = 0,
		p_path_type_keyword: int = 0,
		p_spline: SplineData = null,
		p_speed: float = 1.0
	) -> void:
		path_id = p_path_id
		path_type_keyword = p_path_type_keyword
		spline = p_spline.clone_spline() if p_spline != null else SplineData.new()
		speed = p_speed

	func with_spline(p_spline: SplineData) -> PathInstance:
		var copy := _clone_shell()
		copy.spline = p_spline.clone_spline() if p_spline != null else SplineData.new()
		return copy

	func with_path_type(p_type_keyword: int) -> PathInstance:
		var copy := _clone_shell()
		copy.path_type_keyword = p_type_keyword
		return copy

	func with_speed(p_speed: float) -> PathInstance:
		var copy := _clone_shell()
		copy.speed = maxf(0.0, p_speed)
		return copy

	func with_closed(p_closed: bool) -> PathInstance:
		var copy := _clone_shell()
		copy.spline.closed = p_closed
		return copy

	func with_overrides(p_overrides: Array) -> PathInstance:
		var copy := _clone_shell()
		copy.attribute_overrides.clear()
		if p_overrides != null:
			for ov in p_overrides:
				if ov is GDPlacementData.PlacementAttributeOverride:
					copy.attribute_overrides.append(ov.clone_override())
		return copy

	func with_name(new_name: String) -> PathInstance:
		var copy := _clone_shell()
		copy.path_name = new_name if new_name != null else ""
		return copy

	func with_display_name(new_display_name: String) -> PathInstance:
		var copy := _clone_shell()
		copy.display_name = new_display_name if new_display_name != null else ""
		return copy

	func editor_update_spline(p_spline: SplineData) -> void:
		spline = p_spline.clone_spline() if p_spline != null else SplineData.new()

	func editor_init_path_identity(p_name: String, p_display_name: String) -> void:
		path_name = p_name if p_name != null else ""
		display_name = p_display_name if p_display_name != null else ""

	func editor_rewrite_path_id(new_path_id: int) -> void:
		path_id = new_path_id

	func _clone_shell() -> PathInstance:
		var copy := PathInstance.new(path_id, path_type_keyword, spline, speed)
		copy.path_name = path_name
		copy.display_name = display_name
		for ov in attribute_overrides:
			if ov != null:
				copy.attribute_overrides.append(ov.clone_override())
		return copy


class RuntimePath extends RefCounted:
	var path_id: int = 0
	var path_name: String = ""
	var display_name: String = ""
	var path_type_keyword: int = 0
	var speed: float = 1.0
	var closed: bool = false
	var spline: SplineData = null

	func _init(src: PathInstance) -> void:
		if src == null:
			return
		path_id = src.path_id
		path_name = src.path_name
		display_name = src.display_name
		path_type_keyword = src.path_type_keyword
		speed = src.speed
		closed = src.closed
		spline = src.spline.clone_spline() if src.spline != null else SplineData.new()

	func evaluate_position(t01: float) -> Vector3:
		return spline.evaluate_position(t01) if spline != null else Vector3.ZERO

	func evaluate_tangent(t01: float) -> Vector3:
		return spline.evaluate_tangent(t01) if spline != null else Vector3.FORWARD

	func get_length() -> float:
		return spline.get_length() if spline != null else 0.0


class PathRuntimeRegistry extends RefCounted:
	var _by_id: Dictionary = {} # int -> RuntimePath
	var _all: Array[RuntimePath] = []

	var all_paths: Array[RuntimePath]:
		get:
			return _all

	func add(rt_path: RuntimePath) -> void:
		if rt_path == null or rt_path.path_id <= 0:
			return
		_by_id[rt_path.path_id] = rt_path
		if not _all.has(rt_path):
			_all.append(rt_path)

	func try_get_path(p_path_id: int) -> Dictionary:
		if _by_id.has(p_path_id):
			return {"ok": true, "path": _by_id[p_path_id]}
		return {"ok": false, "path": null}

	func find_by_type(p_type_keyword: int) -> Array[RuntimePath]:
		var res: Array[RuntimePath] = []
		for p in _all:
			if p.path_type_keyword == p_type_keyword:
				res.append(p)
		return res

	func clear_all() -> void:
		_by_id.clear()
		_all.clear()
