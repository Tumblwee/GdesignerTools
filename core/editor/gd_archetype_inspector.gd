@tool
class_name GDArchetypeInspector
extends RefCounted

## 关卡原型和演员原型共用的属性区块。


## 表单结构的指纹：变了才需要重建表单。
static func structure_key(archetype: GDArchetypeRes) -> Array:
	var shape: Array = [archetype, archetype.is_override_archetype]
	for def in archetype.custom_attributes:
		shape.append(def)
		shape.append(def.value_type)
	return shape


static func type_items(catalog: Resource) -> Array:
	var items: Array = [["未分类", 0]]
	if catalog != null:
		for entry in catalog.entries:
			if entry != null and not entry.deprecated:
				items.append([entry.display_name if not entry.display_name.is_empty() else entry.entry_name, entry.stable_id])
	return items


static func add_identity(form: GDForm, archetype: GDArchetypeRes, catalog: Resource) -> void:
	form.heading(archetype.display_name, "ID %d" % archetype.stable_id)
	form.text("显示名",
		func() -> String: return archetype.display_name,
		func(value: String) -> void: archetype.editor_set_display_name(value)
	)
	form.choice("类型", type_items(catalog),
		func() -> int: return archetype.archetype_type_stable_id,
		func(id: int) -> void: archetype.editor_set_archetype_type_stable_id(id)
	)


## candidates：可以作为复写基底的原型。
static func add_override(form: GDForm, archetype: GDArchetypeRes, candidates: Array) -> void:
	if not archetype.is_override_archetype:
		return
	var items: Array = [["（丢失）", 0]]
	for candidate: GDArchetypeRes in candidates:
		if candidate != archetype and not GDArchetypeOps.would_form_cycle(archetype, candidate):
			items.append([candidate.display_name, candidate.stable_id])
	form.choice("复写自", items,
		func() -> int: return archetype.override_base_archetype.stable_id if archetype.override_base_archetype != null else 0,
		func(id: int) -> void:
			for candidate: GDArchetypeRes in candidates:
				if candidate.stable_id == id:
					GDArchetypeOps.try_rebind_base(archetype, candidate),
		"这是一个变体。没有复写的字段沿用基底原型。"
	)
	form.live_note(func() -> String: return "" if archetype.override_base_archetype != null else "基底原型已丢失，请重新选择。")


static func add_addresses(form: GDForm, archetype: GDArchetypeRes) -> void:
	form.group("外观")
	form.text("实例 Prefab",
		func() -> String: return archetype.manufactured_prefab_address,
		func(value: String) -> void: archetype.editor_set_prefab_addresses(value, archetype.preview_prefab_address),
		{"tip": "运行时实例化的场景地址"}
	)
	form.text("预览 Prefab",
		func() -> String: return archetype.preview_prefab_address,
		func(value: String) -> void: archetype.editor_set_prefab_addresses(archetype.manufactured_prefab_address, value),
		{"placeholder": "留空时用实例 Prefab", "tip": "只用于预览和拖拽落点"}
	)
	form.end_group()


## on_structure_changed(label)：增删属性后调用。
static func add_custom_attributes(form: GDForm, archetype: GDArchetypeRes, on_structure_changed: Callable) -> void:
	form.group("自定义属性")
	for index in range(archetype.custom_attributes.size()):
		var def := archetype.custom_attributes[index]
		if def != null:
			_add_attribute(form.nested(), archetype, def, on_structure_changed)
	form.button("添加属性", func() -> void:
		archetype.custom_attributes.append(GDCustomAttributeDef.new())
		archetype.emit_changed()
		on_structure_changed.call("添加属性")
	)
	form.end_group()


static func _add_attribute(form: GDForm, archetype: GDArchetypeRes, def: GDCustomAttributeDef, on_structure_changed: Callable) -> void:
	form.text("显示名", func() -> String: return def.display_name, func(value: String) -> void: def.display_name = value)
	form.text("标签",
		func() -> String: return def.tag,
		func(value: String) -> void: def.tag = value,
		{"placeholder": "例如 fog.negative", "tip": "运行时按标签覆盖实例原子上的变量"}
	)
	form.choice("值类型", [["整数", GDCoreTypes.KeywordValueType.INT], ["小数", GDCoreTypes.KeywordValueType.FLOAT], ["文本", GDCoreTypes.KeywordValueType.STRING], ["开关", GDCoreTypes.KeywordValueType.BOOL]],
		func() -> int: return def.value_type,
		func(id: int) -> void: def.value_type = id
	)
	match def.value_type:
		GDCoreTypes.KeywordValueType.INT:
			form.integer("默认值", func() -> int: return def.default_int, func(value: int) -> void: def.default_int = value)
		GDCoreTypes.KeywordValueType.FLOAT:
			form.number("默认值", func() -> float: return def.default_float, func(value: float) -> void: def.default_float = value)
		GDCoreTypes.KeywordValueType.STRING:
			form.text("默认值", func() -> String: return def.default_string, func(value: String) -> void: def.default_string = value)
		GDCoreTypes.KeywordValueType.BOOL:
			form.toggle("默认值", func() -> bool: return def.default_bool, func(value: bool) -> void: def.default_bool = value)
	form.live_note(func() -> String: return _attribute_warning(archetype, def))
	var remove := form.button("删除这条属性", func() -> void:
		archetype.custom_attributes.erase(def)
		archetype.emit_changed()
		on_structure_changed.call("删除属性")
	, &"danger")
	remove.size_flags_horizontal = Control.SIZE_SHRINK_END
	form.custom(HSeparator.new())


static func _attribute_warning(archetype: GDArchetypeRes, def: GDCustomAttributeDef) -> String:
	if def.tag.is_empty():
		return "没有标签，运行时不会生效。"
	for other in archetype.custom_attributes:
		if other != def and other != null and other.tag == def.tag:
			return "标签重复。"
	return ""
