@tool
class_name GDGuideData
extends RefCounted

## 新手引导基础数据类型、端口、边、黑板、目标引用、事件引用与条件求值引擎
## 对应 GuidePort / GuideEdge / GuideBlackboard / GuideEventRef / GuideTargetRef / GuideTrigger / GuideConditions / GuideNodePhase / GuideSignal

enum GuidePortKind {
	EXEC_IN = 0,
	EXEC_OUT = 1,
	EXEC_TRUE = 2,
	EXEC_FALSE = 3,
	EXEC_TIMEOUT = 4,
}

enum GuideNodePhase {
	IDLE = 0,
	ENTERING = 1,
	RUNNING = 2,
	WAITING = 3,
	SUCCEEDED = 4,
	FAILED = 5,
	SKIPPED = 6,
	PAUSED = 7,
}

enum GuideExitReason {
	COMPLETED = 0,
	SKIPPED = 1,
	DEFERRED = 2,
	FAILED = 3,
	ABORTED = 4,
}

enum GuideValueType {
	BOOL = 0,
	INT = 1,
	FLOAT = 2,
	STRING = 3,
}

enum GuideCompareOp {
	EQUAL = 0,
	NOT_EQUAL = 1,
	GREATER = 2,
	GREATER_OR_EQUAL = 3,
	LESS = 4,
	LESS_OR_EQUAL = 5,
}

enum GuideOperandKind {
	VALUE = 0,
	CONDITION = 1,
}

enum GuideTargetKind {
	NONE = 0,
	UI_WIDGET = 1,
	WORLD_ID = 2,
	SCREEN_ANCHOR = 3,
}

enum GuideTriggerKind {
	MANUAL = 0,
	EVENT_KEY = 1,
	GRAPH_FINISHED = 2,
}

enum GuideCompleteMode {
	TARGET_CLICK = 0,
	EVENT_KEY = 1,
}

enum GuideWaitCondition {
	EVENT_KEY = 0,
	DELAY = 1,
	PREDICATE = 2,
	CONDITIONS = 3,
}

enum GuideBranchSource {
	BLACKBOARD_EQUALS = 0,
	CHECKPOINT = 1,
	PREDICATE = 2,
	NEW_PLAYER = 3,
	LEVEL_AT_LEAST = 4,
}

enum GuideClickMode {
	NONE = 0,
	FORWARD = 1,
	CONSUME = 2,
}

enum GuideAnchor {
	AUTO = 0,
	TOP = 1,
	BOTTOM = 2,
	LEFT = 3,
	RIGHT = 4,
	CENTER = 5,
	NONE = 6,
}

enum GuideSkipButton {
	HIDDEN = 0,
	SKIP = 1,
	DEFER = 2,
}

enum GuideTraceKind {
	RUN_STARTED = 0,
	PHASE = 1,
	EDGE = 2,
	LOG = 3,
	WARNING = 4,
	RUN_FINISHED = 5,
}

enum GuideDebugCommandKind {
	PAUSE = 0,
	CONTINUE = 1,
	STEP_ONCE = 2,
	SKIP_NODE = 3,
	RESTART_FROM = 4,
	SET_BREAKPOINT = 5,
	CLEAR_BREAKPOINT = 6,
	STOP = 7,
}


# ─────────────────────── GuidePorts ───────────────────────

class GuidePort extends RefCounted:
	var kind: int = GuidePortKind.EXEC_IN
	var required: bool = false

	func _init(p_kind: int = GuidePortKind.EXEC_IN, p_required: bool = false) -> void:
		kind = p_kind
		required = p_required

	var is_input: bool:
		get:
			return kind == GuidePortKind.EXEC_IN


class GuidePorts extends RefCounted:
	static func exec_in() -> GuidePort: return GuidePort.new(GuidePortKind.EXEC_IN, false)
	static func exec_out() -> GuidePort: return GuidePort.new(GuidePortKind.EXEC_OUT, true)
	static func exec_true() -> GuidePort: return GuidePort.new(GuidePortKind.EXEC_TRUE, true)
	static func exec_false() -> GuidePort: return GuidePort.new(GuidePortKind.EXEC_FALSE, true)
	static func exec_timeout() -> GuidePort: return GuidePort.new(GuidePortKind.EXEC_TIMEOUT, false)

	static func exec_in_out() -> Array[GuidePort]:
		return [exec_in(), exec_out()]

	static func in_out_timeout() -> Array[GuidePort]:
		return [exec_in(), exec_out(), exec_timeout()]

	static func entry_only() -> Array[GuidePort]:
		return [exec_out()]

	static func exit_only() -> Array[GuidePort]:
		return [exec_in()]

	static func branch() -> Array[GuidePort]:
		return [exec_in(), exec_true(), exec_false()]

	static func is_output(kind: int) -> bool:
		return kind != GuidePortKind.EXEC_IN

	static func label(kind: int) -> String:
		match kind:
			GuidePortKind.EXEC_IN: return "进入"
			GuidePortKind.EXEC_OUT: return "下一步"
			GuidePortKind.EXEC_TRUE: return "是"
			GuidePortKind.EXEC_FALSE: return "否"
			GuidePortKind.EXEC_TIMEOUT: return "超时"
			_: return str(kind)


