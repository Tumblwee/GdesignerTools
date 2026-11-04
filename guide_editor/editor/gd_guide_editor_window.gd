@tool
class_name GDGuideEditorWindow
extends VBoxContainer

## 新手引导编辑器主界面（对应 GuideEditorWindow + GuideGraphView + GuideAtomInspector + GuidePlaymodeHighlighter + GuideClickCapture）
## 四区布局：
##   顶部：工具栏（保存、校验、全部显示、整理蓝图、小地图开关、捕获点击引导、校验徽标、触发引导）+ 缺失节点横幅 + 运行时调试控制条（暂停 / 继续 / 单步 / 跳过此步 / 结束且不记完成 + 模拟点击 / 发送信号）
##   左栏：引导库浏览（+ 新建 / 示例图 / 条件示例图）
##   中栏：蓝图可视化节点画布（节点卡片、端口连线、连线脉冲、运行阶段着色、双击端口沿线跳转、右键断点/从此节点重跑/强弱引导互转/新建节点/删除节点）
##   右栏：Inspector（图头模式 / 节点模式 [含強弱互转、条件列表编辑器、端口状态] / 连线模式 [断开连线] + 运行时黑板与阶段信息）
##   底栏：校验问题列表 / 运行轨迹日志（点击任意行自动定位并高亮对应节点）

var _graph: GDGuideGraphAndValidator.GuideGraphRes = null
var _library: GDGuideGraphAndValidator.GuideLibraryRes = null
var _show_trace: bool = false

var _selected_node_id: int = 0
var _selected_edge_from_id: int = 0
var _selected_edge_port: int = 0

var _report: GDGuideGraphAndValidator.GuideValidationReport = null
var _host: GDGuideHostAndConditions.GuideHost = GDGuideHostAndConditions.GuideHost.new()
var _runner: GDGuideRunnerSystem.GuideRunner = null
var _trace_events: Array[GDGuideRunnerSystem.GuideTraceEvent] = []
var _pulsed_edge_key: String = ""

# 捕获点击录制状态
var _capturing_clicks: bool = false
var _capture_tail_id: int = 0
var _capture_count: int = 0

# 画布平移缩放与拖拽状态
var _canvas_pan: Vector2 = Vector2(40.0, 60.0)
var _canvas_zoom: float = 1.0
var _dragging_node_id: int = 0
var _panning_canvas: bool = false
var _connecting_from_id: int = 0
var _connecting_from_port: int = GDGuideData.GuidePortKind.EXEC_OUT
var _connect_mouse: Vector2 = Vector2.ZERO
var _minimap_visible: bool = true

# UI 引用
var _graph_title_label: Label = null
var _validation_badge: Label = null
var _banner_panel: PanelContainer = null
var _banner_label: Label = null
var _play_bar: HBoxContainer = null
var _play_status_label: Label = null
var _capture_btn: Button = null
var _stop_capture_btn: Button = null
var _graph_list_box: VBoxContainer = null
var _canvas_control: Control = null
var _inspector_box: VBoxContainer = null
var _log_list_box: VBoxContainer = null
var _issues_tab_btn: Button = null
var _trace_tab_btn: Button = null
var _signal_input_edit: LineEdit = null
var _canvas_status: Label = null
var _graph_query: String = ""

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_runner = GDGuideRunnerSystem.GuideRunner.new(_host)
	_runner.traced.connect(func(evt: GDGuideRunnerSystem.GuideTraceEvent) -> void:
		_trace_events.append(evt)
		if evt.kind == GDGuideData.GuideTraceKind.EDGE:
			_pulsed_edge_key = "%d::%d" % [evt.node_id, evt.port]
		_refresh_play_bar()
		_refresh_log_pane()
		if _canvas_control != null:
			_canvas_control.queue_redraw()
	)
	_build_ui()
	_ensure_sample_graphs()
	refresh_graph_list()

func load_graph(graph: GDGuideGraphAndValidator.GuideGraphRes) -> void:
	if _graph != graph:
		_stop_click_capture()
	GDGuideGraphAndValidator.GuideSchemaMigrator.migrate(graph)
	_graph = graph
	_selected_node_id = 0
	_selected_edge_from_id = 0
	if _graph != null and not _runner.is_running:
		if _graph.atoms.is_empty():
			_graph.add_default_skeleton()
	validate_current_graph()
	frame_all()
	refresh_all()
	refresh_graph_list()

func get_current_graph() -> GDGuideGraphAndValidator.GuideGraphRes:
	return _graph

func get_runner() -> GDGuideRunnerSystem.GuideRunner:
	return _runner

