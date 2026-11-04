@tool
class_name GDArchetypeOps
extends RefCounted

## 原型复写（Override / Variant）与复制的共享逻辑，关卡编辑器与演员编辑器共用。
## 命名与资产路径约定由各编辑器自己的服务决定（如 GDActorEditorServices）。

const MAX_OVERRIDE_CHAIN_DEPTH := 64

## candidate_base 的复写链（自身、其基底、基底的基底……）中出现 override_arch 即成环。
static func would_form_cycle(override_arch: GDArchetypeRes, candidate_base: GDArchetypeRes) -> bool:
	if override_arch == null:
		return false
	var cursor := candidate_base
	for _depth in MAX_OVERRIDE_CHAIN_DEPTH:
		if cursor == null:
			return false
		if cursor == override_arch:
			return true
		cursor = cursor.override_base_archetype
	return false

## candidates 中直接以 base_arch 为复写基底的原型个数。
static func count_overrides_of(base_arch: GDArchetypeRes, candidates: Array) -> int:
	if base_arch == null:
		return 0
	return candidates.filter(func(a: Variant) -> bool: return a is GDArchetypeRes and a != base_arch and a.override_base_archetype == base_arch).size()

## 把复写原型改挂到 new_base；预览 Prefab 原本跟随旧基底时一并跟随新基底。独立落盘的原型会立即保存。
static func try_rebind_base(override_arch: GDArchetypeRes, new_base: GDArchetypeRes) -> Dictionary:
	if override_arch == null or new_base == null:
		return {"ok": false, "error": "复写目标无效。"}
	if override_arch == new_base:
		return {"ok": false, "error": "不能把原型自己当复写目标。"}
	if would_form_cycle(override_arch, new_base):
		return {"ok": false, "error": "复写链会成环：目标原型的复写链里已经包含本原型。"}
	if new_base.manufactured_prefab_address.is_empty():
		return {"ok": false, "error": "目标原型未配置「实例」Prefab，无法建 Prefab Variant。"}

	var old_base := override_arch.override_base_archetype
	var preview_follows_base := old_base != null and override_arch.preview_prefab_address == old_base.preview_prefab_address
	override_arch.editor_set_prefab_addresses(
		override_arch.manufactured_prefab_address if not override_arch.manufactured_prefab_address.is_empty() else new_base.manufactured_prefab_address,
		new_base.preview_prefab_address if preview_follows_base else override_arch.preview_prefab_address
	)
	override_arch.editor_set_override_base(new_base)
	if override_arch.resource_path.is_absolute_path() and not override_arch.resource_path.contains("::"):
		ResourceSaver.save(override_arch, override_arch.resource_path)
	return {"ok": true, "error": ""}

## 复制原型（同脚本类型，自定义属性逐个克隆，不深拷贝复写基底）。
## as_override 时新原型以 source 为复写基底；否则是独立原型。
## entity_address 为空时沿用 source 的实例 Prefab 地址（source 也没有则用 "Entity_<new_name>"）。
static func create_duplicate(
	source: GDArchetypeRes,
	new_stable_id: int,
	new_name: String,
	new_display_name: String,
	as_override: bool = false,
	entity_address: String = ""
) -> GDArchetypeRes:
	if source == null:
		return null
	var dup: GDArchetypeRes = source.duplicate()
	dup.resource_name = new_name
	if entity_address.is_empty():
		entity_address = source.manufactured_prefab_address if not source.manufactured_prefab_address.is_empty() else "Entity_%s" % new_name
	dup.editor_init_with_addresses(new_stable_id, new_display_name.strip_edges(), entity_address, source.preview_prefab_address)
	var defs: Array[GDCustomAttributeDef] = []
	for def in source.custom_attributes:
		if def != null:
			defs.append(def.clone_def())
	dup.editor_set_custom_attributes(defs)
	dup.is_override_archetype = false
	dup.override_base_archetype = null
	if as_override:
		dup.editor_set_override_base(source)
	return dup
