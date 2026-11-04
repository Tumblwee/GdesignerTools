@tool
class_name GDGuideEditingAndCli
extends RefCounted

## 新手引导图自动排版（GuideGraphLayout）、结构编辑（GuideGraphEditing）、
## 示例图生成工厂（GuideSampleGraphs）与 CLI 入口（GuideCli：guide.list / guide.validate / guide.create）
## 对应 GuideGraphLayout / GuideGraphEditing / GuideSampleGraphs / GuideCli / GuideNodeCodeGenerator

static var _in_memory_graphs: Dictionary = {} # int (graph_id) -> GuideGraphRes

static func register_in_memory_graph(g: GDGuideGraphAndValidator.GuideGraphRes) -> void:
	if g != null:
		_in_memory_graphs[g.graph_id] = g

static func find_all_graphs() -> Array[GDGuideGraphAndValidator.GuideGraphRes]:
	var result: Array[GDGuideGraphAndValidator.GuideGraphRes] = []
	for k in _in_memory_graphs.keys():
		var g: GDGuideGraphAndValidator.GuideGraphRes = _in_memory_graphs[k]
		if g != null:
			result.append(g)
	result.sort_custom(func(a: GDGuideGraphAndValidator.GuideGraphRes, b: GDGuideGraphAndValidator.GuideGraphRes) -> bool:
		return a.graph_id < b.graph_id
	)
	return result

static func suggest_graph_id() -> int:
	var mx := 0
	for g in find_all_graphs():
		if g.graph_id > mx:
			mx = g.graph_id
	return mx + 1


# ─────────────────────── GuideGraphLayout (自动整理蓝图) ───────────────────────

