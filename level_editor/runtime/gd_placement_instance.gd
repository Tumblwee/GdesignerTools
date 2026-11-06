@tool
class_name GDPlacementData
extends RefCounted

## 关卡摆放实例数据模型与 ID 段分配/标准化纯逻辑
## 对应 PlacementLevel / PlacementAttributeOverride / PlacementInstanceExtra / PlacementInstance / PlacementInstanceIdRangeLogic / PlacementDisplayNameUtil

class PlacementLevel extends RefCounted:
	const MIN_LEVEL := 0

	static func clamp_level(level: int, max_level: int) -> int:
		return clampi(level, MIN_LEVEL, maxi(MIN_LEVEL, max_level))

	static func level_prefab_slot_count(max_level: int) -> int:
		return maxi(0, max_level) + 1

	static func upgrade_transition_count(max_level: int) -> int:
		return maxi(0, max_level)


class PlacementAttributeOverride extends Resource:
	@export var tag: String = ""
	@export var value_type: int = GDCoreTypes.KeywordValueType.INT
	@export var int_value: int = 0
	@export var float_value: float = 0.0
	@export var string_value: String = ""
	@export var bool_value: bool = false

	func get_boxed() -> Variant:
		match value_type:
			GDCoreTypes.KeywordValueType.INT:
				return int_value
			GDCoreTypes.KeywordValueType.FLOAT:
				return float_value
			GDCoreTypes.KeywordValueType.STRING:
				return string_value
			GDCoreTypes.KeywordValueType.BOOL:
				return bool_value
			_:
				return null

	func get_int() -> int:
		if value_type != GDCoreTypes.KeywordValueType.INT:
			GDGameLogger.log_error_d("[PlacementAttributeOverride] ValueType mismatch: expected Int for Tag=%s" % tag)
			return 0
		return int_value

	func get_float() -> float:
		if value_type != GDCoreTypes.KeywordValueType.FLOAT:
			GDGameLogger.log_error_d("[PlacementAttributeOverride] ValueType mismatch: expected Float for Tag=%s" % tag)
			return 0.0
		return float_value

	func get_string() -> String:
		if value_type != GDCoreTypes.KeywordValueType.STRING:
			GDGameLogger.log_error_d("[PlacementAttributeOverride] ValueType mismatch: expected String for Tag=%s" % tag)
			return ""
		return string_value

	func get_bool() -> bool:
		if value_type != GDCoreTypes.KeywordValueType.BOOL:
			GDGameLogger.log_error_d("[PlacementAttributeOverride] ValueType mismatch: expected Bool for Tag=%s" % tag)
			return false
		return bool_value

	static func of_int(p_tag: String, v: int) -> PlacementAttributeOverride:
		var ov := GDPlacementOverrideRes.new()
		ov.tag = p_tag
		ov.value_type = GDCoreTypes.KeywordValueType.INT
		ov.int_value = v
		return ov

	static func of_float(p_tag: String, v: float) -> PlacementAttributeOverride:
		var ov := GDPlacementOverrideRes.new()
		ov.tag = p_tag
		ov.value_type = GDCoreTypes.KeywordValueType.FLOAT
		ov.float_value = v
		return ov

	static func of_string(p_tag: String, v: String) -> PlacementAttributeOverride:
		var ov := GDPlacementOverrideRes.new()
		ov.tag = p_tag
		ov.value_type = GDCoreTypes.KeywordValueType.STRING
		ov.string_value = v
		return ov

	static func of_bool(p_tag: String, v: bool) -> PlacementAttributeOverride:
		var ov := GDPlacementOverrideRes.new()
		ov.tag = p_tag
		ov.value_type = GDCoreTypes.KeywordValueType.BOOL
		ov.bool_value = v
		return ov

	static func from_custom_attribute_def(def: GDCustomAttributeDef) -> PlacementAttributeOverride:
		if def == null:
			return of_int("", 0)
		match def.value_type:
			GDCoreTypes.KeywordValueType.INT:
				return of_int(def.tag, def.default_int)
			GDCoreTypes.KeywordValueType.FLOAT:
				return of_float(def.tag, def.default_float)
			GDCoreTypes.KeywordValueType.STRING:
				return of_string(def.tag, def.default_string)
			GDCoreTypes.KeywordValueType.BOOL:
				return of_bool(def.tag, def.default_bool)
			_:
				return of_int(def.tag, 0)

	func clone_override() -> PlacementAttributeOverride:
		var c := GDPlacementOverrideRes.new()
		c.tag = tag
		c.value_type = value_type
		c.int_value = int_value
		c.float_value = float_value
		c.string_value = string_value
		c.bool_value = bool_value
		return c


class PlacementInstanceExtra extends Resource:
	@export var key: String = ""
	@export var version: int = 0
	@export var json: String = ""

	func _init(p_key: String = "", p_version: int = 0, p_json: String = "") -> void:
		key = p_key
		version = p_version
		json = p_json

	func clone_extra() -> PlacementInstanceExtra:
		return GDPlacementExtraRes.new(key, version, json)


