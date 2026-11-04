@tool
class_name GDGuidePage
extends GDPage

## 新手引导编辑器：左边引导图，中间节点画布，右边属性。试跑时工具栏右侧换成调试条。

const GUIDE_ROOT := "res://game_res/guide"
const PULSE_DECAY := 1.6


## 画布上“在哪儿加节点、从哪个口接过来”。
class PendingAdd extends RefCounted:
	var position: Vector2 = Vector2.ZERO
	var from_id: int = 0
	var port: int = GDGuideData.GuidePortKind.EXEC_OUT


var _host: GDGuideServices.GuideHost = null
var _runner: GDGuideRunnerSystem.GuideRunner = null
var _report: GDGuideValidation.GuideValidationReport = null

var _list: GDGuideGraphList = null
var _view: GDGuideGraphView = null
var _palette: GDGuideNodePalette = null
var _drawer: GDGuideDrawer = null
var _form: GDForm = null
var _banner: PanelContainer = null
var _banner_label: Label = null
var _canvas_box: Control = null
var _center_empty: Control = null

var _add_btn: Button = null
var _frame_btn: Button = null
var _arrange_btn: Button = null
var _idle_strip: HBoxContainer = null
var _debug_strip: GDGuideDebugStrip = null
var _run_btn: Button = null

var _selected_ids: Array[int] = []
var _pending: PendingAdd = PendingAdd.new()
var _pulses: Dictionary = {} # Vector3i(from, port, to) -> 剩余亮度
var _show_run: bool = false
var _run_dirty: bool = false
var _opened_default: bool = false


var graph: GDGuideGraphRes:
	get:
		return doc.resource as GDGuideGraphRes if doc != null else null


func _build() -> void:
	_add_btn = _labeled(&"Add", "节点", "添加节点", _open_palette_from_toolbar)
	toolbar.add_child(_add_btn)
	_frame_btn = _labeled(&"CenterView", "适配", "让全部节点进入视野", frame_all)
	toolbar.add_child(_frame_btn)
	_arrange_btn = _labeled(&"GridLayout", "整理", "按连线自动排列", _arrange)
	toolbar.add_child(_arrange_btn)
	_build_toolbar_right()
	_ensure_runtime()

	_list = GDGuideGraphList.new()
	_list.open_requested.connect(load_graph)
	_list.created.connect(_adopt)
	_list.removed.connect(_forget)
	_list.rename_confirmed.connect(_rename_graph)
	_list.said.connect(say)

	_form = GDForm.new()
	_form.committed.connect(func(label: String, merge: bool) -> void:
		if doc != null:
			doc.commit("修改%s" % label, merge)
	)
	set_panes(GDEditorUi.pane(_list), GDEditorUi.pane(_build_center(), 0), GDEditorUi.pane(GDEditorUi.scroll_of(_form)))
	_palette = GDGuideNodePalette.new()
	_palette.picked.connect(_add_node)
	add_child(_palette)
	document_state_changed.connect(func() -> void: _list.refresh(graph))
	_refresh()


func _build_center() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", GDEditorUi.flat_box(Color(GDEditorUi.tone(&"warn"), 0.16), Color(0, 0, 0, 0), 0, 0, GDEditorUi.PAD, 4))
	var row := HBoxContainer.new()
	_banner.add_child(row)
	_banner_label = GDEditorUi.hint_label("")
	_banner_label.add_theme_color_override("font_color", GDEditorUi.tone(&"warn"))
	row.add_child(_banner_label)
	row.add_child(GDEditorUi.text_button("清理", _clear_missing))
	box.add_child(_banner)

	_center_empty = GDEditorUi.empty_state("没有打开引导图", "", "新建引导图", func() -> void: _list.new_graph())
	box.add_child(_center_empty)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas_box = split
	box.add_child(split)
	_view = GDGuideGraphView.new()
	_view.connect_requested.connect(_on_connect)
	_view.disconnect_requested.connect(_on_disconnect)
	_view.connect_to_empty_requested.connect(func(from_id: int, port: int, at: Vector2) -> void: _open_palette(at, from_id, port))
	_view.canvas_menu_requested.connect(func(at: Vector2) -> void: _open_palette(at, 0, 0))
	_view.node_menu_requested.connect(_show_node_menu)
	_view.delete_requested.connect(_delete_nodes)
	_view.duplicate_requested.connect(_duplicate_nodes)
	_view.nodes_moved.connect(_commit_moves)
	_view.selection_changed.connect(func() -> void:
		_selected_ids = _view.selected_ids()
		_refresh_inspector()
	)
	split.add_child(_view)
	_drawer.node_picked.connect(func(node_id: int) -> void:
		_view.select_ids([node_id])
		_view.center_on(node_id)
	)
	split.add_child(_drawer)
	return box