# ─────────────────────── GuideEdge ───────────────────────

class GuideEdge extends Resource:
	@export var from_id: int = 0
	@export var port: int = GuidePortKind.EXEC_OUT
	@export var to_id: int = 0

	func _init(p_from_id: int = 0, p_port: int = GuidePortKind.EXEC_OUT, p_to_id: int = 0) -> void:
		from_id = p_from_id
		port = p_port
		to_id = p_to_id

	static func compare(a: GuideEdge, b: GuideEdge) -> bool:
		if a.from_id != b.from_id:
			return a.from_id < b.from_id
		if a.port != b.port:
			return a.port < b.port
		return a.to_id < b.to_id

	func equals_edge(other: GuideEdge) -> bool:
		return other != null and from_id == other.from_id and port == other.port and to_id == other.to_id

	func format_edge() -> String:
		return "#%d.%s -> #%d" % [from_id, GuidePorts.label(port), to_id]


# ─────────────────────── GuideSignalKeys & GuideEventRef ───────────────────────

class GuideSignalKeys extends RefCounted:
	const SEPARATOR := ":"

	static func compose(key: String, arg: String = "") -> String:
		if key == null or key.is_empty():
			return ""
		return key if (arg == null or arg.is_empty()) else (key + SEPARATOR + arg)

	static func split(full_key: String) -> Dictionary:
		if full_key == null or full_key.is_empty():
			return {"key": "", "arg": ""}
		var idx := full_key.find(SEPARATOR)
		if idx < 0:
			return {"key": full_key, "arg": ""}
		return {"key": full_key.substr(0, idx), "arg": full_key.substr(idx + 1)}

	static func matches(published: String, expected: String) -> bool:
		if published == null or published.is_empty() or expected == null or expected.is_empty():
			return false
		if expected.find(SEPARATOR) >= 0:
			return published == expected
		if published.length() == expected.length():
			return published == expected
		return published.length() > expected.length() \
			and published[expected.length()] == SEPARATOR \
			and published.begins_with(expected)


class GuideEventRef extends Resource:
	@export var event_name: String = ""
	@export var arg: String = ""

	var key: String:
		get:
			return GuideSignalKeys.compose(event_name, arg)

	var is_empty: bool:
		get:
			return event_name == null or event_name.is_empty()

	func _init(p_name: String = "", p_arg: String = "") -> void:
		event_name = p_name if p_name != null else ""
		arg = p_arg if p_arg != null else ""

	static func parse(full_key: String) -> GuideEventRef:
		if full_key == null or full_key.is_empty():
			return GuideEventRef.new()
		var sp := GuideSignalKeys.split(full_key)
		return GuideEventRef.new(str(sp["key"]), str(sp["arg"]))


# ─────────────────────── GuideTargetRef & GuideTrigger & GuideBlackboard ───────────────────────

class GuideTargetRef extends Resource:
	@export var kind: int = GuideTargetKind.NONE
	@export var panel: String = ""
	@export var widget: String = ""
	@export var world_key: String = ""
	@export var rule: String = ""
	@export var wait_panel: String = ""

	func _init(
		p_kind: int = GuideTargetKind.NONE,
		p_panel: String = "",
		p_widget: String = "",
		p_world_key: String = "",
		p_rule: String = "",
		p_wait_panel: String = ""
	) -> void:
		kind = p_kind
		panel = p_panel if p_panel != null else ""
		widget = p_widget if p_widget != null else ""
		world_key = p_world_key if p_world_key != null else ""
		rule = p_rule if p_rule != null else ""
		wait_panel = p_wait_panel if p_wait_panel != null else ""

	static func ui(p_panel: String, p_widget: String) -> GuideTargetRef:
		return GuideTargetRef.new(GuideTargetKind.UI_WIDGET, p_panel, p_widget)

	var is_none: bool:
		get:
			return kind == GuideTargetKind.NONE

	var gate_panel: String:
		get:
			return wait_panel if not wait_panel.is_empty() else panel

	func format_target() -> String:
		var rule_sfx := "" if rule.is_empty() else (" [%s]" % rule)
		match kind:
			GuideTargetKind.NONE:
				return "无目标"
			GuideTargetKind.UI_WIDGET:
				var joined := widget if panel.is_empty() else (panel if widget.is_empty() else (panel + "/" + widget))
				return joined + rule_sfx
			GuideTargetKind.WORLD_ID:
				return "世界:" + world_key + rule_sfx
			GuideTargetKind.SCREEN_ANCHOR:
				return "锚点:" + widget
			_:
				return str(kind)