class PlacementInstance extends Resource:
	@export var instance_id: int = 0
	@export var archetype_stable_id: int = 0
	@export var instance_name: String = ""
	@export var display_name: String = ""
	@export var position: Vector3 = Vector3.ZERO
	@export var euler_angles: Vector3 = Vector3.ZERO
	@export var scale: Vector3 = Vector3.ONE
	@export var initial_level: int = 1
	@export var attribute_overrides: Array = []
	@export var extras: Array = []
	## 仅插件内置的演员生成点使用。
	@export var actor_reference: GDActorReferenceRes = null
	@export var actor_spawn_on_ready: bool = true

	func _init(
		p_instance_id: int = 0,
		p_archetype_stable_id: int = 0,
		p_position: Vector3 = Vector3.ZERO,
		p_euler_angles: Vector3 = Vector3.ZERO,
		p_scale: Vector3 = Vector3.ONE,
		p_initial_level: int = 1
	) -> void:
		instance_id = p_instance_id
		archetype_stable_id = p_archetype_stable_id
		position = p_position
		euler_angles = p_euler_angles
		scale = p_scale
		initial_level = p_initial_level

	func try_get_extra(p_key: String) -> Dictionary:
		if p_key.is_empty():
			return {"ok": false, "version": 0, "json": ""}
		for e in extras:
			if e != null and e.key == p_key:
				return {"ok": true, "version": e.version, "json": e.json}
		return {"ok": false, "version": 0, "json": ""}

	func with_extra(p_key: String, p_version: int, p_json: String) -> PlacementInstance:
		var copy := _clone_shell(position, euler_angles, scale, initial_level)
		if p_key.is_empty():
			return copy
		for i in range(copy.extras.size() - 1, -1, -1):
			if copy.extras[i] != null and copy.extras[i].key == p_key:
				copy.extras.remove_at(i)
		copy.extras.append(GDPlacementExtraRes.new(p_key, p_version, p_json))
		return copy

	func without_extra(p_key: String) -> PlacementInstance:
		var copy := _clone_shell(position, euler_angles, scale, initial_level)
		if p_key.is_empty():
			return copy
		for i in range(copy.extras.size() - 1, -1, -1):
			if copy.extras[i] != null and copy.extras[i].key == p_key:
				copy.extras.remove_at(i)
		return copy

	func with_transform(p_pos: Vector3, p_euler: Vector3, p_scale: Vector3) -> PlacementInstance:
		return _clone_shell(p_pos, p_euler, p_scale, initial_level)

	func with_level(p_initial_level: int) -> PlacementInstance:
		return _clone_shell(position, euler_angles, scale, p_initial_level)

	func with_overrides(p_overrides: Array) -> PlacementInstance:
		var copy := _clone_shell(position, euler_angles, scale, initial_level)
		copy.attribute_overrides.clear()
		for ov in p_overrides:
			if ov is PlacementAttributeOverride:
				copy.attribute_overrides.append(ov.clone_override())
		return copy

	func with_name(new_name: String) -> PlacementInstance:
		var copy := _clone_shell(position, euler_angles, scale, initial_level)
		copy.instance_name = new_name
		return copy

	func with_display_name(new_display_name: String) -> PlacementInstance:
		var copy := _clone_shell(position, euler_angles, scale, initial_level)
		copy.display_name = new_display_name
		return copy

	func with_archetype_stable_id(new_arch_id: int) -> PlacementInstance:
		var copy := _clone_shell(position, euler_angles, scale, initial_level)
		copy.archetype_stable_id = new_arch_id
		if new_arch_id != archetype_stable_id:
			copy.actor_reference = null
		return copy

	func editor_update_transform(p_pos: Vector3, p_euler: Vector3, p_scale: Vector3) -> void:
		position = p_pos
		euler_angles = p_euler
		scale = p_scale

	func editor_rewrite_instance_id(new_instance_id: int) -> void:
		instance_id = new_instance_id

	func editor_rewrite_archetype_stable_id(new_arch_id: int) -> void:
		archetype_stable_id = new_arch_id

	func editor_init_instance_identity(p_name: String, p_display_name: String) -> void:
		instance_name = p_name
		display_name = p_display_name

	func _clone_shell(p_pos: Vector3, p_euler: Vector3, p_scale: Vector3, p_level: int) -> PlacementInstance:
		var copy := GDPlacementInstanceRes.new(instance_id, archetype_stable_id, p_pos, p_euler, p_scale, p_level)
		copy.instance_name = instance_name
		copy.display_name = display_name
		copy.actor_reference = actor_reference
		copy.actor_spawn_on_ready = actor_spawn_on_ready
		for ov in attribute_overrides:
			if ov != null:
				copy.attribute_overrides.append(ov.clone_override())
		for ex in extras:
			if ex != null:
				copy.extras.append(ex.clone_extra())
		return copy