func _build_toolbar_right() -> void:
	_idle_strip = HBoxContainer.new()
	_idle_strip.add_theme_constant_override("separation", GDEditorUi.GAP)
	_drawer = GDGuideDrawer.new()
	_idle_strip.add_child(_drawer.badge)
	_run_btn = GDEditorUi.text_button("试跑", _run, &"primary", &"Play")
	if _run_btn.icon == null:
		_run_btn.text = "▶ 试跑"
	_run_btn.tooltip_text = "从入口跑一遍，节点和连线会跟着亮"
	_run_btn.shortcut = GDEditorUi.key(KEY_F5)
	_run_btn.shortcut_context = self
	_idle_strip.add_child(_run_btn)
	toolbar_right.add_child(_idle_strip)

	_debug_strip = GDGuideDebugStrip.new()
	_debug_strip.acted.connect(_mark_run_dirty)
	_debug_strip.said.connect(say)
	toolbar_right.add_child(_debug_strip)
	toolbar_right.add_child(GDEditorUi.menu_button("", &"GuiTabMenuHl", "更多", [
		{"text": "示例引导图", "do": _open_samples},
		null,
		{"text": "另存为…", "do": save_as_current},
	]))


static func _labeled(icon_name: StringName, text: String, tip: String, on_pressed: Callable) -> Button:
	var btn := GDEditorUi.tool_button(icon_name, tip, on_pressed)
	btn.text = text if btn.icon != null or icon_name != &"Add" else "+ " + text
	return btn


func _ready() -> void:
	set_process(false)


func _enter_tree() -> void:
	_ensure_runtime()


## 页面离开场景树时释放试跑会话（外壳不再管这件事）。
func _exit_tree() -> void:
	if _runner != null:
		_runner.dispose()
	if _host != null:
		_host.dispose()


func _ensure_runtime() -> void:
	if _runner != null and not _runner.is_disposed:
		return
	_host = GDGuideServices.GuideHost.new()
	_runner = GDGuideRunnerSystem.GuideRunner.new(_host)
	_runner.traced.connect(_on_traced)
	_debug_strip.bind(_host, _runner)


func activate() -> void:
	GDGuideEditing.scan_graphs(GUIDE_ROOT)
	_list.refresh(graph)
	if not _opened_default and doc == null:
		_opened_default = true
		var shown := _list.shown_graphs()
		if not shown.is_empty():
			load_graph(shown[0])


func cli_context(command: String) -> PackedStringArray:
	if graph == null or not command.begins_with("guide."):
		return PackedStringArray()
	return PackedStringArray(["--asset", graph.resource_path if not graph.resource_path.is_empty() else str(graph.graph_id)])


func _suggest_save_path(resource: Resource) -> String:
	return "%s/Guide_%d.tres" % [GUIDE_ROOT, (resource as GDGuideGraphRes).graph_id]


# ── 公开接口 ──

func load_graph(new_graph: GDGuideGraphRes) -> void:
	if new_graph != null:
		GDGuideSchemaMigrator.migrate(new_graph)
		if new_graph.atoms.is_empty():
			new_graph.add_default_skeleton()
	if _runner.is_running and _runner.graph != new_graph:
		_runner.stop()
	_selected_ids.clear()
	_show_run = false
	_pulses.clear()
	open_document(new_graph)
	_refresh()
	_view.frame_all(true)


