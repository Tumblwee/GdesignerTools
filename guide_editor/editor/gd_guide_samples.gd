@tool
class_name GDGuideSamples
extends RefCounted

## 示例引导图（对应 GuideSampleGraphs）：假事件推进示例与条件 / 触发示例。

const SAMPLE_GRAPH_ID := 9001
const SAMPLE_NAME := "示例：假事件推进"
const CONDITION_SAMPLE_ID := 9002

static var _built: Array[GDGuideGraphRes] = []

## 示例图只放在内存注册表里。返回两张示例图（首次调用时构建）。
static func ensure_registered() -> Array[GDGuideGraphRes]:
	if _built.is_empty():
		var sample := GDGuideGraphRes.new()
		build_sample(sample)
		var condition := GDGuideGraphRes.new()
		build_condition_sample(condition)
		_built = [sample, condition]
	for g in _built:
		if GDGuideEditing.find_graph(g.graph_id) == null:
			GDGuideEditing.register_in_memory_graph(g)
	return _built

## 保存到磁盘以后就不再算示例，而是项目自己的图。
static func is_sample(g: GDGuideGraphRes) -> bool:
	return g != null and g.resource_path.is_empty() and _built.has(g)

static func build_sample(graph: GDGuideGraphRes) -> void:
	graph.clear_for_rebuild()
	graph.set_schema_version(GDGuideGraphRes.CURRENT_SCHEMA_VERSION)
	graph.set_graph_id(SAMPLE_GRAPH_ID)
	graph.set_display_name(SAMPLE_NAME)
	graph.set_enabled(true)
	graph.set_allow_skip(true)

	var entry := GDGuideAtoms.EntryAtom.new()
	graph.add_atom(entry, Vector2(0.0, 0.0))

	var welcome := GDGuideAtoms.NarrationAtom.new()
	welcome.set_display_name("欢迎")
	welcome.set_text("欢迎来到引导示例：这张图全靠假事件推进。", "向导")
	graph.add_atom(welcome, Vector2(240.0, 0.0))

	var start := GDGuideAtoms.NarrationAtom.new()
	start.set_display_name("点开始")
	start.set_text("点这里开始")
	graph.add_atom(start, Vector2(500.0, 0.0))

	var panel := GDGuideAtoms.LockWaitAtom.new()
	panel.set_display_name("等示例面板")
	panel.set_event_key("SamplePanelReady")
	panel.set_text("面板加载中…")
	graph.add_atom(panel, Vector2(760.0, 0.0))

	var has_coin := GDGuideAtoms.BranchAtom.new()
	has_coin.set_display_name("已有金币？")
	has_coin.set_conditions([
		GDGuideData.GuideConditionExpr.create_compare("io.guide.sample_has_coin", GDGuideData.GuideValue.new(), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_bool(true))
	])
	graph.add_atom(has_coin, Vector2(1020.0, 0.0))

	var grant := GDGuideAtoms.WaitEventAtom.new()
	grant.set_display_name("等发金币")
	grant.set_event_key("SampleCoinGranted")
	graph.add_atom(grant, Vector2(1280.0, 200.0))

	var collect := GDGuideAtoms.WaitEventAtom.new()
	collect.set_display_name("去收金币")
	collect.set_event_key("SampleCoinCollected")
	collect.set_timeout(12.0)
	graph.add_atom(collect, Vector2(1540.0, 0.0))

	var settle := GDGuideAtoms.DelayAtom.new()
	settle.set_display_name("缓一下")
	settle.set_delay(0.5)
	graph.add_atom(settle, Vector2(1800.0, 0.0))

	var done := GDGuideAtoms.ExitAtom.new()
	done.set_display_name("完成")
	done.set_reason(GDGuideData.GuideExitReason.COMPLETED)
	graph.add_atom(done, Vector2(2040.0, 0.0))

	var later := GDGuideAtoms.ExitAtom.new()
	later.set_display_name("暂缓")
	later.set_reason(GDGuideData.GuideExitReason.DEFERRED)
	graph.add_atom(later, Vector2(1800.0, 240.0))

	graph.connect_nodes(entry.id, GDGuideData.GuidePortKind.EXEC_OUT, welcome.id)
	graph.connect_nodes(welcome.id, GDGuideData.GuidePortKind.EXEC_OUT, start.id)
	graph.connect_nodes(start.id, GDGuideData.GuidePortKind.EXEC_OUT, panel.id)
	graph.connect_nodes(panel.id, GDGuideData.GuidePortKind.EXEC_OUT, has_coin.id)
	graph.connect_nodes(has_coin.id, GDGuideData.GuidePortKind.EXEC_TRUE, collect.id)
	graph.connect_nodes(has_coin.id, GDGuideData.GuidePortKind.EXEC_FALSE, grant.id)
	graph.connect_nodes(grant.id, GDGuideData.GuidePortKind.EXEC_OUT, collect.id)
	graph.connect_nodes(collect.id, GDGuideData.GuidePortKind.EXEC_OUT, settle.id)
	graph.connect_nodes(collect.id, GDGuideData.GuidePortKind.EXEC_TIMEOUT, later.id)
	graph.connect_nodes(settle.id, GDGuideData.GuidePortKind.EXEC_OUT, done.id)

static func build_condition_sample(graph: GDGuideGraphRes) -> void:
	graph.clear_for_rebuild()
	graph.set_schema_version(GDGuideGraphRes.CURRENT_SCHEMA_VERSION)
	graph.set_graph_id(CONDITION_SAMPLE_ID)
	graph.set_display_name("示例：条件与触发")
	graph.set_enabled(true)
	graph.set_allow_skip(true)

	var entry := GDGuideAtoms.EntryAtom.new()
	entry.set_trigger_event(GDGuideData.GuideEventRef.new("SampleStart"))
	entry.set_conditions([
		GDGuideData.GuideConditionExpr.create_compare("io.guide.sample_has_coin", GDGuideData.GuideValue.new(), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_bool(true))
	])
	graph.add_atom(entry, Vector2(0.0, 0.0))

	var wait_c := GDGuideAtoms.ConditionWaitAtom.new()
	wait_c.set_display_name("等待花掉金币")
	wait_c.configure([
		GDGuideData.GuideConditionExpr.create_compare("io.guide.sample_has_coin", GDGuideData.GuideValue.new(), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_bool(false))
	], 30.0, 0.1)
	graph.add_atom(wait_c, Vector2(360.0, 0.0))

	var done := GDGuideAtoms.ExitAtom.new()
	done.set_reason(GDGuideData.GuideExitReason.COMPLETED)
	graph.add_atom(done, Vector2(760.0, 0.0))

	var later := GDGuideAtoms.ExitAtom.new()
	later.set_display_name("稍后再试")
	later.set_reason(GDGuideData.GuideExitReason.DEFERRED)
	graph.add_atom(later, Vector2(760.0, 240.0))

	graph.connect_nodes(entry.id, GDGuideData.GuidePortKind.EXEC_OUT, wait_c.id)
	graph.connect_nodes(wait_c.id, GDGuideData.GuidePortKind.EXEC_OUT, done.id)
	graph.connect_nodes(wait_c.id, GDGuideData.GuidePortKind.EXEC_TIMEOUT, later.id)
