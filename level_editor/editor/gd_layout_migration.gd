@tool
class_name GDLayoutMigrationAndArchetypeOps
extends RefCounted

## 关卡 ID 迁移工具 + 原型重命名/复制/Override 复写服务
## 对应 LayoutIdMigrationTool + PlacementArchetypeOverrideService + PlacementArchetypeRenameService + PlacementArchetypeDuplicatePopup

class MigrationOptions extends RefCounted:
	var dry_run: bool = true
	var remap_archetype_stable_ids: bool = false
	var zero_out_prefab_marker_instance_ids: bool = true
	var id_start: int = GDLevelSceneRes.INSTANCE_ID_START
	var force_reindex: bool = false


class MigrationReport extends RefCounted:
	var layout_count: int = 0
	var placement_count: int = 0
	var instance_id_reassigned: int = 0
	var archetype_remapped: int = 0
	var marker_cleared: int = 0
	var notes: Array[String] = []

	func format_report() -> String:
		var lines: PackedStringArray = PackedStringArray([
			"[LayoutIdMigrationTool] Report:",
			"  Layouts scanned          : %d" % layout_count,
			"  Placements total         : %d" % placement_count,
			"  InstanceId re-assigned   : %d" % instance_id_reassigned,
			"  Archetype StableId remap : %d" % archetype_remapped,
			"  Prefab Marker cleared    : %d" % marker_cleared,
			"  Notes:",
		])
		for n in notes:
			lines.append("    - " + n)
		return "\n".join(lines)


static func run_migration(layouts: Array, opts: MigrationOptions = null) -> MigrationReport:
	var options := opts if opts != null else MigrationOptions.new()
	var report := MigrationReport.new()
	if layouts == null:
		return report
	for item in layouts:
		if item == null or not (item is GDLevelSceneRes):
			continue
		var layout := item as GDLevelSceneRes
		report.layout_count += 1
		migrate_one_layout(layout, options, report)
	return report

static func migrate_one_layout(layout: GDLevelSceneRes, opts: MigrationOptions, report: MigrationReport) -> void:
	var arch_remap: Dictionary = {}
	if opts.remap_archetype_stable_ids and layout.archetypes != null and not layout.archetypes.is_empty():
		var next_arch := GDLevelSceneRes.STABLE_ID_START
		for a in layout.archetypes:
			if a == null:
				continue
			if not arch_remap.has(a.stable_id):
				arch_remap[a.stable_id] = next_arch
				next_arch += 1
		for a in layout.archetypes:
			if a == null or not arch_remap.has(a.stable_id):
				continue
			var new_arch_id := int(arch_remap[a.stable_id])
			if a.stable_id != new_arch_id:
				report.archetype_remapped += 1
				if not opts.dry_run:
					a.editor_bind_stable_id(new_arch_id)

	var n := layout.placements.size()
	report.placement_count += n
	var already_migrated := (not opts.force_reindex) and are_instance_ids_already_migrated(layout.placements, opts.id_start)
	if already_migrated:
		report.notes.append("Layout '%s': instanceId 已是迁移后形态（连续 %d+ 无重复），跳过重排" % [layout.display_name, opts.id_start])
		if not arch_remap.is_empty() and not opts.dry_run:
			for p in layout.placements:
				if p != null and arch_remap.has(p.archetype_stable_id):
					p.editor_rewrite_archetype_stable_id(int(arch_remap[p.archetype_stable_id]))
	else:
		var next_id := opts.id_start
		for p in layout.placements:
			if p == null:
				continue
			var old_id: int = p.instance_id
			if old_id != next_id:
				report.instance_id_reassigned += 1
			if not opts.dry_run:
				p.editor_rewrite_instance_id(next_id)
				if not arch_remap.is_empty() and arch_remap.has(p.archetype_stable_id):
					p.editor_rewrite_archetype_stable_id(int(arch_remap[p.archetype_stable_id]))
			next_id += 1
		if not opts.dry_run:
			layout.next_instance_id = maxi(opts.id_start, next_id)

	if not opts.dry_run:
		layout.editor_reconcile_next_ids_after_load()
		if not layout.resource_path.is_empty():
			ResourceSaver.save(layout, layout.resource_path)

static func are_instance_ids_already_migrated(placements: Array, id_start: int) -> bool:
	if placements == null or placements.is_empty():
		return true
	var seen: Dictionary = {}
	for p in placements:
		if p == null or not (p is GDPlacementData.PlacementInstance):
			return false
		var id := (p as GDPlacementData.PlacementInstance).instance_id
		if id < id_start or seen.has(id):
			return false
		seen[id] = true
	return true


## 原型复写（Variant / Override）与重命名/复制通用服务（LevelEditor 与 ActorEditor 共用）
class ArchetypeOverrideService extends RefCounted:
	const MAX_OVERRIDE_CHAIN_DEPTH := 64

	static func would_form_cycle(override_arch: GDArchetypeRes, candidate_base: GDArchetypeRes) -> bool:
		if override_arch == null or candidate_base == null:
			return false
		var cursor := candidate_base
		var depth := 0
		while cursor != null and depth < MAX_OVERRIDE_CHAIN_DEPTH:
			if cursor == override_arch:
				return true
			cursor = cursor.override_base_archetype
			depth += 1
		return false

	static func count_overrides_of(base_arch: GDArchetypeRes, candidates: Array) -> int:
		if base_arch == null or candidates == null:
			return 0
		var count := 0
		for a in candidates:
			if a is GDArchetypeRes and a != base_arch and (a as GDArchetypeRes).override_base_archetype == base_arch:
				count += 1
		return count

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
		var old_preview := override_arch.preview_prefab_address
		var preview_follows_base := old_base != null and old_preview == old_base.preview_prefab_address

		override_arch.editor_set_prefab_addresses(
			override_arch.manufactured_prefab_address if not override_arch.manufactured_prefab_address.is_empty() else new_base.manufactured_prefab_address,
			new_base.preview_prefab_address if preview_follows_base else old_preview
		)
		override_arch.editor_set_override_base(new_base)
		if not override_arch.resource_path.is_empty():
			ResourceSaver.save(override_arch, override_arch.resource_path)
		return {"ok": true, "error": ""}

	static func create_duplicate_in_memory(
		source: GDArchetypeRes,
		new_stable_id: int,
		new_name: String,
		new_display_name: String,
		as_override: bool = false
	) -> GDArchetypeRes:
		if source == null:
			return null
		var dup: GDArchetypeRes = source.duplicate(true)
		dup.resource_name = new_name
		dup.editor_init_with_addresses(
			new_stable_id,
			new_display_name.strip_edges(),
			source.manufactured_prefab_address if not source.manufactured_prefab_address.is_empty() else ("Entity_%s" % new_name),
			source.preview_prefab_address
		)
		dup.editor_set_archetype_type_stable_id(source.archetype_type_stable_id)
		if as_override:
			dup.editor_set_override_base(source)
		return dup