func get_current_graph() -> GDGuideGraphRes:
	return graph


func get_runner() -> GDGuideRunnerSystem.GuideRunner:
	return _runner


func get_report() -> GDGuideValidation.GuideValidationReport:
	return _report


func frame_all() -> void:
	_view.frame_all()


func is_read_only() -> bool:
	return graph == null or graph.missing_atom_count > 0 or _runner.is_running


# ── 刷新 ──

## 运行着色只保留到下一次改动。
func _refresh() -> void:
	_show_run = _show_run and _runner.is_running
	var g := graph
	_report = GDGuideValidation.GuideGraphValidator.validate(g, [], _host.conditions) if g != null else null
	_list.refresh(g)
	_center_empty.visible = g == null
	_canvas_box.visible = g != null
	var missing := g.missing_atom_count if g != null else 0
	_banner.visible = missing > 0
	_banner_label.text = "%d 个节点类型缺失，整张图只读" % missing
	_view.sync(g, _view_state())
	_selected_ids = _view.selected_ids()
	_drawer.set_issues(_report, g)
	_refresh_toolbar()
	_refresh_inspector()


func _view_state() -> GDGuideGraphView.ViewState:
	var state := GDGuideGraphView.ViewState.new()
	state.report = _report
	state.read_only = is_read_only()
	state.breakpoints = GDGuideRunnerSystem.GuideBreakpoints.get_all(graph)
	if _show_run and graph != null and _runner.graph == graph:
		state.snapshot = _runner.capture_snapshot()
	return state


func _refresh_toolbar() -> void:
	var running := _runner.is_running
	var editable := not is_read_only()
	_add_btn.disabled = not editable
	_arrange_btn.disabled = not editable
	_frame_btn.disabled = graph == null
	_idle_strip.visible = not running
	_debug_strip.visible = running
	_run_btn.disabled = graph == null
	if running:
		_debug_strip.refresh(graph)


func _refresh_inspector() -> void:
	var g := graph
	if g == null:
		_form.clear()
		return
	var ctx := _inspector_context()
	if _selected_ids.size() > 1:
		if _form.begin(["multi", _selected_ids.size(), ctx.read_only]):
			_form.heading("已选 %d 个节点" % _selected_ids.size())
			_form.button("复制", func() -> void: _duplicate_nodes(_selected_ids.duplicate()))
			_form.button("删除", func() -> void: _delete_nodes(_selected_ids.duplicate()), &"danger")
			GDGuideInspector.finish(_form, ctx)
		return
	var atom := g.find_atom(_selected_ids[0]) if _selected_ids.size() == 1 else null
	if atom != null:
		if _form.begin(GDGuideInspector.node_key(g, atom, ctx.read_only)):
			GDGuideInspector.build_node(_form, atom, ctx)
	elif _form.begin(["graph", g, ctx.read_only]):
		GDGuideInspector.build_graph(_form, g, ctx)


func _inspector_context() -> GDGuideInspector.Context:
	var ctx := GDGuideInspector.Context.new()
	ctx.graph = graph
	ctx.conditions = _host.conditions
	ctx.read_only = is_read_only()
	ctx.commit = _commit
	ctx.convert = _convert_node
	ctx.set_graph_id = _set_graph_id
	return ctx


func _commit(label: String) -> void:
	doc.commit(label)


## 撤销会重建节点对象，试跑中的执行器还握着旧对象，所以先结束再撤销。
func _step_history(backwards: bool) -> void:
	if _runner.is_running:
		say("试跑中，结束后再撤销", &"warn")
		return
	super(backwards)


## 只读时说明原因并返回 true。
func _blocked() -> bool:
	if graph == null:
		return true
	if _runner.is_running:
		say("试跑中，结束后再改", &"warn")
		return true
	if graph.missing_atom_count > 0:
		say("有节点类型缺失，整张图只读", &"warn")
		return true
	return false


