@tool
class_name GDGuideGraphView
extends GraphEdit

## 引导图画布：原生 GraphEdit + GraphNode，按节点 id 增量同步，不整张重建（不闪）。
## 这里只管显示，并把原生信号翻译成“节点 id + 端口种类”；改模型由页面完成。

signal connect_requested(from_id: int, port: int, to_id: int)
signal disconnect_requested(from_id: int, port: int)
signal connect_to_empty_requested(from_id: int, port: int, canvas_position: Vector2)
signal canvas_menu_requested(canvas_position: Vector2)
signal node_menu_requested(node_id: int)
signal delete_requested(node_ids: Array[int])
signal duplicate_requested(node_ids: Array[int])
signal nodes_moved
signal selection_changed

const NODE_WIDTH := 210
const FRAME_MARGIN := 48.0
## 打开图时不缩到看不清：低于这个比例就从入口那一侧开始看。
const READABLE_ZOOM := 0.7
const PHASE_TINT := 0.24


## 每次同步时由页面给出的显示状态。
class ViewState extends RefCounted:
	var report: GDGuideValidation.GuideValidationReport = null
	## null 表示不显示运行态着色。
	var snapshot: GDGuideRunnerSystem.GuideRunSnapshot = null
	var breakpoints: Array[int] = []
	var read_only: bool = false


var _frame_pending: bool = false
var _frame_readable: bool = false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	minimap_enabled = false
	show_grid_buttons = false
	show_arrange_button = false
	show_zoom_label = false
	snapping_enabled = true
	snapping_distance = int(GDGuideEditing.GRID_SIZE)
	right_disconnects = true
	zoom_min = 0.25
	zoom_max = 2.0
	connection_request.connect(func(from: StringName, from_port: int, to: StringName, _to_port: int) -> void:
		connect_requested.emit(int(String(from)), port_kind(from, from_port), int(String(to)))
	)
	disconnection_request.connect(func(from: StringName, from_port: int, _to: StringName, _to_port: int) -> void:
		disconnect_requested.emit(int(String(from)), port_kind(from, from_port))
	)
	connection_to_empty.connect(func(from: StringName, from_port: int, _at: Vector2) -> void:
		connect_to_empty_requested.emit(int(String(from)), port_kind(from, from_port), mouse_canvas_position())
	)
	popup_request.connect(func(_at: Vector2) -> void: canvas_menu_requested.emit(mouse_canvas_position()))
	delete_nodes_request.connect(func(names: Array) -> void:
		var ids: Array[int] = []
		for node_name in names:
			ids.append(int(String(node_name)))
		delete_requested.emit(ids)
	)
	duplicate_nodes_request.connect(func() -> void: duplicate_requested.emit(selected_ids()))
	end_node_move.connect(nodes_moved.emit)
	node_selected.connect(func(_n: Node) -> void: selection_changed.emit())
	node_deselected.connect(func(_n: Node) -> void: selection_changed.emit())
	resized.connect(func() -> void:
		if _frame_pending:
			frame_all(_frame_readable)
	)


# ── 同步 ──

func sync(graph: GDGuideGraphRes, state: ViewState) -> void:
	var wanted := {}
	if graph != null:
		for atom in graph.atoms:
			if atom != null:
				wanted[str(atom.id)] = atom
	for node in graph_nodes():
		if not wanted.has(String(node.name)):
			_remove_node(node)
	for key: String in wanted:
		var node := get_node_or_null(key) as GraphNode
		if node == null:
			node = _make_node(wanted[key])
		_update_node(node, wanted[key], state)
	_sync_edges(graph)


func graph_nodes() -> Array[GraphNode]:
	var nodes: Array[GraphNode] = []
	for child in get_children():
		if child is GraphNode and not child.is_queued_for_deletion():
			nodes.append(child)
	return nodes


func graph_node(node_id: int) -> GraphNode:
	return get_node_or_null(str(node_id)) as GraphNode


