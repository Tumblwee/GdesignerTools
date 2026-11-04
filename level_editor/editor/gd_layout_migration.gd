@tool
class_name GDLayoutMigration
extends RefCounted

## 关卡 ID 迁移工具（对应 LayoutIdMigrationTool）：把实例 ID 重排到 10000+ 连续段，可选重映射原型 StableId。

class MigrationOptions extends RefCounted:
	var dry_run: bool = true
	var remap_archetype_stable_ids: bool = false
	var id_start: int = GDLevelSceneRes.INSTANCE_ID_START
	var force_reindex: bool = false


class MigrationReport extends RefCounted:
	var layout_count: int = 0
	var placement_count: int = 0
	var instance_id_reassigned: int = 0
	var archetype_remapped: int = 0
	var notes: Array[String] = []

	func format_report() -> String:
		var lines: PackedStringArray = PackedStringArray([
			"[LayoutIdMigrationTool] Report:",
			"  Layouts scanned          : %d" % layout_count,
			"  Placements total         : %d" % placement_count,
			"  InstanceId re-assigned   : %d" % instance_id_reassigned,
			"  Archetype StableId remap : %d" % archetype_remapped,
			"  Notes:",
		])
		for n in notes:
			lines.append("    - " + n)
		return "\n".join(lines)


static func run_migration(layouts: Array, opts: MigrationOptions = null) -> MigrationReport:
	var options := opts if opts != null else MigrationOptions.new()
	var report := MigrationReport.new()
	for item in layouts:
		if item == null or not (item is GDLevelSceneRes):
			continue
		var layout := item as GDLevelSceneRes
		report.layout_count += 1
		migrate_one_layout(layout, options, report)
	return report

static func migrate_one_layout(layout: GDLevelSceneRes, opts: MigrationOptions, report: MigrationReport) -> void:
	var arch_remap: Dictionary = {}
	if opts.remap_archetype_stable_ids and not layout.archetypes.is_empty():
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
	if placements.is_empty():
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