# ── 画布操作 ──

func _on_connect(from_id: int, port: int, to_id: int) -> void:
	if _blocked():
		return
	var result := graph.connect_nodes(from_id, port, to_id)
	if not bool(result["ok"]):
		say(str(result["reason"]), &"warn")
		return
	_commit("连线")


func _on_disconnect(from_id: int, port: int) -> void:
	if not _blocked() and graph.disconnect_port(from_id, port):
		_commit("断开连线")


func _open_palette(at: Vector2, from_id: int, port: int, screen := Vector2.INF) -> void:
	if _blocked():
		return
	_pending = PendingAdd.new()
	_pending.position = at
	_pending.from_id = from_id
	_pending.port = port
	_palette.open_at(screen if screen != Vector2.INF else get_screen_position() + get_local_mouse_position(), from_id > 0)


## 选中一个节点且它有空着的输出口时，新节点放在它右边并接上。
func _open_palette_from_toolbar() -> void:
	var at := _view.view_center_canvas()
	var from_id := 0
	var port := 0
	var atom := graph.find_atom(_selected_ids[0]) if graph != null and _selected_ids.size() == 1 else null
	if atom != null:
		for p in atom.get_ports():
			if not p.is_input and not bool(graph.try_get_edge(atom.id, p.kind)["ok"]):
				from_id = atom.id
				port = p.kind
				at = atom.editor_position + Vector2(GDGuideGraphView.NODE_WIDTH + 80, 0)
				break
	_open_palette(at, from_id, port, _add_btn.get_screen_position() + Vector2(0, _add_btn.size.y))


func _add_node(atom_type_id: String) -> void:
	if _blocked():
		return
	var at := _pending.position.snapped(Vector2.ONE * GDGuideEditing.GRID_SIZE)
	var atom := GDGuideEditing.add_node(graph, atom_type_id, at, _pending.from_id, _pending.port)
	if atom == null:
		return
	_pending = PendingAdd.new()
	_selected_ids = [atom.id]
	_commit("添加节点")
	_view.select_ids([atom.id])


func _delete_nodes(ids: Array[int]) -> void:
	if ids.is_empty() or _blocked():
		return
	var removed := 0
	for node_id in ids:
		if graph.remove_atom(node_id):
			removed += 1
	if removed > 0:
		_commit("删除节点")
		say("已删除 %d 个节点，可以撤销" % removed)


func _duplicate_nodes(ids: Array[int]) -> void:
	if _blocked():
		return
	var copies := GDGuideEditing.duplicate_nodes(graph, ids, Vector2(40, 40))
	if not copies.is_empty():
		_commit("复制节点")
		_view.select_ids(copies)


func _commit_moves() -> void:
	if graph == null:
		return
	var moved := 0
	for node in _view.graph_nodes():
		var atom := graph.find_atom(int(String(node.name)))
		if atom != null and not atom.editor_position.is_equal_approx(node.position_offset):
			atom.assign_editor_position(node.position_offset)
			moved += 1
	if moved > 0:
		_commit("移动节点")


func _arrange() -> void:
	if _blocked():
		return
	if GDGuideEditing.arrange(graph, _view.node_sizes()) == 0:
		say("已经排好了")
		return
	_commit("整理节点")
	_view.frame_all()


func _clear_missing() -> void:
	if graph != null and not _runner.is_running and graph.remove_missing_atom_slots() > 0:
		_commit("清理缺失节点")