## 输出口序号 -> 端口种类（GraphEdit 只认序号）。
func port_kind(node_name: StringName, port_index: int) -> int:
	var node := get_node_or_null(String(node_name)) as GraphNode
	var outs: Array = node.get_meta("outs", []) if node != null else []
	return int(outs[port_index]) if port_index >= 0 and port_index < outs.size() else -1


func _make_node(atom: GDGuideAtoms.GuideAtom) -> GraphNode:
	var node := GraphNode.new()
	node.name = str(atom.id)
	node.custom_minimum_size.x = NODE_WIDTH
	var bar := node.get_titlebar_hbox()
	for badge_name in ["Breakpoint", "Issue"]:
		var badge := Label.new()
		badge.name = badge_name
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		bar.add_child(badge)
	var dot := bar.get_node("Breakpoint") as Label
	dot.text = "●"
	dot.tooltip_text = "断点"
	dot.add_theme_color_override("font_color", GDEditorUi.tone(&"danger"))
	bar.move_child(dot, 0)
	node.gui_input.connect(_on_node_input.bind(node))
	add_child(node)
	node.position_offset = atom.editor_position
	return node


func _remove_node(node: GraphNode) -> void:
	for c in get_connection_list():
		if c["from_node"] == node.name or c["to_node"] == node.name:
			disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])
	remove_child(node)
	node.queue_free()


func _update_node(node: GraphNode, atom: GDGuideAtoms.GuideAtom, state: ViewState) -> void:
	node.title = atom.title
	node.draggable = not state.read_only
	if not node.position_offset.is_equal_approx(atom.editor_position):
		node.position_offset = atom.editor_position
	_ensure_rows(node, atom)
	var summary := node.get_child(0) as Label
	summary.text = body_text(atom)
	var bar := node.get_titlebar_hbox()
	(bar.get_node("Breakpoint") as Label).visible = state.breakpoints.has(atom.id)
	var severity := state.report.worst_for(atom.id) if state.report != null else -1
	var issue := bar.get_node("Issue") as Label
	issue.visible = severity >= 0
	issue.text = "✕" if severity == GDGuideValidation.GuideValidationIssue.Severity.ERROR else "!"
	issue.add_theme_color_override("font_color", _severity_color(severity))
	var lines := PackedStringArray(["#%d · %s" % [atom.id, atom.get_atom_display_name()]])
	if state.report != null:
		for found in state.report.for_node(atom.id):
			lines.append(found.message)
	node.tooltip_text = "\n".join(lines)
	issue.tooltip_text = node.tooltip_text
	var phase := state.snapshot.phase_of(atom.id) if state.snapshot != null else GDGuideData.GuideNodePhase.IDLE
	node.set_meta("phase", phase)
	_apply_style(node, atom, severity, phase)


## 第 0 行：摘要（带输入口）；之后每行一个输出口，标签靠右。端口不变就不重建行。
func _ensure_rows(node: GraphNode, atom: GDGuideAtoms.GuideAtom) -> void:
	var outs: Array[int] = []
	for p in atom.get_ports():
		if not p.is_input:
			outs.append(p.kind)
	var has_in := atom.has_port(GDGuideData.GuidePortKind.EXEC_IN)
	var signature := "%s|%s" % [has_in, outs]
	if node.get_meta("ports", "") == signature:
		return
	node.set_meta("ports", signature)
	node.set_meta("outs", outs)
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
	node.clear_all_slots()
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.max_lines_visible = 2
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.custom_minimum_size.x = 1
	summary.add_theme_color_override("font_color", GDEditorUi.tone(&"muted"))
	node.add_child(summary)
	node.set_slot(0, has_in, 0, GDEditorUi.tone(&"muted"), false, 0, Color.WHITE)
	for i in range(outs.size()):
		var label := Label.new()
		label.text = GDGuideData.GuidePorts.label(outs[i])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.add_theme_color_override("font_color", port_color(outs[i]))
		node.add_child(label)
		node.set_slot(i + 1, false, 0, Color.WHITE, true, 0, port_color(outs[i]))


