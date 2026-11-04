@tool
class_name GDGuideValidation
extends RefCounted

## 引导图与引导库静态校验（对应 GuideValidation / GuideGraphValidator）：问题、报告、校验上下文与校验器。

class GuideValidationIssue extends RefCounted:
	enum Severity {
		WARNING = 0,
		ERROR = 1,
	}

	var severity: int = Severity.ERROR
	var code: String = ""
	var message: String = ""
	var node_id: int = 0

	func _init(p_sev: int, p_code: String, p_msg: String, p_node_id: int = 0) -> void:
		severity = p_sev
		code = p_code
		message = p_msg
		node_id = p_node_id

	var is_error: bool:
		get:
			return severity == Severity.ERROR

	func format_issue() -> String:
		var prefix := "错误" if is_error else "警告"
		var n_str := ("#%d " % node_id) if node_id > 0 else ""
		return "%s [%s] %s%s" % [prefix, code, n_str, message]


class GuideValidationReport extends RefCounted:
	var issues: Array[GuideValidationIssue] = []
	var error_count: int = 0
	var warning_count: int = 0

	var has_errors: bool:
		get:
			return error_count > 0

	var is_clean: bool:
		get:
			return issues.is_empty()

	func add(issue: GuideValidationIssue) -> void:
		issues.append(issue)
		if issue.is_error:
			error_count += 1
		else:
			warning_count += 1

	func contains(p_code: String, p_node_id: int = -1) -> bool:
		for iss in issues:
			if iss.code == p_code and (p_node_id < 0 or iss.node_id == p_node_id):
				return true
		return false

	func worst_for(p_node_id: int) -> int:
		var worst := -1
		for iss in issues:
			if iss.node_id != p_node_id:
				continue
			if iss.is_error:
				return GuideValidationIssue.Severity.ERROR
			worst = GuideValidationIssue.Severity.WARNING
		return worst

	func for_node(p_node_id: int) -> Array[GuideValidationIssue]:
		var out: Array[GuideValidationIssue] = []
		for iss in issues:
			if iss.node_id == p_node_id:
				out.append(iss)
		return out

	func summarize(max_errors: int = 3) -> String:
		var parts: PackedStringArray = PackedStringArray()
		var shown := 0
		for iss in issues:
			if not iss.is_error:
				continue
			if shown >= max_errors:
				return "；".join(parts) + (" 等 %d 项" % error_count)
			var n_str := ("#%d " % iss.node_id) if iss.node_id > 0 else ""
			parts.append(n_str + iss.message)
			shown += 1
		return "无错误" if shown == 0 else "；".join(parts)


class GuideValidationContext extends RefCounted:
	var graph: GDGuideGraphRes = null
	var report: GuideValidationReport = null
	var atom: GDGuideAtoms.GuideAtom = null

	func _init(p_graph: GDGuideGraphRes, p_report: GuideValidationReport) -> void:
		graph = p_graph
		report = p_report

	func add_error(p_code: String, p_msg: String) -> void:
		report.add(GuideValidationIssue.new(GuideValidationIssue.Severity.ERROR, p_code, p_msg, atom.id if atom != null else 0))

	func add_warning(p_code: String, p_msg: String) -> void:
		report.add(GuideValidationIssue.new(GuideValidationIssue.Severity.WARNING, p_code, p_msg, atom.id if atom != null else 0))

	func is_port_connected(port_kind: int) -> bool:
		return atom != null and graph != null and bool(graph.try_get_edge(atom.id, port_kind).get("ok", false))


