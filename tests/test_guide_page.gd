extends SceneTree

## 引导页的独立测试：在场景树里实例化 GDGuidePage，驱动真实的画布信号、表单、撤销、保存和试跑。
## 运行：godot --headless --path D:/GodotTemplate -s res://addons/gdesigner_tools/tests/test_guide_page.gd

const OUT := GDGuideData.GuidePortKind.EXEC_OUT
const TMP_DIR := "user://gdt_guide_page_test"

var failures := 0
var passes := 0
var page: GDGuidePage = null
var last_status := ""
var last_tone: StringName = &""


func _initialize() -> void:
	Engine.max_fps = 120
	_run_all.call_deferred()


func _run_all() -> void:
	GDGuideEditing._in_memory_graphs.clear()
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	page = GDGuidePage.new()
	page.status_changed.connect(func(text: String, tone: StringName) -> void:
		last_status = text
		last_tone = tone
	)
	root.size = Vector2i(1280, 800)
	root.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.activate()
	await _frames(3)

	_test_model_sync()
	await _test_frame_all()
	_test_connections()
	_test_delete_undo()
	_test_move_undo()
	_test_palette_and_duplicate()
	await _test_insert_click()
	_test_validation_badge()
	await _test_breakpoint_run()
	await _test_full_run()
	await _test_all_atom_inspectors()
	_test_scan_graphs()
	_test_missing_atoms()
	_test_multi_select()
	_test_exit_tree()

	_cleanup()
	print("TOTAL PASSED: %d  FAILED: %d" % [passes, failures])
	quit(failures)


# ── helpers ──