func _sync_edges(graph: GDGuideGraphRes) -> void:
	var wanted := {}
	if graph != null:
		for e in graph.edges:
			var from_node := graph_node(e.from_id)
			var to_node := graph_node(e.to_id)
			if from_node == null or to_node == null:
				continue
			var index := (from_node.get_meta("outs", []) as Array).find(e.port)
			if index >= 0 and graph.find_atom(e.to_id).has_port(GDGuideData.GuidePortKind.EXEC_IN):
				wanted["%s|%d|%s" % [from_node.name, index, to_node.name]] = [from_node.name, index, to_node.name]
	for c in get_connection_list():
		var key := "%s|%d|%s" % [c["from_node"], c["from_port"], c["to_node"]]
		if wanted.has(key):
			wanted.erase(key)
		else:
			disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])
	for key: String in wanted:
		var c: Array = wanted[key]
		connect_node(c[0], c[1], c[2], 0)


## 连线脉冲：试跑走过的边亮一下，由页面逐帧衰减。
func pulse_edge(from_id: int, port: int, to_id: int, amount: float) -> void:
	var from_node := graph_node(from_id)
	if from_node == null or graph_node(to_id) == null:
		return
	var index := (from_node.get_meta("outs", []) as Array).find(port)
	if index >= 0:
		set_connection_activity(from_node.name, index, StringName(str(to_id)), 0, amount)


# ── 外观 ──

static func body_text(atom: GDGuideAtoms.GuideAtom) -> String:
	var summary := atom.summary.replace("\n", " · ")
	if atom.display_name.is_empty():
		return summary if not summary.is_empty() else atom.get_atom_category()
	return atom.get_atom_display_name() + ("" if summary.is_empty() else " · " + summary)


static func category_color(atom: GDGuideAtoms.GuideAtom) -> Color:
	if atom is GDGuideAtoms.EntryAtom:
		return GDEditorUi.tone(&"ok")
	if atom is GDGuideAtoms.ExitAtom or atom is GDGuideAtoms.GuideTutorialCompleteAtom or atom is GDGuideAtoms.MissingAtom:
		return GDEditorUi.tone(&"danger")
	match atom.get_atom_category():
		GDGuideAtoms.CATEGORY_GUIDE:
			return _hue(0.76)
		GDGuideAtoms.CATEGORY_WAIT:
			return _hue(0.11)
	return _hue(0.58)


static func port_color(kind: int) -> Color:
	match kind:
		GDGuideData.GuidePortKind.EXEC_TRUE:
			return GDEditorUi.tone(&"ok")
		GDGuideData.GuidePortKind.EXEC_FALSE:
			return GDEditorUi.tone(&"danger")
		GDGuideData.GuidePortKind.EXEC_TIMEOUT:
			return GDEditorUi.tone(&"warn")
	return GDEditorUi.tone(&"accent")


static func phase_color(phase: int) -> Color:
	match phase:
		GDGuideData.GuideNodePhase.ENTERING, GDGuideData.GuideNodePhase.RUNNING, GDGuideData.GuideNodePhase.WAITING:
			return GDEditorUi.tone(&"accent")
		GDGuideData.GuideNodePhase.SUCCEEDED:
			return GDEditorUi.tone(&"ok")
		GDGuideData.GuideNodePhase.FAILED:
			return GDEditorUi.tone(&"danger")
		GDGuideData.GuideNodePhase.SKIPPED, GDGuideData.GuideNodePhase.PAUSED:
			return GDEditorUi.tone(&"warn")
	return Color(0, 0, 0, 0)


static func _hue(h: float) -> Color:
	return Color.from_hsv(h, 0.6, 0.85 if GDEditorUi.is_dark_theme() else 0.62)


static func _severity_color(severity: int) -> Color:
	if severity == GDGuideValidation.GuideValidationIssue.Severity.ERROR:
		return GDEditorUi.tone(&"danger")
	return GDEditorUi.tone(&"warn") if severity >= 0 else GDEditorUi.tone(&"border")


