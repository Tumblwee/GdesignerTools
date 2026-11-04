@tool
class_name GDGuideDrawer
extends VBoxContainer

## 画布下方的抽屉：校验问题 | 试跑轨迹。点一行，页面就选中并居中那个节点。
## 工具栏上的校验徽标也归这里管：它和问题列表显示的是同一份报告，点它开合抽屉。

signal node_picked(node_id: int)

enum Tab { ISSUES, TRACE }

const PHASE_LABELS := {
	GDGuideData.GuideNodePhase.ENTERING: "进入", GDGuideData.GuideNodePhase.RUNNING: "运行",
	GDGuideData.GuideNodePhase.WAITING: "等待", GDGuideData.GuideNodePhase.SUCCEEDED: "完成",
	GDGuideData.GuideNodePhase.FAILED: "失败", GDGuideData.GuideNodePhase.SKIPPED: "跳过",
	GDGuideData.GuideNodePhase.PAUSED: "暂停",
}

var badge: Button = null
var _tabs: TabBar = null
var _issues: ItemList = null
var _trace: ItemList = null
var _clear_btn: Button = null


func _init() -> void:
	visible = false
	custom_minimum_size.y = 150
	add_theme_constant_override("separation", 2)
	var header := HBoxContainer.new()
	add_child(header)
	_tabs = TabBar.new()
	_tabs.clip_tabs = false
	_tabs.add_tab("校验")
	_tabs.add_tab("轨迹")
	_tabs.tab_changed.connect(_show_tab)
	header.add_child(_tabs)
	header.add_child(GDEditorUi.spacer())
	_clear_btn = GDEditorUi.text_button("清空", clear_trace)
	_clear_btn.flat = true
	header.add_child(_clear_btn)
	header.add_child(GDEditorUi.tool_button(&"Close", "收起", hide))
	_issues = _make_list()
	_trace = _make_list()
	_show_tab(Tab.ISSUES)
	badge = Button.new()
	badge.flat = true
	badge.focus_mode = Control.FOCUS_NONE
	badge.tooltip_text = "查看校验问题"
	badge.pressed.connect(toggle_tab.bind(Tab.ISSUES))


var current_tab: int:
	get:
		return _tabs.current_tab


func open_tab(tab: Tab) -> void:
	visible = true
	_tabs.current_tab = tab
	_show_tab(tab)


func toggle_tab(tab: Tab) -> void:
	if visible and _tabs.current_tab == tab:
		hide()
	else:
		open_tab(tab)


func set_issues(report: GDGuideValidation.GuideValidationReport, graph: GDGuideGraphRes) -> void:
	_show_badge(report)
	_issues.clear()
	var count := report.issues.size() if report != null else 0
	_tabs.set_tab_title(Tab.ISSUES, "校验" if count == 0 else "校验  %d" % count)
	if count == 0:
		_add(_issues, "没有问题", 0, &"ok")
		return
	for found in report.issues:
		var atom := graph.find_atom(found.node_id) if graph != null else null
		var where := atom.title if atom != null else ""
		var text := found.message if where.is_empty() or found.message.contains(where) else "%s · %s" % [where, found.message]
		_add(_issues, "%s  %s" % ["✕" if found.is_error else "!", text], found.node_id, &"danger" if found.is_error else &"warn")


func _show_badge(report: GDGuideValidation.GuideValidationReport) -> void:
	badge.visible = report != null
	if report == null:
		return
	var tone := &"ok"
	badge.text = "✓ 校验通过"
	if report.has_errors:
		tone = &"danger"
		badge.text = "✕ %d 错误" % report.error_count + (" · %d 警告" % report.warning_count if report.warning_count > 0 else "")
	elif report.warning_count > 0:
		tone = &"warn"
		badge.text = "! %d 警告" % report.warning_count
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		badge.add_theme_color_override(state, GDEditorUi.tone(tone))


func clear_trace() -> void:
	_trace.clear()
	_tabs.set_tab_title(Tab.TRACE, "轨迹")


## 试跑轨迹的一条记录。点连线那一行跳到目标节点。
func add_event(evt: GDGuideRunnerSystem.GuideTraceEvent, graph: GDGuideGraphRes) -> void:
	var node_id := evt.to_node_id if evt.kind == GDGuideData.GuideTraceKind.EDGE else evt.node_id
	_add(_trace, _event_text(evt, graph), node_id, _event_tone(evt))
	_tabs.set_tab_title(Tab.TRACE, "轨迹  %d" % _trace.item_count)
	_trace.get_v_scroll_bar().value = _trace.get_v_scroll_bar().max_value


func row_texts(tab: Tab) -> PackedStringArray:
	var list := _issues if tab == Tab.ISSUES else _trace
	var texts := PackedStringArray()
	for i in range(list.item_count):
		texts.append(list.get_item_text(i))
	return texts


## 模拟点了某一行（测试和键盘都走这里）。
func pick_row(tab: Tab, index: int) -> void:
	var list := _issues if tab == Tab.ISSUES else _trace
	var node_id := int(list.get_item_metadata(index))
	if node_id > 0:
		node_picked.emit(node_id)


func _make_list() -> ItemList:
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_clicked.connect(func(index: int, _at: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			pick_row(Tab.ISSUES if list == _issues else Tab.TRACE, index)
	)
	add_child(list)
	return list


func _add(list: ItemList, text: String, node_id: int, tone: StringName) -> void:
	var index := list.add_item(text)
	list.set_item_metadata(index, node_id)
	list.set_item_custom_fg_color(index, GDEditorUi.tone(tone))
	list.set_item_tooltip(index, text)


func _show_tab(tab: int) -> void:
	_issues.visible = tab == Tab.ISSUES
	_trace.visible = tab == Tab.TRACE
	_clear_btn.visible = tab == Tab.TRACE


static func _event_text(evt: GDGuideRunnerSystem.GuideTraceEvent, graph: GDGuideGraphRes) -> String:
	var title_of := func(node_id: int) -> String:
		var atom := graph.find_atom(node_id) if graph != null else null
		return atom.title if atom != null else "#%d" % node_id
	var head := "%6.2fs  " % evt.time_since_start
	match evt.kind:
		GDGuideData.GuideTraceKind.RUN_STARTED:
			return head + "开始 · " + evt.message
		GDGuideData.GuideTraceKind.RUN_FINISHED:
			return head + "结束 · " + evt.message.substr(evt.message.find("：") + 1)
		GDGuideData.GuideTraceKind.EDGE:
			return head + "%s ─%s→ %s" % [title_of.call(evt.node_id), GDGuideData.GuidePorts.label(evt.port), title_of.call(evt.to_node_id)]
		GDGuideData.GuideTraceKind.PHASE:
			return head + "%s · %s%s" % [title_of.call(evt.node_id), PHASE_LABELS.get(evt.phase, str(evt.phase)), "" if evt.message.is_empty() else " · " + evt.message]
	return head + "%s · %s" % [title_of.call(evt.node_id), evt.message]


static func _event_tone(evt: GDGuideRunnerSystem.GuideTraceEvent) -> StringName:
	if evt.kind == GDGuideData.GuideTraceKind.WARNING or evt.phase == GDGuideData.GuideNodePhase.PAUSED:
		return &"warn"
	if evt.phase == GDGuideData.GuideNodePhase.FAILED:
		return &"danger"
	if evt.kind in [GDGuideData.GuideTraceKind.RUN_STARTED, GDGuideData.GuideTraceKind.RUN_FINISHED]:
		return &"accent"
	return &"text" if evt.kind == GDGuideData.GuideTraceKind.EDGE else &"muted"