class GuideGraphLayout extends RefCounted:
	const HORIZONTAL_GAP := 100.0
	const VERTICAL_GAP := 60.0
	const GRID_SIZE := 20.0

	static func calculate(
		graph: GDGuideGraphAndValidator.GuideGraphRes,
		sizes: Dictionary = {}
	) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		if graph == null:
			return result

		var nodes: Array[Dictionary] = []
		var by_id: Dictionary = {}
		for atom in graph.atoms:
			if atom == null or atom.id <= 0 or by_id.has(atom.id):
				continue
			var sz: Vector2 = sizes.get(atom.id, Vector2(280.0, 180.0))
			var valid_sz := Vector2(
				280.0 if (is_nan(sz.x) or is_inf(sz.x) or sz.x <= 0.0) else sz.x,
				180.0 if (is_nan(sz.y) or is_inf(sz.y) or sz.y <= 0.0) else sz.y
			)
			var n := {
				"atom": atom,
				"size": valid_sz,
				"outputs": [],
				"forward": [],
				"incoming": 0,
				"state": 0,
				"next_output": 0,
				"has_child": false,
				"column": 0,
				"row": 0,
			}
			nodes.append(n)
			by_id[atom.id] = n

		if nodes.is_empty():
			return result

		var edges_sorted := graph.edges.duplicate()
		edges_sorted.sort_custom(func(a: GDGuideData.GuideEdge, b: GDGuideData.GuideEdge) -> bool:
			if a.from_id != b.from_id:
				return a.from_id < b.from_id
			var pa := _port_order(a.port)
			var pb := _port_order(b.port)
			if pa != pb:
				return pa < pb
			return a.to_id < b.to_id
		)

		for edge in edges_sorted:
			if edge == null or not by_id.has(edge.from_id) or not by_id.has(edge.to_id):
				continue
			var from_n: Dictionary = by_id[edge.from_id]
			var to_n: Dictionary = by_id[edge.to_id]
			if from_n == to_n:
				continue
			var outs: Array = from_n["outputs"]
			if not outs.has(to_n):
				outs.append(to_n)
				to_n["incoming"] = int(to_n["incoming"]) + 1

		var entry_id := graph.find_entry_id()
		nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_id := (a["atom"] as GDGuideAtoms.GuideAtom).id
			var b_id := (b["atom"] as GDGuideAtoms.GuideAtom).id
			var ap := 0 if a_id == entry_id else (1 if int(a["incoming"]) == 0 else 2)
			var bp := 0 if b_id == entry_id else (1 if int(b["incoming"]) == 0 else 2)
			if ap != bp:
				return ap < bp
			return a_id < b_id
		)

		var stack: Array[Dictionary] = []
		var finished: Array[Dictionary] = []
		var last_row := -1

		for root in nodes:
			if int(root["state"]) != 0:
				continue
			last_row += 1
			root["row"] = last_row
			root["state"] = 1
			stack.append(root)
			while not stack.is_empty():
				var n: Dictionary = stack[stack.size() - 1]
				var outs: Array = n["outputs"]
				var next_idx := int(n["next_output"])
				if next_idx == outs.size():
					n["state"] = 2
					finished.append(n)
					stack.pop_back()
					continue
				n["next_output"] = next_idx + 1
				var nxt: Dictionary = outs[next_idx]
				if int(nxt["state"]) == 1:
					continue
				(n["forward"] as Array).append(nxt)
				if int(nxt["state"]) == 2:
					continue
				if bool(n["has_child"]):
					last_row += 1
					nxt["row"] = last_row
				else:
					nxt["row"] = int(n["row"])
				n["has_child"] = true
				nxt["state"] = 1
				stack.append(nxt)

		var last_column := 0
		for i in range(finished.size() - 1, -1, -1):
			var n := finished[i]
			for nxt in (n["forward"] as Array):
				var next_n: Dictionary = nxt
				next_n["column"] = maxi(int(next_n["column"]), int(n["column"]) + 1)
				last_column = maxi(last_column, int(next_n["column"]))

		var widths: Array[float] = []
		widths.resize(last_column + 1)
		widths.fill(0.0)
		var heights: Array[float] = []
		heights.resize(maxi(1, last_row + 1))
		heights.fill(0.0)

		for n in nodes:
			var col := int(n["column"])
			var row := int(n["row"])
			var sz: Vector2 = n["size"]
			widths[col] = maxf(widths[col], sz.x)
			heights[row] = maxf(heights[row], sz.y)

		var xs := _offsets(widths, HORIZONTAL_GAP)
		var ys := _offsets(heights, VERTICAL_GAP)
		for n in nodes:
			var atom := n["atom"] as GDGuideAtoms.GuideAtom
			var col := int(n["column"])
			var row := int(n["row"])
			result.append({
				"node_id": atom.id,
				"position": Vector2(xs[col], ys[row]),
			})
		return result

	static func _offsets(sizes: Array[float], gap: float) -> Array[float]:
		var out: Array[float] = []
		out.resize(sizes.size())
		out.fill(0.0)
		for i in range(1, sizes.size()):
			out[i] = out[i - 1] + ceilf((sizes[i - 1] + gap) / GRID_SIZE) * GRID_SIZE
		return out

	static func _port_order(port: int) -> int:
		match port:
			GDGuideData.GuidePortKind.EXEC_OUT: return 0
			GDGuideData.GuidePortKind.EXEC_TRUE: return 1
			GDGuideData.GuidePortKind.EXEC_FALSE: return 2
			GDGuideData.GuidePortKind.EXEC_TIMEOUT: return 3
			_: return 4 + port


# ─────────────────────── GuideGraphEditing (结构编辑与强弱互转/点击捕获) ───────────────────────