func _show_node_menu(node_id: int) -> void:
	var atom := graph.find_atom(node_id)
	if atom == null:
		return
	var locked := is_read_only()
	var has_breakpoint := GDGuideRunnerSystem.GuideBreakpoints.contains(graph, node_id)
	var items: Array = [
		{"text": "重命名…", "do": func() -> void: _rename_node(node_id), "shortcut": GDEditorUi.key(KEY_F2), "disabled": locked},
		{"text": "取消断点" if has_breakpoint else "设置断点", "do": func() -> void: _toggle_breakpoint(node_id), "shortcut": GDEditorUi.key(KEY_F9)},
		{"text": "从此节点试跑", "do": func() -> void: _run_from(node_id), "disabled": _runner.is_running or not graph.is_reachable_from_entry(node_id)},
	]
	if atom is GDGuideAtoms.GuideTargetAtom and not (atom as GDGuideAtoms.GuideTargetAtom).alternate_type_id.is_empty():
		items.append({"text": "转为弱引导" if atom is GDGuideAtoms.StrongGuideAtom else "转为强引导", "do": func() -> void: _convert_node(node_id), "disabled": locked})
	if atom.has_port(GDGuideData.GuidePortKind.EXEC_OUT):
		items.append({"text": "在后面插入点击引导…", "do": func() -> void: _insert_click(node_id), "disabled": locked})
	items.append(null)
	items.append({"text": "复制", "do": func() -> void: _duplicate_nodes([node_id]), "shortcut": GDEditorUi.key(KEY_D, true), "disabled": locked or atom is GDGuideAtoms.EntryAtom})
	items.append({"text": "删除", "do": func() -> void: _delete_nodes([node_id]), "shortcut": GDEditorUi.key(KEY_DELETE), "disabled": locked})
	GDEditorUi.context_menu(self, items)


func _rename_node(node_id: int) -> void:
	var atom := graph.find_atom(node_id)
	if atom == null or _blocked():
		return
	GDDialogs.prompt(self, "重命名节点", "节点名", atom.display_name, func(value: String) -> void:
		var target := graph.find_atom(node_id)
		if target != null:
			target.set_display_name(value)
			_commit("重命名节点")
	)


func _toggle_breakpoint(node_id: int) -> void:
	if graph == null or graph.find_atom(node_id) == null:
		return
	GDGuideRunnerSystem.GuideBreakpoints.toggle(graph, node_id)
	_view.sync(graph, _view_state())
	say("已设置断点" if GDGuideRunnerSystem.GuideBreakpoints.contains(graph, node_id) else "已取消断点")


func _convert_node(node_id: int) -> void:
	if not _blocked() and GDGuideEditing.convert_guide(graph, node_id) != null:
		_commit("强弱引导互转")


## 用设计师填的真实面板和控件路径插一步强引导，接在这个节点后面。
func _insert_click(node_id: int) -> void:
	if _blocked():
		return
	GDDialogs.form(self, "在后面插入点击引导", [
		{"key": "panel", "label": "面板", "value": "", "placeholder": "例如 HomePanel"},
		{"key": "widget", "label": "控件", "value": "", "placeholder": "例如 BtnStart"},
		{"key": "tip", "label": "提示", "value": "", "placeholder": "可以不填"},
	], func(values: Dictionary) -> void:
		var target := GDGuideData.GuideTargetRef.ui(str(values["panel"]), str(values["widget"]))
		var atom := GDGuideEditing.capture_click(graph, node_id, target)
		if atom == null:
			say("插不进去：这个节点没有下一步口", &"warn")
			return
		if not str(values["tip"]).is_empty():
			atom.set_text(str(values["tip"]))
		_selected_ids = [atom.id]
		_commit("插入点击引导")
		_view.select_ids([atom.id])
	, func(values: Dictionary) -> String:
		return "面板和控件都要填" if str(values["panel"]).is_empty() or str(values["widget"]).is_empty() else ""
	)


func _set_graph_id(new_id: int) -> void:
	var other := GDGuideEditing.find_graph(new_id)
	if other != null and other != graph:
		say("图 ID %d 已被「%s」占用" % [new_id, other.display_name], &"danger")
		return
	graph.set_graph_id(new_id)
	GDGuideEditing.reindex()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or not is_visible_in_tree() or _selected_ids.size() != 1:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and focus != _view and not _view.is_ancestor_of(focus):
		return
	match key_event.keycode:
		KEY_F9:
			_toggle_breakpoint(_selected_ids[0])
		KEY_F2:
			_rename_node(_selected_ids[0])
		_:
			return
	get_viewport().set_input_as_handled()


