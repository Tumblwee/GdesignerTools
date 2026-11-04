@tool
class_name GDGuideSchemaMigrator
extends RefCounted

## 引导图数据迁移（v1 -> v2，对应 GuideSchemaMigrator）：旧的分支来源 / 事件键 / 图级触发器改写为条件表达式。

static func migrate(graph: GDGuideGraphRes) -> bool:
	if graph == null or graph.schema_version != 1 or graph.missing_atom_count > 0:
		return false
	for atom in graph.atoms:
		if atom == null:
			continue
		atom.set_exit_policies(true, true)
		if atom is GDGuideAtoms.BranchAtom:
			_migrate_branch(atom)
		elif atom is GDGuideAtoms.WaitEventAtom or atom is GDGuideAtoms.GuideTargetAtom:
			atom.migrate_event()
		elif atom is GDGuideAtoms.LockWaitAtom:
			_migrate_lock_wait(atom)
		elif atom is GDGuideAtoms.EntryAtom and graph.trigger != null:
			_migrate_entry(atom, graph.trigger)
	graph.set_schema_version(GDGuideGraphRes.CURRENT_SCHEMA_VERSION)
	return true

static func _migrate_branch(b: GDGuideAtoms.BranchAtom) -> void:
	match b.source:
		GDGuideData.GuideBranchSource.BLACKBOARD_EQUALS:
			b.set_blackboard_equals(b.key, b.value)
		GDGuideData.GuideBranchSource.CHECKPOINT:
			b.set_checkpoint(b.key)
		GDGuideData.GuideBranchSource.PREDICATE:
			b.set_predicate(b.key, b.value)
		GDGuideData.GuideBranchSource.NEW_PLAYER:
			b.set_new_player()
		GDGuideData.GuideBranchSource.LEVEL_AT_LEAST:
			b.set_level_at_least(b.level)

static func _migrate_lock_wait(l: GDGuideAtoms.LockWaitAtom) -> void:
	l.migrate_event()
	if l.condition == GDGuideData.GuideWaitCondition.PREDICATE:
		l.set_conditions([_compare(
			"io.guide.host_predicate",
			GDGuideData.GuideValue.from_string(GDGuideData.GuideSignalKeys.compose(l.predicate_key, l.predicate_arg)),
			GDGuideData.GuideCompareOp.EQUAL,
			GDGuideData.GuideValue.from_bool(true)
		)])

static func _migrate_entry(e: GDGuideAtoms.EntryAtom, old: GDGuideData.GuideTrigger) -> void:
	if old.kind == GDGuideData.GuideTriggerKind.EVENT_KEY:
		e.set_trigger_event(GDGuideData.GuideEventRef.parse(old.event_key))
	elif old.kind == GDGuideData.GuideTriggerKind.GRAPH_FINISHED:
		e.set_trigger_event(GDGuideData.GuideEventRef.new("GraphFinished"))
	var rows: Array[GDGuideData.GuideConditionExpr] = []
	for pid in old.pre_graph_ids:
		rows.append(_compare("io.guide.graph_done", GDGuideData.GuideValue.from_int(pid), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_bool(true)))
	if old.min_level > 0:
		rows.append(_compare("io.guide.player_level", GDGuideData.GuideValue.new(), GDGuideData.GuideCompareOp.GREATER_OR_EQUAL, GDGuideData.GuideValue.from_int(old.min_level)))
	if old.max_level > 0:
		rows.append(_compare("io.guide.player_level", GDGuideData.GuideValue.new(), GDGuideData.GuideCompareOp.LESS_OR_EQUAL, GDGuideData.GuideValue.from_int(old.max_level)))
	if old.new_player_only:
		rows.append(_compare("io.guide.is_new_player", GDGuideData.GuideValue.new(), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_bool(true)))
	e.set_conditions(rows)

static func _compare(condition_id: String, arg: GDGuideData.GuideValue, op: int, right: GDGuideData.GuideValue) -> GDGuideData.GuideConditionExpr:
	return GDGuideData.GuideConditionExpr.create_compare(condition_id, arg, op, right)