func _check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
		print("  PASS  ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _wait_until(condition: Callable, max_ms: int = 4000) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call():
		if Time.get_ticks_msec() - start > max_ms:
			return false
		await process_frame
	return true


var graph: GDGuideGraphRes:
	get:
		return page.get_current_graph()


func _edge_to(from_id: int, port: int) -> int:
	var found := graph.try_get_edge(from_id, port)
	return (found["edge"] as GDGuideData.GuideEdge).to_id if bool(found["ok"]) else 0


func _view_edges() -> Dictionary:
	var out := {}
	for c in page._view.get_connection_list():
		out["%s|%d|%s" % [c["from_node"], c["from_port"], c["to_node"]]] = true
	return out


func _model_matches_view() -> bool:
	var view := page._view
	if view.graph_nodes().size() != graph.atoms.size():
		return false
	for atom in graph.atoms:
		var node := view.graph_node(atom.id)
		if node == null or node.title != atom.title or not node.position_offset.is_equal_approx(atom.editor_position):
			return false
	var wanted := {}
	for e in graph.edges:
		var index := (view.graph_node(e.from_id).get_meta("outs") as Array).find(e.port)
		wanted["%d|%d|%d" % [e.from_id, index, e.to_id]] = true
	return wanted == _view_edges()


func _select(ids: Array) -> void:
	page._view.select_ids(ids)
	page._selected_ids.assign(ids)
	page._refresh_inspector()


## 表单里“标签 -> 控件”的对照（含折叠区里的行）。
func _rows() -> Dictionary:
	var out := {}
	_collect_rows(page._form, out)
	return out


func _collect_rows(node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		if child is HBoxContainer and child.get_child_count() == 2 and child.get_child(0) is Label:
			var caption := (child.get_child(0) as Label).text
			if not out.has(caption):
				out[caption] = child.get_child(1)
		_collect_rows(child, out)


func _buttons() -> Dictionary:
	var out := {}
	_collect_buttons(page._form, out)
	return out


func _collect_buttons(node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		if child is Button and not (child is OptionButton) and not (child is CheckBox):
			out[child.text] = child
		_collect_buttons(child, out)


func _write(caption: String, value: Variant) -> bool:
	var control: Variant = _rows().get(caption)
	if control is LineEdit:
		control.text = str(value)
		control.text_submitted.emit(str(value))
	elif control is TextEdit:
		control.text = str(value)
		control.focus_exited.emit()
	elif control is SpinBox:
		control.value = float(value)
	elif control is OptionButton:
		var index: int = control.get_item_index(int(value))
		control.select(index)
		control.item_selected.emit(index)
	elif control is CheckBox:
		control.button_pressed = bool(value)
	else:
		print("    no field: ", caption)
		return false
	return true


func _dialog() -> ConfirmationDialog:
	for i in range(page.get_child_count() - 1, -1, -1):
		var child := page.get_child(i)
		if child is ConfirmationDialog and child.visible:
			return child
	return null


# ── tests ──

func _test_model_sync() -> void:
	print("[model sync]")
	_check(graph != null and graph.graph_id == GDGuideSamples.SAMPLE_GRAPH_ID, "activate opens the sample graph when the project has none")
	_check(_model_matches_view(), "GraphNodes and connections match the model")
	var node := page._view.graph_node(5)
	_check(node.get_meta("outs") == [GDGuideData.GuidePortKind.EXEC_TRUE, GDGuideData.GuidePortKind.EXEC_FALSE], "Branch node exposes 是 / 否 output rows")
	_check(node.is_slot_enabled_left(0) and not page._view.graph_node(1).is_slot_enabled_left(0), "Input port on the first row; entry has none")
	_check(page._form.get_child_count() > 0 and _rows().has("图 ID"), "Nothing selected shows the graph header")
	_check(page._list._tree.get_root().get_child_count() > 0, "Library lists the sample graphs")
	var first_node := page._view.graph_nodes()[0]
	page._view.sync(graph, page._view_state())
	_check(page._view.graph_nodes()[0] == first_node, "Refresh keeps existing GraphNodes (no rebuild)")


func _test_frame_all() -> void:
	print("[frame_all]")
	page._view.zoom = 2.0
	page._view.scroll_offset = Vector2(-5000, -5000)
	page.frame_all()
	await _frames(2)
	var view := page._view
	var inside := true
	for node in view.graph_nodes():
		var top_left := node.position_offset * view.zoom - view.scroll_offset
		var rect := Rect2(top_left, node.size * view.zoom)
		inside = inside and Rect2(Vector2.ZERO, view.size).grow(1).encloses(rect)
	_check(inside and view.zoom < 1.0, "frame_all zooms and scrolls so every node is visible (zoom %.2f)" % view.zoom)


func _test_connections() -> void:
	print("[connections]")
	page._view.connection_request.emit(&"2", 0, &"4", 0)
	_check(_edge_to(2, OUT) == 4 and page.doc.undo_label == "连线", "connection_request replaces the out port's edge and commits")
	_check(_view_edges().has("2|0|4") and not _view_edges().has("2|0|3"), "View reconciles the replaced connection")
	page._view.connection_request.emit(&"2", 0, &"1", 0)
	_check(_edge_to(2, OUT) == 4 and last_status.contains("不能被连入"), "Connecting into the entry is refused with a reason")
	page._step_history(true)
	_check(_edge_to(2, OUT) == 3 and _model_matches_view(), "Undo restores the original edge")
	page._view.disconnection_request.emit(&"5", 1, &"6", 0)
	_check(_edge_to(5, GDGuideData.GuidePortKind.EXEC_FALSE) == 0 and not _view_edges().has("5|1|6"), "disconnection_request removes the 否 edge")
	page._step_history(true)
	_check(_edge_to(5, GDGuideData.GuidePortKind.EXEC_FALSE) == 6, "Undo restores the 否 edge")


func _test_delete_undo() -> void:
	print("[delete + undo]")
	var edges_before := graph.edges.size()
	page._view.delete_nodes_request.emit([&"4"])
	_check(graph.find_atom(4) == null and page._view.graph_node(4) == null and graph.edges.size() == edges_before - 2, "Delete removes the node and its two edges")
	page._step_history(true)
	_check(graph.find_atom(4) != null and _edge_to(3, OUT) == 4 and _edge_to(4, OUT) == 5 and _model_matches_view(), "Undo restores the node and its edges")


func _test_move_undo() -> void:
	print("[move + undo]")
	var node := page._view.graph_node(2)
	var before := node.position_offset
	node.position_offset = before + Vector2(100, 40)
	page._view.end_node_move.emit()
	_check(graph.find_atom(2).editor_position.is_equal_approx(before + Vector2(100, 40)) and page.doc.undo_label == "移动节点", "end_node_move commits 移动节点 once")
	var depth := page.doc._cursor
	page._view.end_node_move.emit()
	_check(page.doc._cursor == depth, "A move without changes does not add history")
	page._step_history(true)
	_check(graph.find_atom(2).editor_position.is_equal_approx(before) and page._view.graph_node(2).position_offset.is_equal_approx(before), "Undo moves the node back")


func _test_palette_and_duplicate() -> void:
	print("[palette + duplicate]")
	var count := graph.atoms.size()
	page._open_palette(Vector2(400, 400), 8, OUT)
	_check(page._palette.visible and not page._palette.listed_types().has("io.guide.entry"), "Dragging to empty opens the palette without un-connectable types")
	page._palette._search.text = "延迟"
	page._palette._rebuild()
	page._palette._search.text_submitted.emit("延迟")
	var created: GDGuideAtoms.GuideAtom = graph.atoms[graph.atoms.size() - 1]
	_check(graph.atoms.size() == count + 1 and created is GDGuideAtoms.DelayAtom and _edge_to(8, OUT) == created.id, "Picking from the palette adds the node and auto-connects it")
	_check(page._selected_ids == [created.id] and _rows().has("延迟"), "The new node is selected and inspected")
	page._step_history(true)
	_check(graph.atoms.size() == count and _edge_to(8, OUT) == 9, "Undo removes it and restores the old edge")
	page._view.select_ids([2, 3])
	page._view.duplicate_nodes_request.emit()
	var copies := graph.atoms.slice(count)
	_check(copies.size() == 2 and _edge_to(copies[0].id, OUT) == copies[1].id and page.doc.undo_label == "复制节点", "Ctrl+D duplicates the selection and the edge between them")
	page._step_history(true)
	_check(graph.atoms.size() == count, "Undo removes the duplicates")


func _test_insert_click() -> void:
	print("[insert click guide]")
	var count := graph.atoms.size()
	page._show_node_menu(3)
	var menu: PopupMenu = null
	for child in page.get_children():
		if child is PopupMenu:
			menu = child
	var texts := PackedStringArray()
	for i in range(menu.item_count if menu != null else 0):
		texts.append(menu.get_item_text(i))
	_check("在后面插入点击引导…" in texts and "设置断点" in texts and "从此节点试跑" in texts and "删除" in texts, "Node context menu lists the node actions")
	if menu != null:
		menu.hide()
	page._insert_click(3)
	var dialog := _dialog()
	var edits: Array[LineEdit] = []
	for edit in dialog.find_children("*", "LineEdit", true, false):
		edits.append(edit)
	_check(dialog != null and edits.size() == 3 and dialog.get_ok_button().disabled, "Insert dialog asks for 面板 / 控件 / 提示 and needs both")
	for pair in [[0, "HomePanel"], [1, "BtnStart"], [2, "点这里开始"]]:
		edits[pair[0]].text = pair[1]
		edits[pair[0]].text_changed.emit(pair[1])
	dialog.confirmed.emit()
	dialog.hide()
	var added := graph.atoms[graph.atoms.size() - 1] as GDGuideAtoms.StrongGuideAtom
	_check(graph.atoms.size() == count + 1 and added != null and added.target.panel == "HomePanel" and added.target.widget == "BtnStart" and added.text == "点这里开始", "Inserted strong guide uses the real target")
	_check(_edge_to(3, OUT) == added.id and _edge_to(added.id, OUT) == 4, "It sits between the node and its old next step")
	page._step_history(true)
	_check(graph.atoms.size() == count and _edge_to(3, OUT) == 4, "Undo removes the inserted step")
	await _frames(1)


func _test_validation_badge() -> void:
	print("[validation badge]")
	_check(page._drawer.badge.text == "✓ 校验通过" and not page._report.has_errors, "Clean sample shows ✓ 校验通过")
	graph.find_atom(3).set_display_name("")
	page.doc.commit("测试")
	_check(page._drawer.badge.text == "! 1 警告", "A missing node name shows a warning badge: " + page._drawer.badge.text)
	page._step_history(true)
	page._view.disconnection_request.emit(&"1", 0, &"2", 0)
	_check(page._drawer.badge.text.begins_with("✕ 1 错误") and page._drawer.badge.get_theme_color("font_color") == GDEditorUi.tone(&"danger"), "Errors show a danger badge: " + page._drawer.badge.text)
	_check(page._view.graph_node(1).get_titlebar_hbox().get_node("Issue").visible, "The node with the error gets a badge")
	page._drawer.hide()
	page._run()
	_check(not page.get_runner().is_running and page._drawer.visible and page._drawer.current_tab == GDGuideDrawer.Tab.ISSUES, "Run with errors opens the 校验 drawer instead of running")
	var rows := page._drawer.row_texts(GDGuideDrawer.Tab.ISSUES)
	_check(rows.size() == page._report.issues.size() and rows[0].contains("入口"), "Drawer lists each issue")
	page._view.select_ids([])
	page._drawer.pick_row(GDGuideDrawer.Tab.ISSUES, 0)
	_check(page._view.selected_ids() == [1], "Clicking an issue selects its node")
	page._step_history(true)
	page._drawer.badge.pressed.emit()
	_check(page._drawer.badge.text == "✓ 校验通过" and not page._drawer.visible, "Undo clears the error; badge toggles the drawer")


func _test_breakpoint_run() -> void:
	print("[breakpoint]")
	_select([3])
	var f9 := InputEventKey.new()
	f9.keycode = KEY_F9
	f9.pressed = true
	page._unhandled_key_input(f9)
	_check(GDGuideRunnerSystem.GuideBreakpoints.contains(graph, 3) and page._view.graph_node(3).get_titlebar_hbox().get_node("Breakpoint").visible, "F9 sets a breakpoint and shows the dot")
	page._run()
	var runner := page.get_runner()
	_check(runner.is_running and page._debug_strip.visible and not page._idle_strip.visible, "Run swaps the toolbar to the debug strip")
	_check(page._drawer.visible and page._drawer.current_tab == GDGuideDrawer.Tab.TRACE, "Starting a run opens the 轨迹 drawer")
	await _frames(2)
	page._host.simulate_click()
	var paused := await _wait_until(func() -> bool: return runner.is_paused)
	_check(paused and runner.active_node_id == 3 and page._debug_strip._continue_btn.visible and not page._debug_strip._pause_btn.visible, "Run pauses at the breakpoint")
	_check(page.is_read_only() and not page._view.graph_node(3).draggable, "Nodes are read-only while running")
	var cursor := page.doc._cursor
	page._step_history(true)
	_check(page.doc._cursor == cursor and last_status.contains("试跑中"), "Undo is held back while running")
	page._debug_strip._continue_btn.pressed.emit()
	await _frames(2)
	_check(runner.is_running and not runner.is_paused and runner.active_node_id == 3, "Continue resumes")
	page._debug_strip._pause_btn.pressed.emit()
	_check(runner.is_paused, "Pause pauses")
	page._debug_strip._step_btn.pressed.emit()
	_check(runner.is_paused, "Step stays paused")
	for btn in page._debug_strip.get_children():
		if btn is Button and btn.tooltip_text.begins_with("结束"):
			btn.pressed.emit()
	await _frames(2)
	_check(not runner.is_running and runner.get_current_exit_reason() == GDGuideData.GuideExitReason.ABORTED, "结束 stops without completing")
	_check(not page._debug_strip.visible and page._idle_strip.visible and not page.is_read_only(), "Toolbar returns to normal after the run")
	page._toggle_breakpoint(3)


func _test_full_run() -> void:
	print("[full run]")
	page._run()
	var runner := page.get_runner()
	await _frames(2)
	page._host.simulate_click()
	await _wait_until(func() -> bool: return runner.active_node_id == 3)
	page._host.simulate_click()
	await _wait_until(func() -> bool: return runner.active_node_id == 4)
	_check(page._debug_strip._status.text.contains("等示例面板"), "Debug status names the active node: " + page._debug_strip._status.text)
	page._debug_strip._signal_edit.text = "SamplePanelReady"
	page._debug_strip._signal_edit.text_submitted.emit("SamplePanelReady")
	await _wait_until(func() -> bool: return runner.active_node_id == 7)
	page._debug_strip._signal_edit.text = "SampleCoinCollected"
	page._debug_strip.send_signal()
	var finished := await _wait_until(func() -> bool: return not runner.is_running)
	_check(finished and runner.get_current_exit_reason() == GDGuideData.GuideExitReason.COMPLETED, "Ticks in _process carry the delay to the exit")
	await _frames(1)
	_check(page._view.graph_node(9).get_meta("phase") == GDGuideData.GuideNodePhase.SUCCEEDED and page._view.graph_node(6).get_meta("phase") == GDGuideData.GuideNodePhase.IDLE, "Node phases are shown after the run")
	_check(page._drawer.row_texts(GDGuideDrawer.Tab.TRACE).size() > 10 and last_status.begins_with("试跑结束"), "Trace and status report the run")
	await _wait_until(func() -> bool: return not page.is_processing(), 3000)
	_check(not page.is_processing(), "Processing stops once the run and pulses are over")
	graph.find_atom(2).set_display_name("欢迎！")
	page.doc.commit("测试")
	_check(page._view.graph_node(2).get_meta("phase") == GDGuideData.GuideNodePhase.IDLE, "Editing clears the run tint")
	page._step_history(true)


func _test_all_atom_inspectors() -> void:
	print("[inspector for every atom type]")
	var g := GDGuideGraphRes.new()
	g.set_graph_id(4400)
	g.set_display_name("全类型")
	var ids := {}
	var descriptors := GDGuideAtoms.get_all_atom_descriptors()
	for i in range(descriptors.size()):
		var type_id := str(descriptors[i]["id"])
		var atom := GDGuideEditing.add_node(g, type_id, Vector2((i % 5) * 260, (i / 5) * 200))
		ids[type_id] = atom.id
	GDGuideEditing.register_in_memory_graph(g)
	page.load_graph(g)
	var expected := {
		"io.guide.entry": ["触发事件", "添加条件"], "io.guide.exit": ["结束原因"], "io.guide.branch": ["添加条件", "来源"],
		"io.guide.subgraph": ["子图"], "io.guide.narration": ["文案", "说话人", "自动继续", "文案位置", "遮罩浓度"],
		"io.guide.lockwait": ["等待什么", "事件", "超时", "文案", "显示跳过", "遮罩浓度"], "io.guide.wait_event": ["事件", "超时"],
		"io.guide.wait_condition": ["检查间隔", "超时", "添加条件"], "io.guide.delay": ["延迟"],
		"io.guide.strong": ["目标类型", "完成方式", "点击方式", "超时", "显示文案", "手指位置", "遮罩浓度", "高亮缩放"],
		"io.guide.weak": ["目标类型", "完成方式", "超时", "显示文案", "手指位置", "显示箭头", "高亮缩放"],
		"io.guide.dialogue": ["文案", "说话人", "遮罩浓度", "目标类型"], "io.guide.list_focus": ["超时", "目标类型"],
		"io.guide.checkpoint": ["检查点"], "io.guide.complete": [],
	}
	for desc in descriptors:
		var type_id := str(desc["id"])
		var node_id: int = ids[type_id]
		_select([node_id])
		var rows := _rows()
		var labels: Array = expected.get(type_id, [])
		var missing: Array = labels.filter(func(l: String) -> bool: return not rows.has(l) and not _buttons().has(l))
		_check(rows.has("节点名") and rows.has("超时后结束") and missing.is_empty(), "%s inspector builds every field %s" % [type_id, missing])
		_write("节点名", "节点%d" % node_id)
		_check(g.find_atom(node_id).display_name == "节点%d" % node_id and page._view.graph_node(node_id).title == "节点%d" % node_id, "%s rename updates the GraphNode title" % type_id)
		_write_specific(type_id, node_id)
	await _frames(1)

	print("[save + reload all atom types]")
	var path := TMP_DIR.path_join("Guide_all.tres")
	_check(page.doc.save(path) == OK, "Saved all atom types to user://")
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDGuideGraphRes
	_check(back != null and back.atoms.size() == g.atoms.size() and back.edges.size() == g.edges.size(), "Reloaded graph keeps atoms and edges")
	var same := back != null
	for atom in g.atoms:
		var other := back.find_atom(atom.id) if back != null else null
		var a_data: Dictionary = GDGuideGraphRes.codec().encode(atom)
		var b_data: Dictionary = GDGuideGraphRes.codec().encode(other) if other != null else {}
		if atom is GDGuideAtoms.SubgraphAtom:
			## 子图是嵌入的资源，重新加载后是新对象，只比较它是哪张图。
			same = same and other.graph is GDGuideGraphRes and other.graph.graph_id == atom.graph.graph_id
			a_data.erase("graph")
			b_data.erase("graph")
		if a_data != b_data:
			print("    differs: ", a_data, " vs ", b_data)
		same = same and other != null and a_data == b_data
	_check(same, "Every atom deep-equals after reload (written fields included)")
	_check(back != null and (back.find_atom(ids["io.guide.delay"]) as GDGuideAtoms.DelayAtom).delay_sec == 2.5 and (back.find_atom(ids["io.guide.entry"]) as GDGuideAtoms.EntryAtom).conditions.size() == 1, "Written values survive (delay, entry conditions)")


func _write_specific(type_id: String, node_id: int) -> void:
	var g := graph
	var atom := func() -> GDGuideAtoms.GuideAtom: return g.find_atom(node_id)
	match type_id:
		"io.guide.entry":
			_write("触发事件", "LevelUp:3")
			_buttons()["添加条件"].pressed.emit()
			var entry: GDGuideAtoms.EntryAtom = atom.call()
			_check(entry.trigger_event.event_name == "LevelUp" and entry.trigger_event.arg == "3" and entry.conditions.size() == 1, "entry: trigger event and a condition row")
			var ops: OptionButton = _rows()["比较"]
			_check(ops.item_count == 2, "Bool conditions only offer 等于 / 不等于")
			_write("条件", GDGuideInspector._condition_ids(page._host.conditions).find("io.guide.player_level"))
			_check(entry.conditions[0].left.condition_id == "io.guide.player_level" and entry.conditions[0].right.value.type == GDGuideData.GuideValueType.INT, "Changing the condition retypes the right value")
			_write("比较", GDGuideData.GuideCompareOp.GREATER_OR_EQUAL)
			_write("值", 5)
			_check(entry.conditions[0].op == GDGuideData.GuideCompareOp.GREATER_OR_EQUAL and entry.conditions[0].right.value.int_value == 5 and page._host.conditions.validate_expr(entry.conditions[0]).is_empty(), "Condition row edits are typed and valid")
			_buttons()["删除这行"].pressed.emit()
			_check((atom.call() as GDGuideAtoms.EntryAtom).conditions.is_empty(), "Remove deletes the row")
			page._step_history(true)
			_check((atom.call() as GDGuideAtoms.EntryAtom).conditions.size() == 1 and _buttons().has("删除这行"), "Undo restores the row and rebuilds the form")
		"io.guide.exit":
			_write("结束原因", GDGuideData.GuideExitReason.DEFERRED)
			_check(atom.call().reason == GDGuideData.GuideExitReason.DEFERRED and page._view.graph_node(node_id).get_child(0).text.contains("暂缓"), "exit: reason updates the node summary")
		"io.guide.branch":
			_write("来源", GDGuideData.GuideBranchSource.CHECKPOINT)
			_write("键", "tutorial_done")
			var branch: GDGuideAtoms.BranchAtom = atom.call()
			_check(branch.conditions.size() == 1 and branch.conditions[0].left.condition_id == "io.guide.has_checkpoint" and branch.conditions[0].left.arg.string_value == "tutorial_done", "branch: source regenerates conditions")
		"io.guide.subgraph":
			_write("子图", 1)
			_check(atom.call().graph is GDGuideGraphRes and not page._view.graph_node(node_id).get_child(0).text.contains("未选择"), "subgraph: picks a graph by id")
		"io.guide.narration":
			_write("文案", "你好")
			_write("自动继续", 1.5)
			_check(atom.call().text == "你好" and atom.call().auto_advance_sec == 1.5, "narration: text and auto advance")
		"io.guide.lockwait":
			_write("事件", "PanelOpen")
			_check(atom.call().event_key == "PanelOpen", "lockwait: event key")
			_write("等待什么", GDGuideData.GuideWaitCondition.DELAY)
			var rows := _rows()
			_check(rows.has("延迟") and not rows.has("事件"), "lockwait: mode change shows only the delay field")
			_write("延迟", 2.0)
			_check(atom.call().delay_sec == 2.0 and page._view.graph_node(node_id).get_child(0).text.contains("2.00"), "lockwait: delay shows in the summary")
			_write("等待什么", GDGuideData.GuideWaitCondition.CONDITIONS)
			_check(_buttons().has("添加条件") and not _rows().has("延迟"), "lockwait: condition mode shows the condition list")
		"io.guide.wait_event":
			_write("事件", "CoinGot")
			_write("超时", 8)
			_check(atom.call().event_key == "CoinGot" and atom.call().raw_timeout_sec == 8.0, "wait_event: event and timeout")
		"io.guide.wait_condition":
			_write("检查间隔", 0.5)
			_check(atom.call().interval_sec == 0.5, "wait_condition: interval")
		"io.guide.delay":
			_write("延迟", 2.5)
			_check(atom.call().delay_sec == 2.5 and page._view.graph_node(node_id).get_child(0).text.contains("2.50s"), "delay: setter updates the summary")
		"io.guide.strong":
			_write("目标类型", GDGuideData.GuideTargetKind.UI_WIDGET)
			_write("面板", "Shop")
			_write("控件", "BtnBuy")
			_write("点击方式", GDGuideData.GuideClickMode.CONSUME)
			_check(atom.call().target.format_target() == "Shop/BtnBuy" and atom.call().click_mode == GDGuideData.GuideClickMode.CONSUME, "strong: target and click mode")
			_check(not _rows().has("完成事件") and not _rows().has("说话人"), "strong: mode-dependent fields hidden")
			_write("完成方式", GDGuideData.GuideCompleteMode.EVENT_KEY)
			_write("显示文案", true)
			_check(_rows().has("完成事件") and _rows().has("说话人"), "strong: event and text fields appear")
			_write("完成事件", "Bought")
			_check(atom.call().event_key == "Bought", "strong: completion event")
			_buttons()["转为弱引导"].pressed.emit()
			_check(atom.call() is GDGuideAtoms.WeakGuideAtom and atom.call().target.widget == "BtnBuy" and _buttons().has("转为强引导"), "strong → weak keeps the target and rebuilds the form")
			page._step_history(true)
			_check(atom.call() is GDGuideAtoms.StrongGuideAtom, "Undo converts back")
		"io.guide.weak":
			_write("显示箭头", false)
			_write("手指位置", GDGuideData.GuideAnchor.LEFT)
			_check(not atom.call().show_arrow and atom.call().finger_anchor == GDGuideData.GuideAnchor.LEFT, "weak: arrow and finger anchor")
		"io.guide.dialogue":
			_write("说话人", "向导")
			_write("遮罩浓度", 0.8)
			_check(atom.call().speaker == "向导" and is_equal_approx(atom.call().backdrop_alpha, 0.8), "dialogue: speaker and backdrop")
		"io.guide.list_focus":
			_write("目标类型", GDGuideData.GuideTargetKind.WORLD_ID)
			_write("世界键", "Npc_01")
			_check(atom.call().target.world_key == "Npc_01" and not _rows().has("面板"), "list_focus: world target fields")
		"io.guide.checkpoint":
			_write("检查点", "cp_one")
			_check(atom.call().checkpoint == "cp_one", "checkpoint: name")
		"io.guide.complete":
			var advanced: Variant = _rows().get("超时后结束")
			_write("超时后结束", false)
			_check(advanced != null and not atom.call().exit_on_timeout, "complete: advanced group is editable")
	var outs := 0
	for p in g.find_atom(node_id).get_ports():
		outs += 0 if p.is_input else 1
	if outs > 0 and node_id != graph.atoms[graph.atoms.size() - 1].id:
		var target_id: int = graph.atoms[graph.atoms.size() - 1].id
		var port_label := GDGuideData.GuidePorts.label(g.find_atom(node_id).get_ports().filter(func(p: GDGuideData.GuidePort) -> bool: return not p.is_input)[0].kind)
		_write(port_label, target_id)
		_check(page._view.get_connection_list().any(func(c: Dictionary) -> bool: return c["from_node"] == StringName(str(node_id)) and c["to_node"] == StringName(str(target_id))), "%s: 连线 choice draws the connection" % type_id)


func _test_scan_graphs() -> void:
	print("[scan_graphs]")
	var dir := TMP_DIR.path_join("scan")
	DirAccess.make_dir_recursive_absolute(dir)
	var g := GDGuideGraphRes.new()
	g.set_graph_id(4321)
	g.set_display_name("磁盘上的图")
	g.add_default_skeleton()
	ResourceSaver.save(g, dir.path_join("Guide_4321.tres"))
	_check(GDGuideEditing.find_graph(4321) == null, "Saved graph is not registered yet")
	_check(GDGuideEditing.scan_graphs(dir) == 1 and GDGuideEditing.find_graph(4321) != null and GDGuideEditing.find_graph(4321).display_name == "磁盘上的图", "scan_graphs registers the saved graph")
	_check(GDGuideEditing.scan_graphs(dir) == 0, "Scanning again adds nothing")
	_check(page._suggest_save_path(g) == "res://game_res/guide/Guide_4321.tres", "Save path is res://game_res/guide/Guide_<id>.tres")
	page._list.refresh(page.get_current_graph())
	var texts := PackedStringArray()
	var item := page._list._tree.get_root().get_first_child()
	while item != null:
		texts.append(item.get_text(0))
		item = item.get_next_in_tree()
	_check("磁盘上的图" in texts, "Library shows the scanned graph")


func _test_missing_atoms() -> void:
	print("[missing atoms → read-only]")
	var g := GDGuideGraphRes.new()
	g.graph_id = 5555
	g.codec_data = {
		"atoms": [{"$type": "EntryAtom", "id": 1}, {"$type": "FancyAtom", "id": 2, "editor_position": Vector2(300, 0), "display_name": "神秘"}],
		"edges": [{"$type": "GuideEdge", "from_id": 1, "port": OUT, "to_id": 2}],
	}
	g.next_node_id = 3
	GDGuideEditing.register_in_memory_graph(g)
	page.load_graph(g)
	_check(page._banner.visible and page._banner_label.text == "1 个节点类型缺失，整张图只读", "Banner reports the missing type")
	_check(page.is_read_only() and not page._view.graph_node(1).draggable and page._add_btn.disabled, "Missing atoms make the graph read-only")
	page._view.disconnection_request.emit(&"1", 0, &"2", 0)
	page._view.delete_nodes_request.emit([&"1"])
	_check(g.edges.size() == 1 and g.atoms.size() == 2 and last_status.contains("只读"), "Edits are refused with a reason")
	_select([1])
	var edit: LineEdit = _rows().get("节点名")
	_check(edit != null and not edit.editable, "Inspector fields are locked")
	page._clear_missing()
	_check(g.atoms.size() == 1 and not page._banner.visible and not page.is_read_only(), "清理 removes missing nodes")
	page._step_history(true)
	_check(g.atoms.size() == 2 and page._banner.visible, "Undo brings them back")


func _test_multi_select() -> void:
	print("[multi select]")
	page.load_graph(GDGuideEditing.find_graph(GDGuideSamples.SAMPLE_GRAPH_ID))
	page._view.select_ids([2, 3, 4])
	_check(page._selected_ids.size() == 3 and _find_text(page._form, "已选 3 个节点"), "Multiple selection shows 已选 N 个节点")
	page._view.select_ids([])
	_check(page._selected_ids.is_empty() and _rows().has("图 ID"), "Clearing the selection shows the graph header")


func _find_text(node: Node, text: String) -> bool:
	for child in node.get_children():
		if child is Label and child.text == text:
			return true
		if _find_text(child, text):
			return true
	return false


func _test_exit_tree() -> void:
	print("[exit tree]")
	var runner := page.get_runner()
	root.remove_child(page)
	_check(runner.is_disposed, "Leaving the tree disposes the runner and host")
	page.free()


func _cleanup() -> void:
	for path in [TMP_DIR.path_join("scan/Guide_4321.tres"), TMP_DIR.path_join("Guide_all.tres")]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR.path_join("scan")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))
	GDGuideEditing._in_memory_graphs.clear()
	GDGuideSamples._built.clear()
	GDGuideRunnerSystem.GuideBreakpoints._by_graph.clear()