class GuideGraphEditing extends RefCounted:
	static func add_node(
		graph: GDGuideGraphAndValidator.GuideGraphRes,
		atom_type_id: String,
		position: Vector2,
		connect_from_id: int = 0,
		connect_from_port: int = GDGuideData.GuidePortKind.EXEC_OUT,
		connect_to_id: int = 0
	) -> GDGuideAtoms.GuideAtom:
		if graph == null:
			return null
		var atom := GDGuideAtoms.create_atom_by_id(atom_type_id)
		if atom == null:
			return null
		graph.add_atom(atom, position)
		if connect_from_id > 0:
			graph.connect_nodes(connect_from_id, connect_from_port, atom.id)
		if connect_to_id > 0 and atom.has_port(GDGuideData.GuidePortKind.EXEC_OUT):
			graph.connect_nodes(atom.id, GDGuideData.GuidePortKind.EXEC_OUT, connect_to_id)
		return atom

	static func delete_elements(
		graph: GDGuideGraphAndValidator.GuideGraphRes,
		node_ids: Array,
		edges_from: Array
	) -> int:
		if graph == null:
			return 0
		var removed := 0
		if edges_from != null:
			for ef in edges_from:
				if ef is Dictionary:
					if graph.disconnect_port(int(ef.get("node_id", 0)), int(ef.get("port", 0))):
						removed += 1
		if node_ids != null:
			for nid in node_ids:
				if graph.remove_atom(int(nid)):
					removed += 1
		return removed

	static func arrange(
		graph: GDGuideGraphAndValidator.GuideGraphRes,
		sizes: Dictionary = {}
	) -> int:
		if graph == null or graph.missing_atom_count > 0:
			return 0
		var moves := GuideGraphLayout.calculate(graph, sizes)
		var moved_count := 0
		for m in moves:
			var nid := int(m["node_id"])
			var pos: Vector2 = m["position"]
			var a := graph.find_atom(nid)
			if a != null and a.editor_position != pos:
				graph.set_atom_position(nid, pos)
				moved_count += 1
		return moved_count

	static func convert_guide(
		graph: GDGuideGraphAndValidator.GuideGraphRes,
		node_id: int
	) -> GDGuideAtoms.GuideTargetAtom:
		if graph == null or graph.missing_atom_count > 0:
			return null
		var src := graph.find_atom(node_id)
		if not (src is GDGuideAtoms.GuideTargetAtom):
			return null
		var target_src := src as GDGuideAtoms.GuideTargetAtom
		var alt_id := target_src.alternate_type_id
		if alt_id.is_empty():
			return null
		var converted := GDGuideAtoms.create_atom_by_id(alt_id) as GDGuideAtoms.GuideTargetAtom
		if converted == null:
			return null

		# 复制共有字段并原位替换（保留 id、位置及所有连线）
		converted.assign_id(target_src.id)
		converted.assign_editor_position(target_src.editor_position)
		converted.set_display_name(target_src.display_name)
		converted.set_exit_policies(target_src.exit_on_timeout, target_src.exit_on_condition_fail)
		converted.target = target_src.target
		converted.show_text = target_src.show_text
		converted.text = target_src.text
		converted.speaker = target_src.speaker
		converted.finger_anchor = target_src.finger_anchor
		converted.finger_anchor_offset = target_src.finger_anchor_offset
		converted.text_anchor = target_src.text_anchor
		converted.complete_mode = target_src.complete_mode
		converted.raw_event_key = target_src.raw_event_key
		converted.event_ref = target_src.event_ref
		converted.raw_timeout_sec = target_src.raw_timeout_sec

		for i in range(graph.atoms.size()):
			if graph.atoms[i] != null and graph.atoms[i].id == node_id:
				graph.atoms[i] = converted
				graph.emit_changed()
				return converted
		return null

	static func capture_click(
		graph: GDGuideGraphAndValidator.GuideGraphRes,
		after_node_id: int,
		target: GDGuideData.GuideTargetRef,
		button_name: String = ""
	) -> GDGuideAtoms.GuideTargetAtom:
		if graph == null or graph.missing_atom_count > 0:
			return null
		var after_atom := graph.find_atom(after_node_id)
		if after_atom == null or not after_atom.has_port(GDGuideData.GuidePortKind.EXEC_OUT):
			return null
		if target == null or target.kind != GDGuideData.GuideTargetKind.UI_WIDGET or target.panel.is_empty() or target.widget.is_empty():
			return null

		var pos := after_atom.editor_position + Vector2(320.0, 0.0)
		var occupied := true
		while occupied:
			occupied = false
			for existing in graph.atoms:
				if existing == null:
					continue
				if absf(existing.editor_position.x - pos.x) < 280.0 and absf(existing.editor_position.y - pos.y) < 220.0:
					pos.y += 240.0
					occupied = true
					break

		var edge_res := graph.try_get_edge(after_node_id, GDGuideData.GuidePortKind.EXEC_OUT)
		var next_id := (edge_res["edge"] as GDGuideData.GuideEdge).to_id if bool(edge_res.get("ok", false)) else 0
		var atom := add_node(graph, "io.guide.strong", pos, after_node_id, GDGuideData.GuidePortKind.EXEC_OUT, next_id) as GDGuideAtoms.GuideTargetAtom
		if atom != null:
			atom.set_target(target)
			atom.set_display_name("点击" + (button_name if not button_name.is_empty() else target.widget))
		return atom


# ─────────────────────── GuideSampleGraphs (示例图生成) ───────────────────────

class GuideSampleGraphs extends RefCounted:
	const SAMPLE_GRAPH_ID := 9001
	const SAMPLE_NAME := "示例：假事件推进"

	static func build_sample(graph: GDGuideGraphAndValidator.GuideGraphRes) -> void:
		graph.clear_for_rebuild()
		graph.set_schema_version(GDGuideGraphAndValidator.GuideGraphRes.CURRENT_SCHEMA_VERSION)
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

	static func build_condition_sample(graph: GDGuideGraphAndValidator.GuideGraphRes) -> void:
		graph.clear_for_rebuild()
		graph.set_schema_version(GDGuideGraphAndValidator.GuideGraphRes.CURRENT_SCHEMA_VERSION)
		graph.set_graph_id(9002)
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


