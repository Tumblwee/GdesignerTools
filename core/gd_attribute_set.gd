@tool
class_name GDAttributeSystem
extends RefCounted

## GAS 属性系统与容器（对应 AttributeValue / AttributeSet / AttributeInitialOverride / AttributeSetMono）
## 公式：数值通道 Current = Override ?? ((Base + Add) * (1 + Mul))；String/Bool 的 Current 等于 Base。

class AttributeInitialOverride extends RefCounted:
	var kind: int = 0
	var base_value: float = 0.0

	func _init(p_kind: int = 0, p_base: float = 0.0) -> void:
		kind = p_kind
		base_value = p_base


class AttributeValue extends RefCounted:
	var value_type: int = GDCoreTypes.KeywordValueType.FLOAT
	var boxed_base: Variant = 0.0
	var add_bonus: float = 0.0
	var mul_bonus: float = 0.0
	var has_override: bool = false
	var override_value: float = 0.0

	func _init(
		p_value_type: int = GDCoreTypes.KeywordValueType.FLOAT,
		p_base: Variant = 0.0,
		p_add: float = 0.0,
		p_mul: float = 0.0,
		p_has_override: bool = false,
		p_override: float = 0.0
	) -> void:
		value_type = p_value_type
		boxed_base = _normalize_base(p_value_type, p_base)
		add_bonus = p_add
		mul_bonus = p_mul
		has_override = p_has_override
		override_value = p_override

	var base_value: float:
		get:
			return _to_numeric(boxed_base, value_type)

	var current: float:
		get:
			return _to_numeric(current_boxed, value_type)

	var current_boxed: Variant:
		get:
			return _compute_current(value_type, boxed_base, add_bonus, mul_bonus, has_override, override_value)

	func with_base(new_base: Variant) -> AttributeValue:
		return AttributeValue.new(value_type, new_base, add_bonus, mul_bonus, has_override, override_value)

	func with_numeric_base(new_base: float) -> AttributeValue:
		if value_type == GDCoreTypes.KeywordValueType.INT:
			return with_base(roundi(new_base))
		return with_base(new_base)

	func with_add_bonus(new_add: float) -> AttributeValue:
		return AttributeValue.new(value_type, boxed_base, new_add, mul_bonus, has_override, override_value)

	func with_mul_bonus(new_mul: float) -> AttributeValue:
		return AttributeValue.new(value_type, boxed_base, add_bonus, new_mul, has_override, override_value)

	func with_override(new_override: Variant) -> AttributeValue:
		if new_override == null:
			return AttributeValue.new(value_type, boxed_base, add_bonus, mul_bonus, false, 0.0)
		return AttributeValue.new(value_type, boxed_base, add_bonus, mul_bonus, true, float(new_override))

	func apply_delta(delta: float) -> AttributeValue:
		if value_type == GDCoreTypes.KeywordValueType.INT:
			var next_int := roundi(_to_numeric(boxed_base, value_type) + delta)
			return with_base(next_int)
		if value_type == GDCoreTypes.KeywordValueType.FLOAT:
			return with_base(_to_numeric(boxed_base, value_type) + delta)
		return self

	func with_modifier(add_delta: float, mul_delta: float) -> AttributeValue:
		return AttributeValue.new(
			value_type,
			boxed_base,
			add_bonus + add_delta,
			mul_bonus + mul_delta,
			has_override,
			override_value
		)

	static func _normalize_base(vt: int, val: Variant) -> Variant:
		match vt:
			GDCoreTypes.KeywordValueType.INT:
				if val is int:
					return val
				return roundi(_to_numeric(val, GDCoreTypes.KeywordValueType.FLOAT))
			GDCoreTypes.KeywordValueType.FLOAT:
				return _to_numeric(val, GDCoreTypes.KeywordValueType.FLOAT)
			GDCoreTypes.KeywordValueType.STRING:
				return str(val) if val != null else ""
			GDCoreTypes.KeywordValueType.BOOL:
				return bool(val) if val != null else false
			_:
				return val

	static func _compute_current(
		vt: int,
		base_val: Variant,
		add_v: float,
		mul_v: float,
		has_ov: bool,
		ov: float
	) -> Variant:
		match vt:
			GDCoreTypes.KeywordValueType.INT:
				if has_ov:
					return roundi(ov)
				return roundi((_to_numeric(base_val, GDCoreTypes.KeywordValueType.INT) + add_v) * (1.0 + mul_v))
			GDCoreTypes.KeywordValueType.FLOAT:
				if has_ov:
					return ov
				return (_to_numeric(base_val, GDCoreTypes.KeywordValueType.FLOAT) + add_v) * (1.0 + mul_v)
			GDCoreTypes.KeywordValueType.STRING, GDCoreTypes.KeywordValueType.BOOL:
				return base_val
			_:
				return base_val

	static func _to_numeric(val: Variant, _vt: int) -> float:
		if val is float:
			return val
		if val is int:
			return float(val)
		return 0.0


