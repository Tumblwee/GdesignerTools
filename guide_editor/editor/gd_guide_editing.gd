@tool
class_name GDGuideEditing
extends RefCounted

## 引导图编辑服务（对应 GuideGraphEditing / GuideGraphLayout）：
## 内存图注册表、结构编辑（增删节点、强弱引导互转、点击录制）与自动整理布局。

## 自动整理布局的列 / 行间距与网格。
const HORIZONTAL_GAP := 100.0
const VERTICAL_GAP := 60.0
const GRID_SIZE := 20.0

static var _in_memory_graphs: Dictionary = {} # int (graph_id) -> GDGuideGraphRes

# ── Graph registry ──

static func register_in_memory_graph(g: GDGuideGraphRes) -> void:
	if g != null:
		unregister_graph(g)
		var key := g.graph_id if not _in_memory_graphs.has(g.graph_id) else -g.get_instance_id()
		_in_memory_graphs[key] = g

static func find_graph(graph_id: int) -> GDGuideGraphRes:
	return _in_memory_graphs.get(graph_id)

## 已登记的全部引导图（按 graph_id 升序）。
static func find_all_graphs() -> Array[GDGuideGraphRes]:
	var result: Array[GDGuideGraphRes] = []
	result.assign(_in_memory_graphs.values().filter(func(g: Variant) -> bool: return g != null))
	result.sort_custom(func(a: GDGuideGraphRes, b: GDGuideGraphRes) -> bool: return a.graph_id < b.graph_id)
	return result

## 示例图不参与编号，免得新图从 9003 开始。
static func suggest_graph_id(root: String = "res://game_res/guide") -> int:
	var mx := 0
	for g in find_all_graphs():
		if not GDGuideSamples.is_sample(g):
			mx = maxi(mx, g.graph_id)
	var next_id := mx + 1
	while FileAccess.file_exists(root.path_join("Guide_%d.tres" % next_id)) or FileAccess.file_exists(root.path_join("Guide_%d.res" % next_id)):
		next_id += 1
	return next_id

static func suggest_save_path(g: GDGuideGraphRes, root: String = "res://game_res/guide") -> String:
	var stem := "Guide_%d" % g.graph_id
	var path := root.path_join(stem + ".tres")
	var suffix := 2
	while FileAccess.file_exists(path):
		path = root.path_join("%s_%d.tres" % [stem, suffix])
		suffix += 1
	return path

static func unregister_graph(g: GDGuideGraphRes) -> void:
	for key in _in_memory_graphs.keys():
		if _in_memory_graphs[key] == g:
			_in_memory_graphs.erase(key)

## 冲突图保留在列表中，使用负的实例 ID 作临时键，修正 ID 后恢复正常键。
static func reindex() -> void:
	var graphs := find_all_graphs()
	_in_memory_graphs.clear()
	for g in graphs:
		register_in_memory_graph(g)

static func conflicting_graph(g: GDGuideGraphRes, graph_id: int) -> GDGuideGraphRes:
	for other in find_all_graphs():
		if other != g and other.graph_id == graph_id:
			return other
	return null

## 把磁盘上保存过的引导图载入注册表，编辑器重启后也能找到。返回新登记的数量。
static func scan_graphs(root: String = "res://game_res/guide") -> int:
	var dir := DirAccess.open(root)
	if dir == null:
		return 0
	var added := 0
	for file in dir.get_files():
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var g := ResourceLoader.load(root.path_join(file)) as GDGuideGraphRes
		if g == null:
			continue
		var existing := find_graph(g.graph_id)
		if existing == g:
			continue
		if GDGuideSamples.is_sample(existing):
			unregister_graph(existing)
		if not _in_memory_graphs.values().has(g):
			GDGuideSchemaMigrator.migrate(g)
			register_in_memory_graph(g)
			added += 1
	for sub in dir.get_directories():
		added += scan_graphs(root.path_join(sub))
	return added

# ── Structure editing ──

static func add_node(
	graph: GDGuideGraphRes,
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

## 复制节点（入口除外）和它们之间的连线，返回新节点 id。
static func duplicate_nodes(graph: GDGuideGraphRes, node_ids: Array, offset: Vector2) -> Array[int]:
	var copies := {}
	for node_id in node_ids:
		var source := graph.find_atom(node_id)
		if source == null or source is GDGuideAtoms.EntryAtom or source is GDGuideAtoms.MissingAtom:
			continue
		var copy := GDGuideGraphRes.codec().decode(GDGuideGraphRes.codec().encode(source)) as GDGuideAtoms.GuideAtom
		graph.add_atom(copy, source.editor_position + offset)
		copies[node_id] = copy.id
	for e in graph.edges.duplicate():
		if copies.has(e.from_id) and copies.has(e.to_id):
			graph.connect_nodes(copies[e.from_id], e.port, copies[e.to_id])
	var ids: Array[int] = []
	ids.assign(copies.values())
	return ids

static func delete_elements(
	graph: GDGuideGraphRes,
	node_ids: Array,
	edges_from: Array
) -> int:
	if graph == null:
		return 0
	var removed := 0
	for ef in edges_from:
		if ef is Dictionary and graph.disconnect_port(int(ef.get("node_id", 0)), int(ef.get("port", 0))):
			removed += 1
	for nid in node_ids:
		if graph.remove_atom(int(nid)):
			removed += 1
	return removed

static func arrange(
	graph: GDGuideGraphRes,
	sizes: Dictionary = {}
) -> int:
	if graph == null or graph.missing_atom_count > 0:
		return 0
	var moves := calculate_layout(graph, sizes)
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
	graph: GDGuideGraphRes,
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
	graph: GDGuideGraphRes,
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


# ── Auto layout ──

static func calculate_layout(
	graph: GDGuideGraphRes,
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