func get_report() -> GDGuideGraphAndValidator.GuideValidationReport:
	return _report

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	# ── 1. 顶部工具栏：图本身 ──
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	add_child(toolbar)

	_graph_title_label = Label.new()
	_graph_title_label.text = "未打开引导图"
	GDEditorUi.style_context_label(_graph_title_label)
	toolbar.add_child(_graph_title_label)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.tooltip_text = "把当前引导图写回资源"
	save_btn.pressed.connect(_save_graph)
	GDEditorUi.style_button(save_btn, "primary")
	toolbar.add_child(save_btn)

	var val_btn := Button.new()
	val_btn.text = "校验"
	val_btn.tooltip_text = "检查断线、缺失节点和必填项"
	val_btn.pressed.connect(func() -> void:
		validate_current_graph()
		_show_trace = false
		refresh_all()
	)
	GDEditorUi.style_button(val_btn, "quiet")
	toolbar.add_child(val_btn)

	var frame_btn := Button.new()
	frame_btn.text = "适配"
	frame_btn.tooltip_text = "把画布缩放到能看见整张图"
	frame_btn.pressed.connect(frame_all)
	GDEditorUi.style_button(frame_btn, "quiet")
	toolbar.add_child(frame_btn)

	var arrange_btn := Button.new()
	arrange_btn.text = "整理"
	arrange_btn.tooltip_text = "按连线重新排一下节点"
	arrange_btn.pressed.connect(func() -> void:
		if _graph != null and not _runner.is_running:
			GDGuideEditingAndCli.GuideGraphEditing.arrange(_graph)
			frame_all()
			refresh_all()
	)
	GDEditorUi.style_button(arrange_btn, "quiet")
	toolbar.add_child(arrange_btn)

	var minimap_cb := CheckBox.new()
	minimap_cb.text = "小地图"
	minimap_cb.button_pressed = _minimap_visible
	minimap_cb.toggled.connect(func(on: bool) -> void:
		_minimap_visible = on
		if _canvas_control != null:
			_canvas_control.queue_redraw()
	)
	toolbar.add_child(minimap_cb)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_validation_badge = Label.new()
	toolbar.add_child(_validation_badge)

	var trigger_btn := Button.new()
	trigger_btn.text = "▶ 试跑"
	trigger_btn.tooltip_text = "从入口跑一遍当前引导，下面会记下轨迹"
	trigger_btn.pressed.connect(_trigger_selected_graph)
	GDEditorUi.style_button(trigger_btn, "primary")
	toolbar.add_child(trigger_btn)
	GDEditorUi.wrap_toolbar(toolbar)

	# ── 2. 缺失节点横幅 ──
	_banner_panel = PanelContainer.new()
	_banner_panel.visible = false
	var banner_row := HBoxContainer.new()
	_banner_label = Label.new()
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	banner_row.add_child(_banner_label)
	var clr_missing_btn := Button.new()
	clr_missing_btn.text = "清理缺失节点…"
	clr_missing_btn.pressed.connect(func() -> void:
		if _graph != null and not _runner.is_running:
			_graph.remove_missing_atom_slots()
			validate_current_graph()
			refresh_all()
	)
	banner_row.add_child(clr_missing_btn)
	_banner_panel.add_child(banner_row)
	add_child(_banner_panel)

	# ── 3. 运行时调试控制条（Play Bar） ──
	_play_bar = HBoxContainer.new()
	_play_bar.add_theme_constant_override("separation", 4)
	add_child(_play_bar)

	_play_status_label = Label.new()
	_play_status_label.text = "调试待命"
	_play_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GDEditorUi.style_context_label(_play_status_label)
	_play_bar.add_child(_play_status_label)

	_capture_btn = GDEditorUi.icon_button("录", "从选中节点往后录一段点击引导", "quiet")
	_capture_btn.pressed.connect(_start_click_capture)
	_play_bar.add_child(_capture_btn)

	_stop_capture_btn = GDEditorUi.icon_button("停", "停止录制", "danger")
	_stop_capture_btn.visible = false
	_stop_capture_btn.pressed.connect(_stop_click_capture)
	_play_bar.add_child(_stop_capture_btn)

	var pause_btn := GDEditorUi.icon_button("Ⅱ", "暂停")
	pause_btn.pressed.connect(func() -> void:
		_runner.enqueue_debug_command(GDGuideData.GuideDebugCommandKind.PAUSE)
		refresh_all()
	)
	_play_bar.add_child(pause_btn)

	var cont_btn := GDEditorUi.icon_button("▶", "继续", "primary")
	cont_btn.pressed.connect(func() -> void:
		_runner.enqueue_debug_command(GDGuideData.GuideDebugCommandKind.CONTINUE)
		refresh_all()
	)
	_play_bar.add_child(cont_btn)

	var step_btn := GDEditorUi.icon_button("↳", "单步")
	step_btn.pressed.connect(func() -> void:
		_runner.enqueue_debug_command(GDGuideData.GuideDebugCommandKind.STEP_ONCE)
		refresh_all()
	)
	_play_bar.add_child(step_btn)

	var skip_node_btn := GDEditorUi.icon_button("⇥", "跳过此步")
	skip_node_btn.pressed.connect(func() -> void:
		_runner.enqueue_debug_command(GDGuideData.GuideDebugCommandKind.SKIP_NODE)
		refresh_all()
	)
	_play_bar.add_child(skip_node_btn)

	var abort_btn := GDEditorUi.icon_button("■", "结束且不记完成", "danger")
	abort_btn.pressed.connect(func() -> void:
		_runner.enqueue_debug_command(GDGuideData.GuideDebugCommandKind.STOP, 0, GDGuideData.GuideExitReason.ABORTED)
		refresh_all()
	)
	_play_bar.add_child(abort_btn)

	_signal_input_edit = LineEdit.new()
	_signal_input_edit.placeholder_text = "信号"
	_signal_input_edit.tooltip_text = "例如 SamplePanelReady"
	_signal_input_edit.custom_minimum_size.x = 120
	_play_bar.add_child(_signal_input_edit)

	var send_sig_btn := GDEditorUi.icon_button("⇢", "发送信号，走过等待信号的节点", "quiet")
	send_sig_btn.pressed.connect(func() -> void:
		var sig := _signal_input_edit.text.strip_edges()
		if not sig.is_empty():
			var sp := GDGuideData.GuideSignalKeys.split(sig)
			_host.signals.publish(str(sp["key"]), str(sp["arg"]))
			_runner.tick(0.1)
			refresh_all()
	)
	_play_bar.add_child(send_sig_btn)

	var more_btn := MenuButton.new()
	more_btn.text = "⋯"
	more_btn.tooltip_text = "模拟点击、推进时间"
	GDEditorUi.style_button(more_btn, "quiet")
	var more_popup := more_btn.get_popup()
	more_popup.add_item("模拟点击", 1)
	more_popup.add_item("推进 0.5 秒", 2)
	more_popup.id_pressed.connect(func(id: int) -> void:
		if id == 1:
			_host.simulate_click()
			_runner.tick(0.1)
		elif id == 2:
			_runner.tick(0.5)
		refresh_all()
	)
	_play_bar.add_child(more_btn)
	GDEditorUi.wrap_toolbar(_play_bar)

	# ── 4. 上下分割（上：三栏；下：校验/运行轨迹） ──
	var v_split := VSplitContainer.new()
	v_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v_split.split_offset = 420
	v_split.resized.connect(func() -> void:
		GDEditorUi.ensure_split_usable(v_split, 220, 120)
	)
	add_child(v_split)

	var top_split := HSplitContainer.new()
	top_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_split.split_offset = 210
	v_split.add_child(top_split)

	# 左栏：引导库
	var left_panel := PanelContainer.new()
	left_panel.clip_contents = true
	left_panel.custom_minimum_size.x = 200
	GDEditorUi.apply_panel(left_panel, 10)
	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)
	top_split.add_child(left_panel)

	left_vbox.add_child(GDEditorUi.section_title("引导图"))
	var graph_search := GDEditorUi.search_field("搜索引导名称或 ID")
	graph_search.text_changed.connect(func(t: String) -> void:
		_graph_query = t
		refresh_graph_list()
	)
	left_vbox.add_child(graph_search)

	var lib_scroll := ScrollContainer.new()
	lib_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(lib_scroll)

	_graph_list_box = VBoxContainer.new()
	_graph_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_list_box.add_theme_constant_override("separation", 3)
	lib_scroll.add_child(_graph_list_box)
	GDEditorUi.configure_vertical_scroll(lib_scroll, _graph_list_box)

	var left_btns := HBoxContainer.new()
	var new_g_btn := Button.new()
	new_g_btn.text = "+ 新建"
	new_g_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_g_btn.pressed.connect(_create_new_graph)
	GDEditorUi.style_button(new_g_btn, "primary")
	left_btns.add_child(new_g_btn)

	var sample_btn := Button.new()
	sample_btn.text = "示例图"
	sample_btn.tooltip_text = "打开一份带分支的示例引导"
	sample_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sample_btn.pressed.connect(_open_sample_graph)
	GDEditorUi.style_button(sample_btn, "quiet")
	left_btns.add_child(sample_btn)
	left_vbox.add_child(left_btns)

	# 中右分割
	var center_right_split := HSplitContainer.new()
	center_right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_right_split.split_offset = 540
	top_split.add_child(center_right_split)

	# 中栏：蓝图画布 + 顶部快捷新建节点菜单
	var center_panel := PanelContainer.new()
	GDEditorUi.apply_panel(center_panel, 8)
	var center_vbox := VBoxContainer.new()
	center_vbox.add_theme_constant_override("separation", 6)
	center_panel.add_child(center_vbox)
	center_right_split.add_child(center_panel)

	var canvas_bar := HBoxContainer.new()
	canvas_bar.add_theme_constant_override("separation", 6)
	var add_node_menu := MenuButton.new()
	add_node_menu.text = "+ 新建节点"
	var np := add_node_menu.get_popup()
	var descriptors := GDGuideAtoms.get_all_atom_descriptors()
	for i in range(descriptors.size()):
		var d := descriptors[i]
		np.add_item("[%s] %s (%s)" % [d["category"], d["display"], d["id"]], i)
	np.id_pressed.connect(func(idx: int) -> void:
		if _graph == null or _runner.is_running:
			return
		var desc := descriptors[idx]
		var pos := Vector2(160.0 + float(_graph.atoms.size()) * 180.0, 80.0)
		var auto_from := _selected_node_id if _selected_node_id > 0 else 0
		var created := GDGuideEditingAndCli.GuideGraphEditing.add_node(
			_graph, str(desc["id"]), pos, auto_from, GDGuideData.GuidePortKind.EXEC_OUT, 0
		)
		if created != null:
			_selected_node_id = created.id
			validate_current_graph()
			refresh_all()
	)
	GDEditorUi.style_button(add_node_menu, "primary")
	canvas_bar.add_child(add_node_menu)

	var del_sel_btn := Button.new()
	del_sel_btn.text = "删除选中"
	del_sel_btn.tooltip_text = "删除当前节点。也可以按 Delete。"
	del_sel_btn.pressed.connect(_delete_selected_in_canvas)
	GDEditorUi.style_button(del_sel_btn, "danger")
	canvas_bar.add_child(del_sel_btn)

	var bp_btn := Button.new()
	bp_btn.text = "断点"
	bp_btn.tooltip_text = "在选中节点上切换断点。试跑到这里会暂停。"
	GDEditorUi.style_button(bp_btn, "quiet")
	bp_btn.pressed.connect(func() -> void:
		if _graph != null and _selected_node_id > 0:
			GDGuideRunnerSystem.GuideBreakpoints.toggle(_graph, _selected_node_id)
			refresh_all()
	)
	canvas_bar.add_child(bp_btn)
	center_vbox.add_child(canvas_bar)
	_canvas_status = GDEditorUi.muted("拖节点 · 圆点连线 · 滚轮缩放 · 中键平移 · Delete 删除")
	center_vbox.add_child(_canvas_status)

	_canvas_control = Control.new()
	_canvas_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas_control.custom_minimum_size = Vector2(360, 260)
	_canvas_control.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas_control.clip_contents = true
	_canvas_control.gui_input.connect(_on_canvas_gui_input)
	_canvas_control.draw.connect(_on_canvas_draw)
	center_vbox.add_child(_canvas_control)

	# 右栏：Inspector
	var right_panel := PanelContainer.new()
	right_panel.clip_contents = true
	right_panel.custom_minimum_size.x = 260
	GDEditorUi.apply_panel(right_panel, 10)
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(right_vbox)
	center_right_split.add_child(right_panel)
	right_vbox.add_child(GDEditorUi.section_title("属性"))

	var insp_scroll := ScrollContainer.new()
	insp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(insp_scroll)

	_inspector_box = VBoxContainer.new()
	_inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_box.add_theme_constant_override("separation", 6)
	insp_scroll.add_child(_inspector_box)
	GDEditorUi.configure_vertical_scroll(insp_scroll, _inspector_box)

	# 底栏：校验 / 运行轨迹
	var bottom_panel := PanelContainer.new()
	GDEditorUi.apply_panel(bottom_panel, 8)
	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.add_theme_constant_override("separation", 6)
	bottom_panel.add_child(bottom_vbox)
	v_split.add_child(bottom_panel)

	var b_tabs := HBoxContainer.new()
	_issues_tab_btn = Button.new()
	_issues_tab_btn.text = "校验"
	_issues_tab_btn.pressed.connect(func() -> void:
		_show_trace = false
		_refresh_log_pane()
	)
	b_tabs.add_child(_issues_tab_btn)

	_trace_tab_btn = Button.new()
	_trace_tab_btn.text = "运行轨迹"
	_trace_tab_btn.pressed.connect(func() -> void:
		_show_trace = true
		_refresh_log_pane()
	)
	b_tabs.add_child(_trace_tab_btn)

	var b_sp := Control.new()
	b_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_tabs.add_child(b_sp)

	var clr_trace_btn := Button.new()
	clr_trace_btn.text = "清空轨迹"
	clr_trace_btn.pressed.connect(func() -> void:
		_trace_events.clear()
		_refresh_log_pane()
	)
	b_tabs.add_child(clr_trace_btn)
	bottom_vbox.add_child(b_tabs)

	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_vbox.add_child(log_scroll)

	_log_list_box = VBoxContainer.new()
	_log_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_list_box.add_theme_constant_override("separation", 2)
	log_scroll.add_child(_log_list_box)
	GDEditorUi.configure_vertical_scroll(log_scroll, _log_list_box)