class GuideGraphValidator extends RefCounted:
	const CODE_GRAPH_NULL := "graph.null"
	const CODE_GRAPH_NO_ID := "graph.no_id"
	const CODE_ENTRY_MISSING := "entry.missing"
	const CODE_ENTRY_MULTIPLE := "entry.multiple"
	const CODE_ENTRY_NO_OUT := "entry.no_out"
	const CODE_MISSING_TYPE := "node.missing_type"
	const CODE_BAD_NODE_ID := "node.bad_id"
	const CODE_DUPLICATE_NODE_ID := "node.duplicate_id"
	const CODE_ORPHAN := "node.orphan"
	const CODE_NO_NAME := "node.no_name"
	const CODE_PORT_UNCONNECTED := "port.unconnected"
	const CODE_EDGE_DANGLING := "edge.dangling"
	const CODE_EDGE_BAD_PORT := "edge.bad_port"
	const CODE_EDGE_BAD_TARGET := "edge.bad_target"
	const CODE_EDGE_SELF := "edge.self"
	const CODE_EDGE_DUPLICATE := "edge.duplicate"
	const CODE_IMMEDIATE_CYCLE := "cycle.immediate"
	const CODE_TIMEOUT_TO_STEP := "timeout.to_step"
	const CODE_TIMEOUT_TO_COMPLETED := "timeout.to_completed"
	const CODE_LIBRARY_NULL_GRAPH := "library.null_graph"
	const CODE_LIBRARY_DUPLICATE_ID := "library.duplicate_id"

	static func validate(
		graph: GDGuideGraphRes,
		missing_atoms: Array = [],
		conditions: GDGuideServices.GuideConditionRegistry = null
	) -> GuideValidationReport:
		return _validate_nested(graph, missing_atoms, conditions, {})

	static func _validate_nested(
		graph: GDGuideGraphRes,
		missing_atoms: Array,
		conditions: GDGuideServices.GuideConditionRegistry,
		ancestors: Dictionary
	) -> GuideValidationReport:
		var report := GuideValidationReport.new()
		if graph == null:
			report.add(_err(CODE_GRAPH_NULL, "图为空", 0))
			return report
		if graph.schema_version != GDGuideGraphRes.CURRENT_SCHEMA_VERSION:
			report.add(_err("graph.schema", "数据版本不支持，请先在引导编辑器打开迁移", 0))
		if ancestors.size() >= 16 or ancestors.has(graph):
			report.add(_err("subgraph.recursion", "子图递归或嵌套超过 16 层", 0))
			return report
		ancestors[graph] = true

		var nodes: Dictionary = {}
		var ordered: Array[GDGuideAtoms.GuideAtom] = []
		var null_slots := 0
		for a in graph.atoms:
			if a == null:
				null_slots += 1
				continue
			if a is GDGuideAtoms.MissingAtom:
				null_slots += 1
				continue
			if a.id <= 0:
				report.add(_err(CODE_BAD_NODE_ID, "「%s」的 id 无效（%d）" % [a.title, a.id], 0))
				continue
			if nodes.has(a.id):
				report.add(_err(CODE_DUPLICATE_NODE_ID, "节点 id 重复：#%d" % a.id, a.id))
				continue
			nodes[a.id] = a
			ordered.append(a)

		var missing: Dictionary = {}
		for m in missing_atoms:
			if m is GDGuideAtoms.MissingAtom and m.id > 0 and not nodes.has(m.id):
				missing[m.id] = m
		for a in graph.atoms:
			if a is GDGuideAtoms.MissingAtom and a.id > 0 and not nodes.has(a.id):
				missing[a.id] = a

		if null_slots > 0:
			if not missing.is_empty():
				for m in missing.values():
					var ma := m as GDGuideAtoms.MissingAtom
					report.add(_err(CODE_MISSING_TYPE, "节点类型缺失：%s" % ma.type_name, ma.id))
			else:
				report.add(_err(CODE_MISSING_TYPE, "有 %d 个节点类型缺失" % null_slots, 0))

		if graph.graph_id == 0:
			report.add(_warn(CODE_GRAPH_NO_ID, "图 Id 为 0，进度会和其他没填 Id 的图记在一起", 0))

		# Check entries
		var entry: GDGuideAtoms.EntryAtom = null
		for a in ordered:
			if a is GDGuideAtoms.EntryAtom:
				if entry == null:
					entry = a
				else:
					report.add(_err(CODE_ENTRY_MULTIPLE, "入口多于一个（已有 #%d）" % entry.id, a.id))
		if entry == null:
			report.add(_err(CODE_ENTRY_MISSING, "没有入口节点", 0))

		# Check edges
		var seen_port_edges: Dictionary = {}
		for edge in graph.edges:
			if edge == null:
				continue
			var from_a: GDGuideAtoms.GuideAtom = nodes.get(edge.from_id, null)
			var to_a: GDGuideAtoms.GuideAtom = nodes.get(edge.to_id, null)
			if from_a == null and not missing.has(edge.from_id):
				report.add(_err(CODE_EDGE_DANGLING, "边的起点 #%d 不存在" % edge.from_id, edge.to_id))
			if to_a == null and not missing.has(edge.to_id):
				report.add(_err(CODE_EDGE_DANGLING, "边指向不存在的节点 #%d" % edge.to_id, edge.from_id))
			if edge.from_id == edge.to_id:
				report.add(_err(CODE_EDGE_SELF, "节点连到了自己", edge.from_id))
			if from_a != null and (not GDGuideData.GuidePorts.is_output(edge.port) or not from_a.has_port(edge.port)):
				report.add(_err(CODE_EDGE_BAD_PORT, "「%s」没有「%s」口，却连了边" % [from_a.title, GDGuideData.GuidePorts.label(edge.port)], from_a.id))
			if to_a != null and not to_a.has_port(GDGuideData.GuidePortKind.EXEC_IN):
				report.add(_err(CODE_EDGE_BAD_TARGET, "「%s」不能被连入" % to_a.title, to_a.id))
			var pkey := "%d::%d" % [edge.from_id, edge.port]
			if seen_port_edges.has(pkey):
				report.add(_err(CODE_EDGE_DUPLICATE, "同一输出口连了多条边", edge.from_id))
			seen_port_edges[pkey] = true

		# Reachable & Ports
		var reachable := _collect_reachable(graph, nodes, entry.id) if entry != null else {}
		for a in ordered:
			if a is GDGuideAtoms.EntryAtom:
				if not bool(graph.try_get_edge(a.id, GDGuideData.GuidePortKind.EXEC_OUT).get("ok", false)):
					report.add(_err(CODE_ENTRY_NO_OUT, "入口没有连出去", a.id))
				continue
			if not reachable.has(a.id):
				if entry != null:
					report.add(_warn(CODE_ORPHAN, "「%s」从入口走不到" % a.title, a.id))
				continue
			for p in a.get_ports():
				if p.is_input or p.kind == GDGuideData.GuidePortKind.EXEC_FALSE or not p.required:
					continue
				if not bool(graph.try_get_edge(a.id, p.kind).get("ok", false)):
					report.add(_err(CODE_PORT_UNCONNECTED, "「%s」的「%s」口必须连线" % [a.title, GDGuideData.GuidePorts.label(p.kind)], a.id))

		# Immediate cycles (CompletesOnEnter 节点环检测)
		_check_immediate_cycles(graph, ordered, nodes, report)
		# Timeout edges
		_check_timeout_edges(graph, nodes, report)

		# Node names & conditions & atom self-validate
		for a in ordered:
			if a.display_name.is_empty() and not (a is GDGuideAtoms.EntryAtom) and not (a is GDGuideAtoms.ExitAtom):
				report.add(_warn(CODE_NO_NAME, "%s #%d 没有节点名，日志里不好认" % [a.title, a.id], a.id))

		if conditions != null:
			for r_err in conditions.registration_errors:
				report.add(_err("condition.registry", r_err, 0))
			for a in ordered:
				for row in a.get_conditions():
					var c_err := conditions.validate_expr(row)
					if not c_err.is_empty():
						report.add(_err("condition.invalid", c_err, a.id))

		var vctx := GuideValidationContext.new(graph, report)
		for a in ordered:
			vctx.atom = a
			if not a.exit_on_timeout and not bool(graph.try_get_edge(a.id, GDGuideData.GuidePortKind.EXEC_TIMEOUT).get("ok", false)) and a.blocks_input:
				vctx.add_warning("timeout.locked", "未连接超时口且关闭超时退出，超时后将持续锁屏")
			a.validate(vctx)

		for a in ordered:
			if a is GDGuideAtoms.SubgraphAtom and (a as GDGuideAtoms.SubgraphAtom).graph is GDGuideGraphRes:
				var sub := (a as GDGuideAtoms.SubgraphAtom).graph as GDGuideGraphRes
				var nested := _validate_nested(sub, [], conditions, ancestors)
				for iss in nested.issues:
					report.add(GuideValidationIssue.new(iss.severity, iss.code, "子图「%s」#%d：%s" % [sub.display_name, iss.node_id, iss.message], a.id))

		ancestors.erase(graph)
		return report

	static func validate_library(library: GDGuideLibraryRes) -> GuideValidationReport:
		var report := GuideValidationReport.new()
		if library == null:
			report.add(_err(CODE_GRAPH_NULL, "库为空", 0))
			return report
		var seen: Dictionary = {}
		for i in range(library.graphs.size()):
			var g := library.graphs[i]
			if g == null:
				report.add(_warn(CODE_LIBRARY_NULL_GRAPH, "第 %d 项是空引用" % (i + 1), 0))
				continue
			if seen.has(g.graph_id):
				var other: GDGuideGraphRes = seen[g.graph_id]
				report.add(_err(CODE_LIBRARY_DUPLICATE_ID, "图 Id %d 重复：「%s」与「%s」" % [g.graph_id, other.display_name, g.display_name], 0))
				continue
			seen[g.graph_id] = g
		return report

	static func _collect_reachable(graph: GDGuideGraphRes, nodes: Dictionary, entry_id: int) -> Dictionary:
		var reachable := {entry_id: true}
		var queue: Array[int] = [entry_id]
		while not queue.is_empty():
			var cur := queue.pop_front()
			for e in graph.edges:
				if e == null or e.from_id != cur or not nodes.has(e.to_id):
					continue
				if not reachable.has(e.to_id):
					reachable[e.to_id] = true
					queue.append(e.to_id)
		return reachable

	static func _check_immediate_cycles(graph: GDGuideGraphRes, ordered: Array[GDGuideAtoms.GuideAtom], nodes: Dictionary, report: GuideValidationReport) -> void:
		var color: Dictionary = {} # 0=unvisited, 1=on_stack, 2=done
		var stack: Array[int] = []
		var reported: Dictionary = {}

		for a in ordered:
			if a.completes_on_enter and not color.has(a.id):
				_visit_immediate(a.id, graph, nodes, color, stack, reported, report)

	static func _visit_immediate(
		node_id: int,
		graph: GDGuideGraphRes,
		nodes: Dictionary,
		color: Dictionary,
		stack: Array[int],
		reported: Dictionary,
		report: GuideValidationReport
	) -> void:
		color[node_id] = 1
		stack.append(node_id)
		for edge in graph.edges:
			if edge == null or edge.from_id != node_id or not nodes.has(edge.to_id):
				continue
			var next_a: GDGuideAtoms.GuideAtom = nodes[edge.to_id]
			if not next_a.completes_on_enter:
				continue
			var st := int(color.get(edge.to_id, 0))
			if st == 0:
				_visit_immediate(edge.to_id, graph, nodes, color, stack, reported, report)
			elif st == 1:
				var start_idx := stack.find(edge.to_id)
				var cycle := stack.slice(start_idx)
				var sorted := cycle.duplicate()
				sorted.sort()
				var key := str(sorted)
				if not reported.has(key):
					reported[key] = true
					report.add(_err(CODE_IMMEDIATE_CYCLE, "无等待环（进入即离开的节点互相连成环）", edge.to_id))
		stack.pop_back()
		color[node_id] = 2

	static func _check_timeout_edges(graph: GDGuideGraphRes, nodes: Dictionary, report: GuideValidationReport) -> void:
		for edge in graph.edges:
			if edge == null or edge.port != GDGuideData.GuidePortKind.EXEC_TIMEOUT or not nodes.has(edge.to_id):
				continue
			var from_a: GDGuideAtoms.GuideAtom = nodes.get(edge.from_id, null)
			var to_a: GDGuideAtoms.GuideAtom = nodes[edge.to_id]
			var from_title := from_a.title if from_a != null else ("#%d" % edge.from_id)
			if to_a is GDGuideAtoms.ExitAtom:
				if (to_a as GDGuideAtoms.ExitAtom).reason == GDGuideData.GuideExitReason.COMPLETED:
					report.add(_warn(CODE_TIMEOUT_TO_COMPLETED, "「%s」的超时连到了「完成」出口：超时不是成功，通常应连暂缓出口" % from_title, edge.from_id))
			elif not (to_a is GDGuideAtoms.BranchAtom):
				report.add(_warn(CODE_TIMEOUT_TO_STEP, "「%s」的超时连到了普通步骤「%s」，疑似把超时当成功" % [from_title, to_a.title], edge.from_id))

	static func _err(code: String, msg: String, nid: int) -> GuideValidationIssue:
		return GuideValidationIssue.new(GuideValidationIssue.Severity.ERROR, code, msg, nid)

	static func _warn(code: String, msg: String, nid: int) -> GuideValidationIssue:
		return GuideValidationIssue.new(GuideValidationIssue.Severity.WARNING, code, msg, nid)