class GuideTrigger extends Resource:
	@export var kind: int = GuideTriggerKind.MANUAL
	@export var event_key: String = ""
	@export var pre_graph_ids: PackedInt32Array = PackedInt32Array()
	@export var min_level: int = 0
	@export var max_level: int = 0
	@export var new_player_only: bool = false


class GuideBlackboard extends RefCounted:
	var _values: Dictionary = {} # String -> String

	var count: int:
		get:
			return _values.size()

	var values: Dictionary:
		get:
			return _values

	func try_get(key: String) -> Dictionary:
		if key == null or key.is_empty() or not _values.has(key):
			return {"ok": false, "value": ""}
		return {"ok": true, "value": str(_values[key])}

	func set_value(key: String, val: String) -> void:
		if key == null or key.is_empty():
			return
		_values[key] = val if val != null else ""

	func remove(key: String) -> bool:
		return not (key == null or key.is_empty()) and _values.erase(key)

	func clear() -> void:
		_values.clear()


# ─────────────────────── GuideConditions & Evaluator ───────────────────────

class GuideValue extends Resource:
	@export var type: int = GuideValueType.BOOL
	@export var bool_value: bool = false
	@export var int_value: int = 0
	@export var float_value: float = 0.0
	@export var string_value: String = ""

	static func from_bool(v: bool) -> GuideValue:
		var gv := GuideValue.new()
		gv.type = GuideValueType.BOOL
		gv.bool_value = v
		return gv

	static func from_int(v: int) -> GuideValue:
		var gv := GuideValue.new()
		gv.type = GuideValueType.INT
		gv.int_value = v
		return gv

	static func from_float(v: float) -> GuideValue:
		var gv := GuideValue.new()
		gv.type = GuideValueType.FLOAT
		gv.float_value = v
		return gv

	static func from_string(v: String) -> GuideValue:
		var gv := GuideValue.new()
		gv.type = GuideValueType.STRING
		gv.string_value = v if v != null else ""
		return gv

	var is_numeric: bool:
		get:
			return type == GuideValueType.INT or type == GuideValueType.FLOAT

	var number: float:
		get:
			return float(int_value) if type == GuideValueType.INT else float_value

	func format_value() -> String:
		match type:
			GuideValueType.BOOL: return "是" if bool_value else "否"
			GuideValueType.INT: return str(int_value)
			GuideValueType.FLOAT: return str(float_value)
			_: return string_value if string_value != null else ""


class GuideConditionCall extends Resource:
	@export var condition_id: String = ""
	@export var arg: GuideValue = GuideValue.new()

	func _init(p_id: String = "", p_arg: GuideValue = null) -> void:
		condition_id = p_id if p_id != null else ""
		arg = p_arg if p_arg != null else GuideValue.new()


class GuideOperand extends Resource:
	@export var kind: int = GuideOperandKind.VALUE
	@export var value: GuideValue = GuideValue.new()
	@export var condition: GuideConditionCall = GuideConditionCall.new()


class GuideConditionExpr extends Resource:
	@export var left: GuideConditionCall = GuideConditionCall.new()
	@export var op: int = GuideCompareOp.EQUAL
	@export var right: GuideOperand = GuideOperand.new()

	static func create_compare(p_id: String, p_arg: GuideValue, p_op: int, p_right_val: GuideValue) -> GuideConditionExpr:
		var expr := GuideConditionExpr.new()
		expr.left = GuideConditionCall.new(p_id, p_arg)
		expr.op = p_op
		expr.right = GuideOperand.new()
		expr.right.kind = GuideOperandKind.VALUE
		expr.right.value = p_right_val if p_right_val != null else GuideValue.new()
		return expr


class GuideConditionResult extends RefCounted:
	var satisfied: bool = false
	var error: String = ""
	var left: GuideValue = null
	var right: GuideValue = null
	var has_values: bool = false

	var success: bool:
		get:
			return error.is_empty()

	func _init(
		p_satisfied: bool = false,
		p_error: String = "",
		p_left: GuideValue = null,
		p_right: GuideValue = null,
		p_has_values: bool = false
	) -> void:
		satisfied = p_satisfied
		error = p_error if p_error != null else ""
		left = p_left
		right = p_right
		has_values = p_has_values

	func describe() -> String:
		if not error.is_empty():
			return error
		var prefix := ""
		if has_values and left != null and right != null:
			prefix = "左侧实际值：%s；右侧实际值：%s；" % [left.format_value(), right.format_value()]
		return prefix + ("满足" if satisfied else "未满足")