# ─────────────────────── 画布绘制与交互（Node / Port / Edge / Minimap） ───────────────────────

const NODE_WIDTH := 220.0
const NODE_HEIGHT := 92.0

func frame_all() -> void:
	_canvas_pan = Vector2(40.0, 50.0)
	_canvas_zoom = 1.0
	if _canvas_control != null:
		_canvas_control.queue_redraw()

func frame_node(node_id: int) -> void:
	if _graph == null:
		return
	var a := _graph.find_atom(node_id)
	if a == null:
		return
	_selected_node_id = node_id
	_selected_edge_from_id = 0
	if _canvas_control != null:
		_canvas_pan = _canvas_control.size * 0.5 - a.editor_position * _canvas_zoom - Vector2(NODE_WIDTH * 0.5, NODE_HEIGHT * 0.5)
	refresh_all()

func _node_screen_rect(atom: GDGuideAtoms.GuideAtom) -> Rect2:
	var pos := _canvas_pan + atom.editor_position * _canvas_zoom
	var sz := Vector2(NODE_WIDTH, NODE_HEIGHT) * _canvas_zoom
	return Rect2(pos, sz)

func _output_ports(atom: GDGuideAtoms.GuideAtom) -> Array:
	var result: Array = []
	if atom == null:
		return result
	for p in atom.get_ports():
		if p != null and not p.is_input:
			result.append(p)
	return result