# ── 引导图列表 ──

## 新建或复制出来的图：登记、打开并立刻保存，重启编辑器后还能找到。
func _adopt(created: GDGuideGraphRes) -> void:
	GDGuideEditing.register_in_memory_graph(created)
	load_graph(created)
	save_current()


func _rename_graph(g: GDGuideGraphRes, new_name: String) -> void:
	if graph != g:
		load_graph(g)
	g.set_display_name(new_name)
	_commit("重命名引导图")


func _forget(g: GDGuideGraphRes) -> void:
	var was_current := graph == g
	close_document(g)
	if was_current:
		var shown := _list.shown_graphs()
		load_graph(shown[0] if not shown.is_empty() else null)
	else:
		_list.refresh(graph)


func _open_samples() -> void:
	_list.show_samples = true
	var samples := GDGuideSamples.ensure_registered()
	load_graph(samples[0])


# ── 试跑 ──

func _run() -> void:
	if graph != null and not _runner.is_running and _check_runnable():
		_start(func() -> bool: return _runner.try_start(graph, 0, true))


func _run_from(node_id: int) -> void:
	if graph != null and not _runner.is_running and _check_runnable():
		_start(func() -> bool: return _runner.try_start_from(graph, node_id))


## 有校验错误时不跑，直接打开问题列表。
func _check_runnable() -> bool:
	_report = GDGuideValidation.GuideGraphValidator.validate(graph, [], _host.conditions)
	if not _report.has_errors:
		return true
	_drawer.open_tab(GDGuideDrawer.Tab.ISSUES)
	say("有 %d 个错误，修好再试跑" % _report.error_count, &"danger")
	return false


func _start(starter: Callable) -> void:
	_drawer.clear_trace()
	_pulses.clear()
	_host.predicates.erase("sample_has_coin")
	if GDGuideSamples.is_sample(graph):
		_host.set_predicate("sample_has_coin", true)
	_show_run = true
	_drawer.open_tab(GDGuideDrawer.Tab.TRACE)
	if not starter.call():
		say("没能开始：%s" % _runner.get_current_exit_message(), &"danger")
	_selected_ids.clear()
	_refresh()
	set_process(true)


func _mark_run_dirty() -> void:
	_run_dirty = true
	set_process(true)


func _on_traced(evt: GDGuideRunnerSystem.GuideTraceEvent) -> void:
	_drawer.add_event(evt, graph)
	if evt.kind == GDGuideData.GuideTraceKind.EDGE:
		_pulses[Vector3i(evt.node_id, evt.port, evt.to_node_id)] = 1.0
	_mark_run_dirty()


## 只在试跑期间（以及连线脉冲还没熄灭时）逐帧推进，延迟和自动继续才会真的走。
func _process(delta: float) -> void:
	if _runner.is_running and not _runner.is_paused:
		_runner.tick(delta)
	for key: Vector3i in _pulses.keys():
		var amount: float = _pulses[key] - delta * PULSE_DECAY
		_view.pulse_edge(key.x, key.y, key.z, maxf(amount, 0.0))
		if amount <= 0.0:
			_pulses.erase(key)
		else:
			_pulses[key] = amount
	if _debug_strip.visible and not _runner.is_running:
		_on_run_finished()
	elif _run_dirty:
		_run_dirty = false
		_view.sync(graph, _view_state())
	if _runner.is_running:
		_debug_strip.refresh(graph)
	elif _pulses.is_empty():
		set_process(false)


func _on_run_finished() -> void:
	_run_dirty = false
	var snap := _runner.capture_snapshot()
	var completed := snap.exit_reason == GDGuideData.GuideExitReason.COMPLETED
	say("试跑结束：%s · %s" % [GDGuideAtoms.ExitAtom.exit_reason_label(snap.exit_reason), snap.exit_message], &"ok" if completed else &"warn")
	_view.sync(graph, _view_state())
	_refresh_toolbar()
	_refresh_inspector()