class GuideConditionEvaluator extends RefCounted:
	static func compare_values(left: GuideValue, op: int, right: GuideValue) -> GuideConditionResult:
		if op < GuideCompareOp.EQUAL or op > GuideCompareOp.LESS_OR_EQUAL:
			return GuideConditionResult.new(false, "未知操作符")
		if left == null or right == null:
			return GuideConditionResult.new(false, "比较参数为空")

		var equal := false
		var order := 0
		if left.is_numeric and right.is_numeric:
			if is_nan(left.number) or is_inf(left.number) or is_nan(right.number) or is_inf(right.number):
				return GuideConditionResult.new(false, "条件数值必须有限")
			if left.type == GuideValueType.INT and right.type == GuideValueType.INT:
				equal = left.int_value == right.int_value
			else:
				var tol := maxf(0.000001 * maxf(absf(left.number), absf(right.number)), 1e-7)
				equal = absf(left.number - right.number) <= tol
			order = -1 if left.number < right.number else (1 if left.number > right.number else 0)
		else:
			if left.type != right.type:
				return GuideConditionResult.new(false, "左右类型不匹配")
			if op != GuideCompareOp.EQUAL and op != GuideCompareOp.NOT_EQUAL:
				return GuideConditionResult.new(false, "布尔和字符串只支持等于或不等于")
			if left.type == GuideValueType.BOOL:
				equal = left.bool_value == right.bool_value
			elif left.type == GuideValueType.STRING:
				equal = (left.string_value if left.string_value != null else "") == (right.string_value if right.string_value != null else "")
			else:
				return GuideConditionResult.new(false, "未知值类型")

		match op:
			GuideCompareOp.EQUAL: return GuideConditionResult.new(equal)
			GuideCompareOp.NOT_EQUAL: return GuideConditionResult.new(not equal)
			GuideCompareOp.GREATER: return GuideConditionResult.new(order > 0)
			GuideCompareOp.GREATER_OR_EQUAL: return GuideConditionResult.new(order >= 0)
			GuideCompareOp.LESS: return GuideConditionResult.new(order < 0)
			_: return GuideConditionResult.new(order <= 0)


# ─────────────────────── GuideSignal ───────────────────────

class GuideSignal extends RefCounted:
	var phase: int = GuideNodePhase.RUNNING
	var out_port: int = GuidePortKind.EXEC_OUT
	var log: String = ""
	var stalled: bool = false
	var ends_graph: bool = false
	var exit_reason: int = GuideExitReason.COMPLETED

	func _init(
		p_phase: int = GuideNodePhase.RUNNING,
		p_out_port: int = GuidePortKind.EXEC_OUT,
		p_log: String = "",
		p_stalled: bool = false,
		p_ends_graph: bool = false,
		p_exit_reason: int = GuideExitReason.COMPLETED
	) -> void:
		phase = p_phase
		out_port = p_out_port
		log = p_log if p_log != null else ""
		stalled = p_stalled
		ends_graph = p_ends_graph
		exit_reason = p_exit_reason

	var leaves_node: bool:
		get:
			return ends_graph or phase == GuideNodePhase.SUCCEEDED or phase == GuideNodePhase.SKIPPED or phase == GuideNodePhase.FAILED

	static func running(p_log: String = "") -> GuideSignal:
		return GuideSignal.new(GuideNodePhase.RUNNING, GuidePortKind.EXEC_OUT, p_log, false, false, GuideExitReason.COMPLETED)

	static func waiting(p_log: String = "") -> GuideSignal:
		return GuideSignal.new(GuideNodePhase.WAITING, GuidePortKind.EXEC_OUT, p_log, false, false, GuideExitReason.COMPLETED)

	static func stall(p_log: String = "") -> GuideSignal:
		return GuideSignal.new(GuideNodePhase.WAITING, GuidePortKind.EXEC_OUT, p_log, true, false, GuideExitReason.COMPLETED)

	static func succeed(p_port: int = GuidePortKind.EXEC_OUT, p_log: String = "") -> GuideSignal:
		return GuideSignal.new(GuideNodePhase.SUCCEEDED, p_port, p_log, false, false, GuideExitReason.COMPLETED)

	static func skip(p_port: int = GuidePortKind.EXEC_OUT, p_log: String = "") -> GuideSignal:
		return GuideSignal.new(GuideNodePhase.SKIPPED, p_port, p_log, false, false, GuideExitReason.COMPLETED)

	static func fail(p_log: String) -> GuideSignal:
		return GuideSignal.new(GuideNodePhase.FAILED, GuidePortKind.EXEC_OUT, p_log, false, false, GuideExitReason.FAILED)

	static func end_graph(p_reason: int, p_log: String = "") -> GuideSignal:
		return GuideSignal.new(GuideNodePhase.SUCCEEDED, GuidePortKind.EXEC_OUT, p_log, false, true, p_reason)