func _port_center(atom: GDGuideAtoms.GuideAtom, kind: int) -> Vector2:
	var nr := _node_screen_rect(atom)
	if kind == GDGuideData.GuidePortKind.EXEC_IN:
		return Vector2(nr.position.x, nr.position.y + nr.size.y * 0.55)
	var outs := _output_ports(atom)
	var idx := 0
	for i in range(outs.size()):
		if int(outs[i].kind) == kind:
			idx = i
			break
	var n := maxi(1, outs.size())
	var y := nr.position.y + nr.size.y * (float(idx) + 1.0) / float(n + 1)
	return Vector2(nr.end.x, y)


func _hit_output_port(local_pos: Vector2) -> Dictionary:
	if _graph == null:
		return {}
	var best_d := 14.0
	var best: Dictionary = {}
	for atom in _graph.atoms:
		if atom == null:
			continue
		for p in _output_ports(atom):
			var d := local_pos.distance_to(_port_center(atom, int(p.kind)))
			if d < best_d:
				best_d = d
				best = {"id": atom.id, "port": int(p.kind)}
	return best


func _hit_node(local_pos: Vector2) -> int:
	if _graph == null:
		return 0
	for i in range(_graph.atoms.size() - 1, -1, -1):
		var a = _graph.atoms[i]
		if a != null and _node_screen_rect(a).has_point(local_pos):
			return int(a.id)
	return 0


func _set_canvas_status(text: String) -> void:
	if _canvas_status != null and not text.is_empty():
		_canvas_status.text = text


func _finish_connect(local_pos: Vector2) -> void:
	var from_id := _connecting_from_id
	var port := _connecting_from_port
	_connecting_from_id = 0
	if from_id <= 0 or _graph == null or _runner.is_running:
		if _canvas_control != null:
			_canvas_control.queue_redraw()
		return
	var target := _hit_node(local_pos)
	if target > 0 and target != from_id:
		var res := _graph.connect_nodes(from_id, port, target)
		if bool(res.get("ok", false)):
			_set_canvas_status("已连上「%s」。再从圆点拖一次，可以改接到别的节点。" % GDGuideData.GuidePorts.label(port))
			validate_current_graph()
		else:
			_set_canvas_status(str(res.get("reason", "这条线接不上。")))
	else:
		_set_canvas_status("松开时要落在另一个节点上。从右侧圆点拖过去。")
	refresh_all()