# ─────────────────────── GuideCli (guide.list / guide.validate / guide.create) ───────────────────────

class GuideCli extends RefCounted:
	static func run(command: String, args: Array = []) -> String:
		var safe_args := args if args != null else []
		if command == "guide.list":
			var lib_path := _option(safe_args, "--library")
			var graphs: Array = []
			if not lib_path.is_empty():
				if not ResourceLoader.exists(lib_path):
					return _error(command, "library.missing", lib_path)
				var lib := ResourceLoader.load(lib_path) as GDGuideGraphAndValidator.GuideLibraryRes
				if lib == null:
					return _error(command, "library.missing", lib_path)
				graphs = lib.graphs
			else:
				graphs = GDGuideEditingAndCli.find_all_graphs()
			var rows: Array = []
			for g in graphs:
				if g is GDGuideGraphAndValidator.GuideGraphRes:
					var gr := g as GDGuideGraphAndValidator.GuideGraphRes
					rows.append({
						"id": gr.graph_id,
						"name": gr.display_name,
						"path": gr.resource_path,
					})
			return JSON.stringify({
				"ok": true,
				"command": command,
				"graphs": rows,
			})

		var asset_path := _option(safe_args, "--asset")
		if asset_path.is_empty() and not safe_args.is_empty() and not str(safe_args[0]).begins_with("--"):
			asset_path = str(safe_args[0])

		if command == "guide.validate":
			var graph: GDGuideGraphAndValidator.GuideGraphRes = null
			if not asset_path.is_empty() and ResourceLoader.exists(asset_path):
				graph = ResourceLoader.load(asset_path) as GDGuideGraphAndValidator.GuideGraphRes
			elif asset_path.is_valid_int() and GDGuideEditingAndCli._in_memory_graphs.has(asset_path.to_int()):
				graph = GDGuideEditingAndCli._in_memory_graphs[asset_path.to_int()]
			if graph == null:
				return _error(command, "asset.missing", asset_path if not asset_path.is_empty() else "缺少 --asset")
			var report := GDGuideGraphAndValidator.GuideGraphValidator.validate(graph)
			var issues_arr: Array = []
			for i in report.issues:
				issues_arr.append({
					"severity": "Error" if i.is_error else "Warning",
					"code": i.code,
					"message": i.message,
					"nodeId": i.node_id,
				})
			return JSON.stringify({
				"ok": not report.has_errors,
				"command": command,
				"path": asset_path,
				"errors": report.error_count,
				"warnings": report.warning_count,
				"issues": issues_arr,
			})

		if command == "guide.create":
			var id_raw := _option(safe_args, "--id")
			if not id_raw.is_valid_int() or id_raw.to_int() <= 0:
				return _error(command, "id.invalid", "--id 必须是正整数")
			var gid := id_raw.to_int()
			var gname := _option(safe_args, "--name")
			if gname.strip_edges().is_empty():
				return _error(command, "name.missing", "缺少 --name")
			for g in GDGuideEditingAndCli.find_all_graphs():
				if g.graph_id == gid:
					return _error(command, "id.duplicate", "图 Id 已存在")
			var graph := GDGuideGraphAndValidator.GuideGraphRes.new()
			graph.set_graph_id(gid)
			graph.set_display_name(gname.strip_edges())
			graph.add_default_skeleton()
			if not asset_path.is_empty() and asset_path.begins_with("res://"):
				GDCliRoot.AtomCreator.ensure_dir(asset_path.get_base_dir())
				ResourceSaver.save(graph, asset_path)
			GDGuideEditingAndCli.register_in_memory_graph(graph)
			return JSON.stringify({
				"ok": true,
				"command": command,
				"path": asset_path,
			})

		return _error(command, "command.unknown", "支持 guide.list / validate / create")

	static func _option(args: Array, key: String) -> String:
		for i in range(args.size() - 1):
			if str(args[i]) == key:
				return str(args[i + 1])
		return ""

	static func _error(command: String, code: String, message: String) -> String:
		return JSON.stringify({
			"ok": false,
			"command": command,
			"code": code,
			"message": message,
		})