class PlacementInstanceIdRangeLogic extends RefCounted:
	const INSTANCE_ID_START := 10000

	static func try_validate_custom_range(min_id: int, max_id: int) -> Dictionary:
		if min_id <= 0:
			return {"ok": false, "error": "实例 ID 段 Min 必须是正整数。"}
		if max_id < min_id:
			return {"ok": false, "error": "实例 ID 段 Max 必须大于或等于 Min。"}
		return {"ok": true, "error": ""}

	static func try_allocate(
		use_custom_range: bool,
		min_id: int,
		max_id: int,
		next_instance_id: int,
		occupied: Dictionary
	) -> Dictionary:
		if use_custom_range:
			var val_res := try_validate_custom_range(min_id, max_id)
			if not bool(val_res.get("ok", false)):
				return {
					"ok": false,
					"instance_id": 0,
					"new_next_instance_id": next_instance_id,
					"error": str(val_res.get("error", ""))
				}
			for id in range(min_id, max_id + 1):
				if occupied.has(id):
					continue
				return {
					"ok": true,
					"instance_id": id,
					"new_next_instance_id": next_instance_id,
					"error": ""
				}
			return {
				"ok": false,
				"instance_id": 0,
				"new_next_instance_id": next_instance_id,
				"error": "自定义 ID 段 [%d, %d] 内已无空闲 InstanceId。" % [min_id, max_id]
			}

		var candidate := INSTANCE_ID_START if next_instance_id < INSTANCE_ID_START else next_instance_id
		if occupied.has(candidate):
			return {
				"ok": false,
				"instance_id": 0,
				"new_next_instance_id": next_instance_id,
				"error": "全局 nextInstanceId=%d 已被占用。请先运行 Reconcile / 迁移，或为原型开启自定义 ID 段。" % candidate
			}
		return {
			"ok": true,
			"instance_id": candidate,
			"new_next_instance_id": candidate + 1,
			"error": ""
		}

	static func try_plan_standardize(
		placements: Array,
		archetype_stable_id: int,
		min_id: int,
		max_id: int
	) -> Dictionary:
		if archetype_stable_id <= 0:
			return {"ok": false, "remaps": [], "error": "archetypeStableId 无效。"}
		var val_res := try_validate_custom_range(min_id, max_id)
		if not bool(val_res.get("ok", false)):
			return {"ok": false, "remaps": [], "error": str(val_res.get("error", ""))}

		var owned: Array[PlacementInstance] = []
		var foreign_occupied: Dictionary = {}
		for p in placements:
			if p == null or not (p is PlacementInstance):
				continue
			var inst := p as PlacementInstance
			if inst.instance_id <= 0:
				continue
			if inst.archetype_stable_id == archetype_stable_id:
				owned.append(inst)
			else:
				foreign_occupied[inst.instance_id] = true

		owned.sort_custom(func(a: PlacementInstance, b: PlacementInstance) -> bool:
			return a.instance_id < b.instance_id
		)

		var capacity := max_id - min_id + 1
		if owned.size() > capacity:
			return {
				"ok": false,
				"remaps": [],
				"error": "本原型已摆放 %d 个实例，超过 ID 段容量 %d（[%d, %d]）。" % [owned.size(), capacity, min_id, max_id]
			}

		var remaps: Array[Dictionary] = []
		for i in range(owned.size()):
			var old_id := owned[i].instance_id
			var new_id := min_id + i
			if foreign_occupied.has(new_id):
				return {
					"ok": false,
					"remaps": [],
					"error": "目标 InstanceId=%d 已被其它原型实例占用，标准化整批取消。" % new_id
				}
			if old_id != new_id:
				remaps.append({"old_id": old_id, "new_id": new_id})

		return {"ok": true, "remaps": remaps, "error": ""}

	static func allocate_temp_ids(count: int, occupied: Dictionary) -> Array[int]:
		var temps: Array[int] = []
		var candidate := -1
		while temps.size() < count:
			if not occupied.has(candidate):
				temps.append(candidate)
			candidate -= 1
		return temps

	static func create_default_overrides(archetype: GDArchetypeRes) -> Array[PlacementAttributeOverride]:
		var result: Array[PlacementAttributeOverride] = []
		if archetype == null:
			return result
		for def in archetype.custom_attributes:
			if def != null and not def.tag.strip_edges().is_empty():
				result.append(PlacementAttributeOverride.from_custom_attribute_def(def))
		return result

	static func resolve_display_name(inst: PlacementInstance, archetype: GDArchetypeRes) -> String:
		if inst != null and not inst.display_name.is_empty():
			return inst.display_name
		if archetype != null:
			var base := archetype.display_name if not archetype.display_name.is_empty() else archetype.resource_name
			return "%s #%d" % [base if not base.is_empty() else "Placement", inst.instance_id if inst != null else 0]
		return "Placement #%d" % (inst.instance_id if inst != null else 0)