func _draw_curve(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	if _canvas_control == null:
		return
	var dist := maxf(28.0, absf(b.x - a.x) * 0.45)
	var c1 := a + Vector2(dist, 0.0)
	var c2 := b - Vector2(dist, 0.0)
	var prev := a
	for i in range(1, 13):
		var t := float(i) / 12.0
		var u := 1.0 - t
		var p := (a * u * u * u) + (c1 * 3.0 * u * u * t) + (c2 * 3.0 * u * t * t) + (b * t * t * t)
		_canvas_control.draw_line(prev, p, col, width)
		prev = p


func _input(event: InputEvent) -> void:
	if _connecting_from_id <= 0 or _canvas_control == null or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		_connect_mouse = _canvas_control.get_local_mouse_position()
		_canvas_control.queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_finish_connect(_canvas_control.get_local_mouse_position())


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _runner == null or _runner.is_running:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_DELETE:
		_delete_selected_in_canvas()
		get_viewport().set_input_as_handled()


func _on_canvas_gui_input(event: InputEvent) -> void:
	if _graph == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_canvas_zoom = clampf(_canvas_zoom * 1.1, 0.25, 2.0)
			_canvas_control.queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_canvas_zoom = clampf(_canvas_zoom / 1.1, 0.25, 2.0)
			_canvas_control.queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning_canvas = mb.pressed
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var port_hit := _hit_output_port(mb.position)
				if not port_hit.is_empty() and not _runner.is_running:
					_connecting_from_id = int(port_hit["id"])
					_connecting_from_port = int(port_hit["port"])
					_connect_mouse = mb.position
					_selected_node_id = _connecting_from_id
					_selected_edge_from_id = 0
					_dragging_node_id = 0
					_set_canvas_status("拖到目标节点上松开，接上「%s」。" % GDGuideData.GuidePorts.label(_connecting_from_port))
					refresh_all()
					accept_event()
					return
				var hit_id := _hit_node(mb.position)
				_selected_node_id = hit_id
				_selected_edge_from_id = 0
				if hit_id > 0 and not _runner.is_running:
					_dragging_node_id = hit_id
				else:
					_dragging_node_id = 0
				refresh_all()
			else:
				_dragging_node_id = 0
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning_canvas:
			_canvas_pan += mm.relative
			_canvas_control.queue_redraw()
			accept_event()
		elif _dragging_node_id > 0 and not _runner.is_running:
			var a := _graph.find_atom(_dragging_node_id)
			if a != null:
				a.assign_editor_position(a.editor_position + mm.relative / maxf(0.1, _canvas_zoom))
				_canvas_control.queue_redraw()
			accept_event()

func _on_canvas_draw() -> void:
	var rect := Rect2(Vector2.ZERO, _canvas_control.size)
	_canvas_control.draw_rect(rect, Color(0.13, 0.14, 0.16, 1.0))

	# 背景网格
	var grid_step := 24.0 * _canvas_zoom
	if grid_step >= 8.0:
		var grid_col := Color(0.20, 0.21, 0.24, 0.6)
		var x := fmod(_canvas_pan.x, grid_step)
		while x < rect.size.x:
			_canvas_control.draw_line(Vector2(x, 0), Vector2(x, rect.size.y), grid_col, 1.0)
			x += grid_step
		var y := fmod(_canvas_pan.y, grid_step)
		while y < rect.size.y:
			_canvas_control.draw_line(Vector2(0, y), Vector2(rect.size.x, y), grid_col, 1.0)
			y += grid_step

	if _graph == null:
		return

	var font := ThemeDB.fallback_font
	var snap := _runner.capture_snapshot() if _runner != null else null

	# 1. 绘制连线
	for edge in _graph.edges:
		if edge == null:
			continue
		var from_a := _graph.find_atom(edge.from_id)
		var to_a := _graph.find_atom(edge.to_id)
		if from_a == null or to_a == null:
			continue
		var p_start := _port_center(from_a, edge.port)
		var p_end := _port_center(to_a, GDGuideData.GuidePortKind.EXEC_IN)
		var e_key := "%d::%d" % [edge.from_id, edge.port]
		var edge_col := Color(1.0, 0.88, 0.3, 1.0) if e_key == _pulsed_edge_key else Color(0.55, 0.75, 0.95, 0.9)
		_draw_curve(p_start, p_end, edge_col, 2.6 if e_key == _pulsed_edge_key else 1.8)
		if font != null:
			var mid := (p_start + p_end) * 0.5
			_canvas_control.draw_string(font, mid + Vector2(-18, -6), GDGuideData.GuidePorts.label(edge.port), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, edge_col)

	# 2. 绘制节点
	for atom in _graph.atoms:
		if atom == null:
			continue
		var nr := _node_screen_rect(atom)
		var bg_col := Color(0.22, 0.24, 0.28, 0.96)
		if atom is GDGuideAtoms.EntryAtom:
			bg_col = Color(0.18, 0.36, 0.24, 0.96)
		elif atom is GDGuideAtoms.ExitAtom:
			bg_col = Color(0.36, 0.20, 0.22, 0.96)
		elif atom is GDGuideAtoms.MissingAtom:
			bg_col = Color(0.50, 0.16, 0.16, 0.96)

		# 运行阶段着色
		if snap != null and snap.has_run:
			var ph := snap.phase_of(atom.id)
			match ph:
				GDGuideData.GuideNodePhase.RUNNING, GDGuideData.GuideNodePhase.WAITING:
					bg_col = Color(0.22, 0.44, 0.68, 0.98)
				GDGuideData.GuideNodePhase.SUCCEEDED:
					bg_col = Color(0.20, 0.46, 0.30, 0.96)
				GDGuideData.GuideNodePhase.FAILED:
					bg_col = Color(0.58, 0.20, 0.20, 0.98)
				GDGuideData.GuideNodePhase.SKIPPED:
					bg_col = Color(0.38, 0.34, 0.22, 0.95)
				GDGuideData.GuideNodePhase.PAUSED:
					bg_col = Color(0.56, 0.42, 0.18, 0.98)

		# 边框（选中 / 校验报错 / 活跃闪烁）
		var border_col := Color(0.45, 0.48, 0.54)
		var border_w := 1
		if _report != null:
			var w_sev := _report.worst_for(atom.id)
			if w_sev == GDGuideGraphAndValidator.GuideValidationIssue.Severity.ERROR:
				border_col = Color(1.0, 0.32, 0.32)
				border_w = 2
			elif w_sev == GDGuideGraphAndValidator.GuideValidationIssue.Severity.WARNING:
				border_col = Color(1.0, 0.78, 0.28)
				border_w = 2
		if snap != null and snap.is_running and snap.active_node_id == atom.id:
			border_col = Color(0.35, 1.0, 0.55)
			border_w = 3
		elif atom.id == _selected_node_id:
			border_col = Color(0.45, 0.80, 1.0)
			border_w = 2
		GDEditorUi.paint_round_rect(_canvas_control, nr, bg_col, border_col, 8, border_w)
		var header_h := clampf(18.0 * _canvas_zoom, 12.0, nr.size.y * 0.38)
		var header_col := bg_col.lightened(0.16)
		_canvas_control.draw_rect(Rect2(nr.position + Vector2(3, 3), Vector2(maxf(4.0, nr.size.x - 6.0), header_h)), header_col)
		_canvas_control.draw_rect(Rect2(nr.position + Vector2(6, header_h + 6), Vector2(3, maxf(6.0, nr.size.y - header_h - 12.0))), border_col)

		if font != null:
			var bp_prefix := "● " if GDGuideRunnerSystem.GuideBreakpoints.contains(_graph, atom.id) else ""
			_canvas_control.draw_string(
				font,
				nr.position + Vector2(8, 18),
				"%s%s  #%d" % [bp_prefix, atom.title, atom.id],
				HORIZONTAL_ALIGNMENT_LEFT,
				nr.size.x - 58,
				12,
				Color(0.96, 0.97, 0.99)
			)
			_canvas_control.draw_string(
				font,
				nr.position + Vector2(14, 36),
				"%s · %s" % [atom.get_atom_category(), atom.get_atom_display_name()],
				HORIZONTAL_ALIGNMENT_LEFT,
				nr.size.x - 64,
				10,
				Color(0.72, 0.78, 0.86)
			)
			var sum_txt: String = atom.summary
			if not sum_txt.is_empty():
				_canvas_control.draw_string(
					font,
					nr.position + Vector2(14, 56),
					sum_txt.replace("\n", " "),
					HORIZONTAL_ALIGNMENT_LEFT,
					nr.size.x - 64,
					11,
					Color(0.9, 0.92, 0.94)
				)
		for p in _output_ports(atom):
			var c := _port_center(atom, int(p.kind))
			var hot: bool = _connecting_from_id == atom.id and _connecting_from_port == int(p.kind)
			_canvas_control.draw_circle(c, 5.0, Color(0.98, 0.84, 0.4) if hot else Color(0.78, 0.9, 1.0))
			if font != null and _canvas_zoom >= 0.85:
				_canvas_control.draw_string(font, c + Vector2(-50, 4), GDGuideData.GuidePorts.label(int(p.kind)), HORIZONTAL_ALIGNMENT_RIGHT, 44, 10, Color(0.78, 0.84, 0.92))
		if atom.has_port(GDGuideData.GuidePortKind.EXEC_IN):
			_canvas_control.draw_circle(_port_center(atom, GDGuideData.GuidePortKind.EXEC_IN), 4.5, Color(0.5, 0.86, 0.62))

	if _connecting_from_id > 0:
		var from_drag := _graph.find_atom(_connecting_from_id)
		if from_drag != null:
			_draw_curve(_port_center(from_drag, _connecting_from_port), _connect_mouse, Color(0.98, 0.86, 0.42), 2.2)

	# 3. 小地图
	if _minimap_visible and not _graph.atoms.is_empty():
		var mm_rect := Rect2(Vector2(8, 8), Vector2(150, 96))
		GDEditorUi.paint_round_rect(_canvas_control, mm_rect, Color(0.07, 0.08, 0.1, 0.9), Color(0.45, 0.58, 0.78, 0.95), 6, 1)
		for a in _graph.atoms:
			if a != null:
				var dot_pos: Vector2 = mm_rect.position + Vector2(16, 20) + a.editor_position * 0.05
				dot_pos.x = clampf(dot_pos.x, mm_rect.position.x + 4, mm_rect.end.x - 12)
				dot_pos.y = clampf(dot_pos.y, mm_rect.position.y + 4, mm_rect.end.y - 8)
				_canvas_control.draw_rect(Rect2(dot_pos, Vector2(8, 5)), Color(0.45, 0.78, 1.0))

# ─────────────────────── Refresh & Inspector ───────────────────────

func validate_current_graph() -> void:
	_report = GDGuideGraphAndValidator.GuideGraphValidator.validate(_graph, [], _host.conditions) if _graph != null else null

func refresh_all() -> void:
	if _graph_title_label == null:
		return
	_graph_title_label.text = "未打开引导图" if _graph == null else ("%s  #%d" % [_graph.display_name, _graph.graph_id])

	# 校验徽标
	if _report == null:
		_validation_badge.text = ""
	elif _report.has_errors:
		_validation_badge.text = "校验：%d 错误 · %d 警告" % [_report.error_count, _report.warning_count]
		_validation_badge.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	elif _report.warning_count > 0:
		_validation_badge.text = "校验通过 · %d 警告" % _report.warning_count
		_validation_badge.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	else:
		_validation_badge.text = "✔ 校验通过"
		_validation_badge.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))

	# 缺失节点横幅
	var missing_cnt := _graph.missing_atom_count if _graph != null else 0
	_banner_panel.visible = missing_cnt > 0
	if missing_cnt > 0:
		_banner_label.text = "这张图有 %d 个节点类型缺失，整张图只读。恢复类后重新打开，或清理缺失节点。" % missing_cnt

	_refresh_play_bar()
	_rebuild_inspector()
	_refresh_log_pane()
	if _canvas_control != null:
		_canvas_control.queue_redraw()