class AttributeSet extends RefCounted:
	signal attribute_changed(kind: int, old_current: float, new_current: float, reason: String)
	signal attribute_value_changed(kind: int, old_current: Variant, new_current: Variant, reason: String)

	var _values: Dictionary = {} # int -> AttributeValue
	var _warned_kinds: Dictionary = {} # int -> bool

	func get_current(kind: int) -> float:
		if _values.has(kind):
			var v: AttributeValue = _values[kind]
			return v.current
		_warn_unregistered_once(kind)
		return 0.0

	func get_base(kind: int) -> float:
		if _values.has(kind):
			var v: AttributeValue = _values[kind]
			return v.base_value
		_warn_unregistered_once(kind)
		return 0.0

	func get_current_typed(kind: int, expected_value_type: int) -> Variant:
		if not _values.has(kind):
			_warn_unregistered_once(kind)
			return _default_for_type(expected_value_type)
		var v: AttributeValue = _values[kind]
		if v.value_type != expected_value_type:
			GDGameLogger.log_error_p("[AttributeSet] get_current_typed 类型不一致 kind=%d stored=%d requested=%d" % [kind, v.value_type, expected_value_type])
			return _default_for_type(expected_value_type)
		return v.current_boxed

	func get_base_typed(kind: int, expected_value_type: int) -> Variant:
		if not _values.has(kind):
			_warn_unregistered_once(kind)
			return _default_for_type(expected_value_type)
		var v: AttributeValue = _values[kind]
		if v.value_type != expected_value_type:
			GDGameLogger.log_error_p("[AttributeSet] get_base_typed 类型不一致 kind=%d stored=%d requested=%d" % [kind, v.value_type, expected_value_type])
			return _default_for_type(expected_value_type)
		return v.boxed_base

	func has_attribute(kind: int) -> bool:
		return _values.has(kind)

	func try_get_value_type(kind: int) -> Dictionary:
		if _values.has(kind):
			var v: AttributeValue = _values[kind]
			return {"ok": true, "value_type": v.value_type}
		return {"ok": false, "value_type": GDCoreTypes.KeywordValueType.INT}

	func set_base(kind: int, base_val: float, reason: String = "set-base") -> void:
		_set_base_core(kind, GDCoreTypes.KeywordValueType.FLOAT, base_val, reason, true)

	func set_base_typed(kind: int, value_type: int, base_val: Variant, reason: String = "set-base") -> void:
		_set_base_core(kind, value_type, base_val, reason, true)

	func apply_delta(kind: int, delta: float, reason: String = "delta") -> void:
		if not _values.has(kind):
			set_base(kind, delta, reason)
			return
		var cur: AttributeValue = _values[kind]
		if cur.value_type != GDCoreTypes.KeywordValueType.INT and cur.value_type != GDCoreTypes.KeywordValueType.FLOAT:
			GDGameLogger.log_error_p("[AttributeSet] ApplyDelta 仅支持 Int/Float kind=%d vt=%d" % [kind, cur.value_type])
			return
		var old_boxed: Variant = cur.current_boxed
		var old_num: float = cur.current
		var next_val: AttributeValue = cur.apply_delta(delta)
		_values[kind] = next_val
		_raise_if_changed(kind, old_num, old_boxed, next_val.current, next_val.current_boxed, reason)

	func add_modifier(kind: int, add_bonus: float, mul_bonus: float, reason: String = "modifier-added") -> void:
		var cur: AttributeValue
		if _values.has(kind):
			cur = _values[kind]
		else:
			cur = AttributeValue.new(GDCoreTypes.KeywordValueType.FLOAT, 0.0)
		if cur.value_type != GDCoreTypes.KeywordValueType.INT and cur.value_type != GDCoreTypes.KeywordValueType.FLOAT:
			GDGameLogger.log_error_p("[AttributeSet] AddModifier 仅支持 Int/Float kind=%d vt=%d" % [kind, cur.value_type])
			return
		var old_boxed: Variant = cur.current_boxed
		var old_num: float = cur.current
		var next_val: AttributeValue = cur.with_modifier(add_bonus, mul_bonus)
		_values[kind] = next_val
		_raise_if_changed(kind, old_num, old_boxed, next_val.current, next_val.current_boxed, reason)

	func remove_modifier(kind: int, add_bonus: float, mul_bonus: float, reason: String = "modifier-removed") -> void:
		if not _values.has(kind):
			GDGameLogger.log_warning("[AttributeSet] RemoveModifier 时 kind '%d' 未注册，已忽略。" % kind)
			return
		var cur: AttributeValue = _values[kind]
		if cur.value_type != GDCoreTypes.KeywordValueType.INT and cur.value_type != GDCoreTypes.KeywordValueType.FLOAT:
			GDGameLogger.log_error_p("[AttributeSet] RemoveModifier 仅支持 Int/Float kind=%d vt=%d" % [kind, cur.value_type])
			return
		var old_boxed: Variant = cur.current_boxed
		var old_num: float = cur.current
		var next_val: AttributeValue = cur.with_modifier(-add_bonus, -mul_bonus)
		_values[kind] = next_val
		_raise_if_changed(kind, old_num, old_boxed, next_val.current, next_val.current_boxed, reason)

	func set_override(kind: int, override_val: Variant, reason: String = "override") -> void:
		var cur: AttributeValue
		if _values.has(kind):
			cur = _values[kind]
		else:
			cur = AttributeValue.new(GDCoreTypes.KeywordValueType.FLOAT, 0.0)
		var old_boxed: Variant = cur.current_boxed
		var old_num: float = cur.current
		var next_val: AttributeValue = cur.with_override(override_val)
		_values[kind] = next_val
		_raise_if_changed(kind, old_num, old_boxed, next_val.current, next_val.current_boxed, reason)

	func get_all_kinds() -> Array:
		return _values.keys()

	func apply_initial_overrides(overrides: Array) -> void:
		for entry in overrides:
			if entry is AttributeInitialOverride:
				set_base(entry.kind, entry.base_value, "level-config-override")
			elif entry is Dictionary:
				set_base(int(entry.get("kind", 0)), float(entry.get("base_value", 0.0)), "level-config-override")

	func _set_base_core(kind: int, vt: int, base_val: Variant, reason: String, create_if_missing: bool) -> void:
		var old_boxed: Variant = null
		var old_num: float = 0.0
		var next_val: AttributeValue
		if _values.has(kind):
			var existing: AttributeValue = _values[kind]
			if existing.value_type != vt:
				GDGameLogger.log_error_p("[AttributeSet] SetBase 类型与已注册 ValueType 不一致 kind=%d stored=%d requested=%d" % [kind, existing.value_type, vt])
				return
			old_boxed = existing.current_boxed
			old_num = existing.current
			next_val = existing.with_base(base_val)
		else:
			if not create_if_missing:
				return
			next_val = AttributeValue.new(vt, base_val)
		_values[kind] = next_val
		_raise_if_changed(kind, old_num, old_boxed, next_val.current, next_val.current_boxed, reason)

	func _raise_if_changed(kind: int, old_num: float, old_boxed: Variant, new_num: float, new_boxed: Variant, reason: String) -> void:
		var safe_reason := reason if reason != null else ""
		if old_boxed != new_boxed:
			attribute_value_changed.emit(kind, old_boxed, new_boxed, safe_reason)
		if not is_equal_approx(old_num, new_num):
			attribute_changed.emit(kind, old_num, new_num, safe_reason)

	func _warn_unregistered_once(kind: int) -> void:
		if not _warned_kinds.has(kind):
			_warned_kinds[kind] = true
			GDGameLogger.log_warning("[AttributeSet] 访问了未注册的 kind '%d'，返回 default。" % kind)

	static func _default_for_type(vt: int) -> Variant:
		match vt:
			GDCoreTypes.KeywordValueType.INT:
				return 0
			GDCoreTypes.KeywordValueType.FLOAT:
				return 0.0
			GDCoreTypes.KeywordValueType.STRING:
				return ""
			GDCoreTypes.KeywordValueType.BOOL:
				return false
			_:
				return null