## 标题栏按类别着色；正文按运行阶段着色；描边表示校验问题，选中时换成强调色。
func _apply_style(node: GraphNode, atom: GDGuideAtoms.GuideAtom, severity: int, phase: int) -> void:
	var surface := GDEditorUi.tone(&"raised")
	var title_bg := surface.lerp(category_color(atom), 0.5 if GDEditorUi.is_dark_theme() else 0.32)
	var body_bg := surface
	if phase != GDGuideData.GuideNodePhase.IDLE:
		body_bg = surface.lerp(phase_color(phase), PHASE_TINT)
	var border := _severity_color(severity)
	var width := 2 if severity >= 0 or phase != GDGuideData.GuideNodePhase.IDLE else 1
	if phase != GDGuideData.GuideNodePhase.IDLE and severity < 0:
		border = phase_color(phase)
	var accent := GDEditorUi.tone(&"accent")
	node.add_theme_stylebox_override("titlebar", _box(title_bg, border, width, true))
	node.add_theme_stylebox_override("titlebar_selected", _box(title_bg, accent, 2, true))
	node.add_theme_stylebox_override("panel", _box(body_bg, border, width, false))
	node.add_theme_stylebox_override("panel_selected", _box(body_bg, accent, 2, false))


static func _box(bg: Color, border: Color, width: int, top: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = width
	box.border_width_right = width
	box.border_width_top = width if top else 0
	box.border_width_bottom = 0 if top else width
	var radius := 6
	box.corner_radius_top_left = radius if top else 0
	box.corner_radius_top_right = radius if top else 0
	box.corner_radius_bottom_left = 0 if top else radius
	box.corner_radius_bottom_right = 0 if top else radius
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 5 if top else 6
	box.content_margin_bottom = 5 if top else 8
	return box


# ── 选择与视图 ──

func selected_ids() -> Array[int]:
	var ids: Array[int] = []
	for node in graph_nodes():
		if node.selected:
			ids.append(int(String(node.name)))
	return ids


func select_ids(ids: Array) -> void:
	for node in graph_nodes():
		node.selected = ids.has(int(String(node.name)))


func center_on(node_id: int) -> void:
	var node := graph_node(node_id)
	if node != null:
		scroll_offset = (node.position_offset + _size_of(node) * 0.5) * zoom - size * 0.5


## 让全部节点进入视野：按节点包围盒设缩放和滚动。尺寸还没算出来时等第一次布局。
## readable：整张图太大时保持可读的缩放，左对齐（入口一般在最左边）。
func frame_all(readable: bool = false) -> void:
	var nodes := graph_nodes()
	if nodes.is_empty():
		return
	if size.x < 8.0 or size.y < 8.0:
		_frame_pending = true
		_frame_readable = readable
		return
	_frame_pending = false
	var bounds := Rect2(nodes[0].position_offset, _size_of(nodes[0]))
	for node in nodes:
		bounds = bounds.merge(Rect2(node.position_offset, _size_of(node)))
	bounds = bounds.grow(FRAME_MARGIN)
	zoom = clampf(minf(size.x / bounds.size.x, size.y / bounds.size.y), zoom_min, 1.0)
	var target := bounds.get_center() * zoom - size * 0.5
	if readable and zoom < READABLE_ZOOM:
		zoom = READABLE_ZOOM
		target = Vector2(bounds.position.x * zoom, bounds.get_center().y * zoom - size.y * 0.5)
	scroll_offset = target
	## 新加的节点要等下一帧才算进滚动范围，所以再设一次。
	set_deferred(&"scroll_offset", target)


func mouse_canvas_position() -> Vector2:
	return to_canvas(get_local_mouse_position())


func to_canvas(local: Vector2) -> Vector2:
	return (local + scroll_offset) / zoom


func view_center_canvas() -> Vector2:
	return to_canvas(size * 0.5)


## 给自动整理用的真实节点尺寸。
func node_sizes() -> Dictionary:
	var sizes := {}
	for node in graph_nodes():
		sizes[int(String(node.name))] = _size_of(node)
	return sizes


static func _size_of(node: GraphNode) -> Vector2:
	return node.size.max(node.get_combined_minimum_size())


func _on_node_input(event: InputEvent, node: GraphNode) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	if not node.selected:
		set_selected(node)
	node.accept_event()
	node_menu_requested.emit(int(String(node.name)))