func _refresh_play_bar() -> void:
	if _play_status_label == null or _runner == null:
		return
	var snap := _runner.capture_snapshot()
	if not snap.has_run:
		_play_status_label.text = "调试待命。点「试跑」从入口开始。"
		return
	if snap.is_running:
		var a := _graph.find_atom(snap.active_node_id) if _graph != null else null
		var t_title := a.title if a != null else ("#%d" % snap.active_node_id)
		_play_status_label.text = "%s  %s · 「%s」 · %.1fs  %s" % [
			"已暂停" if snap.is_paused else "运行中",
			snap.graph_name,
			t_title,
			snap.node_elapsed,
			snap.active_message
		]
	else:
		_play_status_label.text = "已结束：%s · %s" % [
			GDGuideAtoms.ExitAtom.exit_reason_label(snap.exit_reason),
			snap.exit_message
		]

func _rebuild_inspector() -> void:
	if _inspector_box == null:
		return
	GDEditorUi.clear_children(_inspector_box)

	if _graph == null:
		_inspector_box.add_child(GDEditorUi.empty_state("还没有引导图", [
			"在左侧点一张引导图。",
			"或点「+ 新建」从入口和结束节点开始。",
			"点画布上的节点，这里会改成那一步的属性。",
		]))
		return

	if _selected_node_id > 0:
		var atom := _graph.find_atom(_selected_node_id)
		if atom != null:
			_build_node_inspector(atom)
			return

	_build_graph_header_inspector()

func _build_graph_header_inspector() -> void:
	_inspector_box.add_child(GDEditorUi.section_title(_graph.display_name))
	_inspector_box.add_child(GDEditorUi.muted("现在改的是整张图。点画布上的节点，改为改那一步。"))

	_add_insp_int("图 Id", _graph.graph_id, func(v: int) -> void:
		_graph.set_graph_id(v)
		validate_current_graph()
		refresh_graph_list()
		refresh_all()
	)
	_add_insp_str("名称", _graph.raw_display_name, func(t: String) -> void:
		_graph.set_display_name(t)
		refresh_graph_list()
		refresh_all()
	)

	var en_cb := CheckBox.new()
	en_cb.text = "启用"
	en_cb.button_pressed = _graph.enabled
	en_cb.toggled.connect(func(on: bool) -> void: _graph.set_enabled(on))
	_inspector_box.add_child(en_cb)

	_add_insp_int("优先级", _graph.priority, func(v: int) -> void: _graph.set_priority(v))

	var sk_cb := CheckBox.new()
	sk_cb.text = "允许跳过"
	sk_cb.button_pressed = _graph.allow_skip
	sk_cb.toggled.connect(func(on: bool) -> void: _graph.set_allow_skip(on))
	_inspector_box.add_child(sk_cb)

	var res_cb := CheckBox.new()
	res_cb.text = "恢复时从入口分支判断"
	res_cb.button_pressed = _graph.resume_from_entry
	res_cb.toggled.connect(func(on: bool) -> void: _graph.set_resume_from_entry(on))
	_inspector_box.add_child(res_cb)

	var stats := Label.new()
	stats.text = "节点 %d · 连线 %d · 下一个节点 id %d · 数据版本 v%d" % [
		_graph.atoms.size() - _graph.missing_atom_count,
		_graph.edges.size(),
		_graph.next_node_id,
		_graph.schema_version
	]
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector_box.add_child(stats)

