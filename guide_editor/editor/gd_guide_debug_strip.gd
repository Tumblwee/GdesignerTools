@tool
class_name GDGuideDebugStrip
extends HBoxContainer

## 试跑时替换工具栏右侧：状态、暂停/继续、单步、跳过此步、结束、发信号、模拟点击。
## 只在有试跑时显示。每次操作后发 acted，页面据此刷新画布。

signal acted
signal said(text: String)

var _host: GDGuideServices.GuideHost = null
var _runner: GDGuideRunnerSystem.GuideRunner = null
var _status: Label = null
var _pause_btn: Button = null
var _continue_btn: Button = null
var _step_btn: Button = null
var _signal_edit: LineEdit = null


func _init() -> void:
	visible = false
	add_theme_constant_override("separation", 2)
	_status = Label.new()
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_status)
	_pause_btn = GDEditorUi.tool_button(&"Pause", "暂停", command.bind(GDGuideData.GuideDebugCommandKind.PAUSE))
	_continue_btn = GDEditorUi.tool_button(&"Play", "继续", command.bind(GDGuideData.GuideDebugCommandKind.CONTINUE))
	_step_btn = GDEditorUi.tool_button(&"DebugStep", "单步", command.bind(GDGuideData.GuideDebugCommandKind.STEP_ONCE))
	var skip := GDEditorUi.tool_button(&"DebugNext", "跳过此步", command.bind(GDGuideData.GuideDebugCommandKind.SKIP_NODE))
	var stop := GDEditorUi.tool_button(&"Stop", "结束，不记完成", command.bind(GDGuideData.GuideDebugCommandKind.STOP))
	GDEditorUi.style_kind(stop, &"danger")
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		stop.add_theme_color_override(state, GDEditorUi.tone(&"danger"))
	for btn in [_pause_btn, _continue_btn, _step_btn, skip, stop]:
		add_child(btn)
	add_child(VSeparator.new())
	_signal_edit = LineEdit.new()
	_signal_edit.placeholder_text = "发送信号"
	_signal_edit.tooltip_text = "事件名，或 事件名:参数，回车发送"
	_signal_edit.custom_minimum_size.x = 120
	_signal_edit.text_submitted.connect(func(_t: String) -> void: send_signal())
	add_child(_signal_edit)
	add_child(GDEditorUi.tool_button(&"ArrowRight", "发送信号", send_signal))
	var click := GDEditorUi.text_button("点击", simulate_click)
	click.flat = true
	click.tooltip_text = "模拟玩家点中当前引导"
	add_child(click)


func bind(host: GDGuideServices.GuideHost, runner: GDGuideRunnerSystem.GuideRunner) -> void:
	_host = host
	_runner = runner


func refresh(graph: GDGuideGraphRes) -> void:
	var snap := _runner.capture_snapshot()
	var atom := graph.find_atom(snap.active_node_id) if graph != null else null
	_status.text = "%s · %s · %.1fs" % ["已暂停" if snap.is_paused else "运行中", atom.title if atom != null else "—", snap.node_elapsed]
	_status.tooltip_text = snap.active_message
	_pause_btn.visible = not snap.is_paused
	_continue_btn.visible = snap.is_paused
	_step_btn.disabled = not snap.is_paused


func command(kind: int) -> void:
	_runner.enqueue_debug_command(kind, 0, GDGuideData.GuideExitReason.ABORTED)
	acted.emit()


func send_signal() -> void:
	var full := _signal_edit.text.strip_edges()
	if full.is_empty():
		return
	var parts := GDGuideData.GuideSignalKeys.split(full)
	_host.signals.publish(str(parts["key"]), str(parts["arg"]))
	said.emit("已发送 %s" % full)
	acted.emit()


func simulate_click() -> void:
	_host.simulate_click()
	acted.emit()