func _build_node_inspector(atom: GDGuideAtoms.GuideAtom) -> void:
	_inspector_box.add_child(GDEditorUi.section_title("%s  #%d" % [atom.get_atom_display_name(), atom.id]))
	_inspector_box.add_child(GDEditorUi.muted(atom.get_atom_id()))

	# 强弱引导互转按钮
	if atom is GDGuideAtoms.GuideTargetAtom:
		var t_atom := atom as GDGuideAtoms.GuideTargetAtom
		if not t_atom.alternate_type_id.is_empty():
			var conv_btn := Button.new()
			conv_btn.text = "转换为%s" % ("弱引导" if t_atom is GDGuideAtoms.StrongGuideAtom else "强引导")
			conv_btn.disabled = _runner.is_running
			conv_btn.pressed.connect(func() -> void:
				GDGuideEditingAndCli.GuideGraphEditing.convert_guide(_graph, atom.id)
				validate_current_graph()
				refresh_all()
			)
			_inspector_box.add_child(conv_btn)

	_add_insp_str("节点名", atom.display_name, func(t: String) -> void:
		atom.set_display_name(t)
		validate_current_graph()
		refresh_all()
	)

	# 连线编辑器：为每个输出口提供目标节点下拉选择
	_inspector_box.add_child(GDEditorUi.section_title("连到哪一步"))
	_inspector_box.add_child(GDEditorUi.muted("也可以直接从画布右侧的圆点拖到目标节点。"))

	for p in atom.get_ports():
		if p.is_input:
			continue
		var p_row := HBoxContainer.new()
		var pl := Label.new()
		pl.text = GDGuideData.GuidePorts.label(p.kind) + ("*" if p.required else "")
		pl.custom_minimum_size.x = 76
		p_row.add_child(pl)

		var target_opt := OptionButton.new()
		target_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target_opt.add_item("（未连）", 0)
		var cur_edge_res := _graph.try_get_edge(atom.id, p.kind)
		var cur_to_id := (cur_edge_res["edge"] as GDGuideData.GuideEdge).to_id if bool(cur_edge_res.get("ok", false)) else 0
		var sel_idx := 0
		for other in _graph.atoms:
			if other != null and other.id != atom.id and other.has_port(GDGuideData.GuidePortKind.EXEC_IN):
				target_opt.add_item("#%d %s" % [other.id, other.title], other.id)
				if other.id == cur_to_id:
					sel_idx = target_opt.item_count - 1
		target_opt.selected = sel_idx
		var cap_port := p.kind
		target_opt.item_selected.connect(func(idx: int) -> void:
			var picked_to := target_opt.get_item_id(idx)
			if picked_to <= 0:
				_graph.disconnect_port(atom.id, cap_port)
			else:
				_graph.connect_nodes(atom.id, cap_port, picked_to)
			validate_current_graph()
			refresh_all()
		)
		p_row.add_child(target_opt)
		_inspector_box.add_child(p_row)

	# 各原子特定字段
	if atom is GDGuideAtoms.EntryAtom:
		var ea := atom as GDGuideAtoms.EntryAtom
		_add_insp_str("触发事件", ea.trigger_event.key if ea.trigger_event != null else "", func(t: String) -> void:
			ea.set_trigger_event(GDGuideData.GuideEventRef.parse(t))
			validate_current_graph()
			refresh_all()
		)
	elif atom is GDGuideAtoms.ExitAtom:
		var ex := atom as GDGuideAtoms.ExitAtom
		var r_row := HBoxContainer.new()
		var rl := Label.new()
		rl.text = "结束原因"
		rl.custom_minimum_size.x = 84
		r_row.add_child(rl)
		var r_opt := OptionButton.new()
		for r_i in range(5):
			r_opt.add_item(GDGuideAtoms.ExitAtom.exit_reason_label(r_i), r_i)
		r_opt.selected = ex.reason
		r_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_opt.item_selected.connect(func(idx: int) -> void:
			ex.set_reason(idx)
			validate_current_graph()
			refresh_all()
		)
		r_row.add_child(r_opt)
		_inspector_box.add_child(r_row)
	elif atom is GDGuideAtoms.NarrationAtom:
		var na := atom as GDGuideAtoms.NarrationAtom
		_add_insp_str("文案", na.text, func(t: String) -> void:
			na.set_text(t, na.speaker)
			validate_current_graph()
			refresh_all()
		)
		_add_insp_str("说话人", na.speaker, func(t: String) -> void: na.set_text(na.text, t))
	elif atom is GDGuideAtoms.WaitEventAtom:
		var wa := atom as GDGuideAtoms.WaitEventAtom
		_add_insp_str("事件键", wa.event_key, func(t: String) -> void:
			wa.set_event_key(t)
			validate_current_graph()
			refresh_all()
		)
	elif atom is GDGuideAtoms.DelayAtom:
		var da := atom as GDGuideAtoms.DelayAtom
		_add_insp_str("延迟秒数", str(da.delay_sec), func(t: String) -> void:
			da.set_delay(t.to_float())
			validate_current_graph()
			refresh_all()
		)
	elif atom is GDGuideAtoms.GuideTargetAtom:
		var ta := atom as GDGuideAtoms.GuideTargetAtom
		_add_insp_str("目标面板", ta.target.panel if ta.target != null else "", func(t: String) -> void:
			if ta.target == null: ta.target = GDGuideData.GuideTargetRef.new()
			ta.target.kind = GDGuideData.GuideTargetKind.UI_WIDGET
			ta.target.panel = t
			validate_current_graph()
			refresh_all()
		)
		_add_insp_str("目标控件", ta.target.widget if ta.target != null else "", func(t: String) -> void:
			if ta.target == null: ta.target = GDGuideData.GuideTargetRef.new()
			ta.target.kind = GDGuideData.GuideTargetKind.UI_WIDGET
			ta.target.widget = t
			validate_current_graph()
			refresh_all()
		)
		var st_cb := CheckBox.new()
		st_cb.text = "引导文案"
		st_cb.button_pressed = ta.show_text
		st_cb.toggled.connect(func(on: bool) -> void:
			ta.set_show_text(on)
			refresh_all()
		)
		_inspector_box.add_child(st_cb)
		if ta.show_text:
			_add_insp_str("文案内容", ta.text, func(t: String) -> void:
				ta.text = t
				refresh_all()
			)
			_add_insp_str("说话人", ta.speaker, func(t: String) -> void: ta.speaker = t)

func _refresh_log_pane() -> void:
	if _log_list_box == null:
		return
	GDEditorUi.clear_children(_log_list_box)

	if _issues_tab_btn != null and _trace_tab_btn != null:
		_issues_tab_btn.text = "校验" if _report == null else ("校验  %d 错误 / %d 警告" % [_report.error_count, _report.warning_count])
		_trace_tab_btn.text = "运行轨迹  %d" % _trace_events.size()
		GDEditorUi.style_button(_issues_tab_btn, "toggle_on" if not _show_trace else "quiet")
		GDEditorUi.style_button(_trace_tab_btn, "toggle_on" if _show_trace else "quiet")

	if _show_trace:
		if _trace_events.is_empty():
			_log_list_box.add_child(GDEditorUi.muted("还没有运行轨迹。点右上角「试跑」。"))
			return
		for evt in _trace_events:
			var btn := Button.new()
			btn.text = evt.format_trace()
			GDEditorUi.style_list_button(btn, false)
			var nid := evt.to_node_id if evt.kind == GDGuideData.GuideTraceKind.EDGE else evt.node_id
			btn.pressed.connect(func() -> void:
				if nid > 0:
					frame_node(nid)
			)
			_log_list_box.add_child(btn)
	else:
		if _report == null or _report.is_clean:
			var ok_l := Label.new()
			ok_l.text = "校验通过，没有问题。"
			ok_l.add_theme_color_override("font_color", Color(0.45, 0.9, 0.55))
			_log_list_box.add_child(ok_l)
			return
		for iss in _report.issues:
			var btn := Button.new()
			btn.text = iss.format_issue()
			GDEditorUi.style_list_button(btn, false)
			btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if iss.is_error else Color(1.0, 0.86, 0.45))
			var nid := iss.node_id
			btn.pressed.connect(func() -> void:
				if nid > 0:
					frame_node(nid)
			)
			_log_list_box.add_child(btn)

func refresh_graph_list() -> void:
	if _graph_list_box == null:
		return
	GDEditorUi.clear_children(_graph_list_box)
	var list := GDGuideEditingAndCli.find_all_graphs()
	var shown := 0
	for g in list:
		if not GDEditorUi.matches_query("%s %d" % [g.display_name, g.graph_id], _graph_query):
			continue
		shown += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(GDEditorUi.swatch(GDEditorUi.hue_color(g.graph_id), 6))
		var btn := Button.new()
		btn.text = "%s\n#%d" % [g.display_name, g.graph_id]
		btn.custom_minimum_size.y = 44
		GDEditorUi.style_list_button(btn, g == _graph)
		var cap_g := g
		btn.pressed.connect(func() -> void: load_graph(cap_g))
		row.add_child(btn)
		_graph_list_box.add_child(row)
	if shown == 0 and not list.is_empty():
		_graph_list_box.add_child(GDEditorUi.muted("没有匹配「%s」的引导图。" % _graph_query.strip_edges()))
	elif list.is_empty():
		_graph_list_box.add_child(GDEditorUi.empty_state("还没有引导图", [
			"点下面的「+ 新建」。",
			"或打开「示例图」看看一条完整引导。",
		]))
	if _graph == null and not list.is_empty() and _graph_query.strip_edges().is_empty():
		load_graph(list[0])

func _ensure_sample_graphs() -> void:
	if not GDGuideEditingAndCli.find_all_graphs().is_empty():
		return
	var g1 := GDGuideGraphAndValidator.GuideGraphRes.new()
	GDGuideEditingAndCli.GuideSampleGraphs.build_sample(g1)
	GDGuideEditingAndCli.register_in_memory_graph(g1)

	var g2 := GDGuideGraphAndValidator.GuideGraphRes.new()
	GDGuideEditingAndCli.GuideSampleGraphs.build_condition_sample(g2)
	GDGuideEditingAndCli.register_in_memory_graph(g2)

func _create_new_graph() -> void:
	var g := GDGuideGraphAndValidator.GuideGraphRes.new()
	var gid := GDGuideEditingAndCli.suggest_graph_id()
	g.set_graph_id(gid)
	g.set_display_name("Guide_%d" % gid)
	g.add_default_skeleton()
	GDGuideEditingAndCli.register_in_memory_graph(g)
	refresh_graph_list()
	load_graph(g)

func _open_sample_graph() -> void:
	_ensure_sample_graphs()
	var g := GDGuideEditingAndCli._in_memory_graphs.get(GDGuideEditingAndCli.GuideSampleGraphs.SAMPLE_GRAPH_ID, null)
	if g != null:
		load_graph(g)

func _save_graph() -> void:
	if _graph == null:
		return
	if not _graph.resource_path.is_empty():
		ResourceSaver.save(_graph, _graph.resource_path)
	validate_current_graph()
	refresh_all()

func _trigger_selected_graph() -> void:
	if _graph == null:
		return
	validate_current_graph()
	if _report != null and _report.has_errors:
		_show_trace = false
		refresh_all()
		return
	_trace_events.clear()
	_host.set_predicate("sample_has_coin", true)
	_runner.try_start(_graph, 0, true)
	_show_trace = true
	refresh_all()

func _delete_selected_in_canvas() -> void:
	if _graph == null or _runner.is_running or _selected_node_id <= 0:
		return
	GDGuideEditingAndCli.GuideGraphEditing.delete_elements(_graph, [_selected_node_id], [])
	_selected_node_id = 0
	validate_current_graph()
	refresh_all()

func _start_click_capture() -> void:
	if _graph == null or _selected_node_id <= 0:
		_set_canvas_status("先在画布上点一个节点，再录点击。")
		return
	_capturing_clicks = true
	_capture_tail_id = _selected_node_id
	_capture_count += 1
	var target := GDGuideData.GuideTargetRef.ui("HomePanel", "BtnSample_%d" % _capture_count)
	var atom := GDGuideEditingAndCli.GuideGraphEditing.capture_click(_graph, _capture_tail_id, target, "示例按钮_%d" % _capture_count)
	if atom != null:
		_capture_tail_id = atom.id
		_selected_node_id = atom.id
	validate_current_graph()
	refresh_all()

func _stop_click_capture() -> void:
	_capturing_clicks = false

func _add_insp_str(label_text: String, val: String, on_changed: Callable) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 84
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.text = val
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(t: String) -> void: on_changed.call(t))
	row.add_child(edit)
	_inspector_box.add_child(row)

func _add_insp_int(label_text: String, val: int, on_changed: Callable) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 84
	row.add_child(lbl)
	var sb := SpinBox.new()
	sb.step = 1
	sb.min_value = 0
	sb.max_value = 999999
	sb.value = val
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.value_changed.connect(func(v: float) -> void: on_changed.call(roundi(v)))
	row.add_child(sb)
	_inspector_box.add_child(row)
