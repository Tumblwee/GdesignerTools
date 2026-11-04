@tool
class_name GDGuideAtoms
extends RefCounted

## 新手引导全部节点原子（GuideAtom 基类 + MissingAtom + 15 种内置原子）

const CATEGORY_FLOW := "流程"
const CATEGORY_GUIDE := "引导"
const CATEGORY_WAIT := "等待"


# ─────────────────────── GuideAtom Base ───────────────────────

class GuideAtom extends Resource:
	@export var id: int = 0
	@export var editor_position: Vector2 = Vector2.ZERO
	@export var display_name: String = ""
	@export var exit_on_timeout: bool = true
	@export var exit_on_condition_fail: bool = true

	var title: String:
		get:
			return display_name if not display_name.is_empty() else get_atom_display_name()

	func get_atom_id() -> String:
		return "io.guide.base"

	func get_atom_display_name() -> String:
		return "GuideAtom"

	func get_atom_category() -> String:
		return CATEGORY_FLOW

	func get_ports() -> Array[GDGuideData.GuidePort]:
		return GDGuideData.GuidePorts.exec_in_out()

	func get_conditions() -> Array[GDGuideData.GuideConditionExpr]:
		return []

	func _get_completes_on_enter() -> bool:
		return false

	func _get_is_resume_point() -> bool:
		return true

	func _get_timeout_sec() -> float:
		return -1.0

	func _get_blocks_input() -> bool:
		return false

	func _get_summary() -> String:
		return ""

	var completes_on_enter: bool:
		get:
			return _get_completes_on_enter()

	var is_resume_point: bool:
		get:
			return _get_is_resume_point()

	var timeout_sec: float:
		get:
			return _get_timeout_sec()

	var blocks_input: bool:
		get:
			return _get_blocks_input()

	var summary: String:
		get:
			return _get_summary()

	func set_exit_policies(p_timeout: bool, p_cond_fail: bool) -> void:
		exit_on_timeout = p_timeout
		exit_on_condition_fail = p_cond_fail

	func set_display_name(p_name: String) -> void:
		display_name = p_name if p_name != null else ""

	func assign_id(p_id: int) -> void:
		id = p_id

	func assign_editor_position(p_pos: Vector2) -> void:
		editor_position = p_pos

	func has_port(kind: int) -> bool:
		return try_get_port(kind).get("ok", false)

	func try_get_port(kind: int) -> Dictionary:
		for p in get_ports():
			if p.kind == kind:
				return {"ok": true, "port": p}
		return {"ok": false, "port": null}

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		return tick(ctx, 0.0)

	func tick(_ctx: RefCounted, _dt: float) -> GDGuideData.GuideSignal:
		return GDGuideData.GuideSignal.running()

	func exit(_ctx: RefCounted) -> void:
		pass

	func validate(_vctx: RefCounted) -> void:
		pass


# ─────────────────────── MissingAtom ───────────────────────

class MissingAtom extends GuideAtom:
	@export var type_name: String = ""
	@export var reference_id: int = 0
	var _dynamic_ports: Array[GDGuideData.GuidePort] = [GDGuideData.GuidePorts.exec_in()]

	func get_atom_id() -> String: return "io.guide.missing"
	func get_atom_display_name() -> String: return "缺失类型"
	func get_ports() -> Array[GDGuideData.GuidePort]: return _dynamic_ports
	func _get_is_resume_point() -> bool: return false
	func _get_summary() -> String: return "缺失类型：" + type_name

	static func create_placeholder(
		node_id: int,
		pos: Vector2,
		p_display_name: String,
		p_type_name: String,
		p_ref_id: int,
		out_ports: Array
	) -> MissingAtom:
		var atom := MissingAtom.new()
		atom.type_name = p_type_name
		atom.reference_id = p_ref_id
		atom.assign_id(node_id)
		atom.assign_editor_position(pos)
		atom.set_display_name(p_display_name)
		var pts: Array[GDGuideData.GuidePort] = [GDGuideData.GuidePorts.exec_in()]
		if out_ports != null:
			for k in out_ports:
				var kind := int(k)
				if GDGuideData.GuidePorts.is_output(kind):
					var exists := false
					for ep in pts:
						if ep.kind == kind:
							exists = true
							break
					if not exists:
						pts.append(GDGuideData.GuidePort.new(kind, false))
		atom._dynamic_ports = pts
		return atom

	func enter(_ctx: RefCounted) -> GDGuideData.GuideSignal:
		return GDGuideData.GuideSignal.fail("节点类型缺失：" + type_name)

	func validate(vctx: RefCounted) -> void:
		vctx.call("add_error", "node.missing_type", "节点类型缺失：%s。恢复这个类或在编辑器里清理缺失节点" % type_name)


# ─────────────────────── 1. EntryAtom ───────────────────────

class EntryAtom extends GuideAtom:
	@export var trigger_event: GDGuideData.GuideEventRef = GDGuideData.GuideEventRef.new()
	@export var conditions: Array[GDGuideData.GuideConditionExpr] = []

	func get_atom_id() -> String: return "io.guide.entry"
	func get_atom_display_name() -> String: return "入口"
	func get_atom_category() -> String: return CATEGORY_FLOW
	func get_ports() -> Array[GDGuideData.GuidePort]: return GDGuideData.GuidePorts.entry_only()
	func get_conditions() -> Array[GDGuideData.GuideConditionExpr]: return conditions
	func _get_completes_on_enter() -> bool: return true
	func _get_is_resume_point() -> bool: return false
	func _get_summary() -> String:
		return "手动启动" if (trigger_event == null or trigger_event.is_empty) else ("触发：" + trigger_event.key)

	func set_trigger_event(val: GDGuideData.GuideEventRef) -> void:
		trigger_event = val if val != null else GDGuideData.GuideEventRef.new()

	func set_conditions(vals: Array) -> void:
		conditions.clear()
		if vals != null:
			for v in vals:
				if v is GDGuideData.GuideConditionExpr:
					conditions.append(v)

	func enter(_ctx: RefCounted) -> GDGuideData.GuideSignal:
		return GDGuideData.GuideSignal.succeed()


# ─────────────────────── 2. ExitAtom ───────────────────────

class ExitAtom extends GuideAtom:
	@export var reason: int = GDGuideData.GuideExitReason.COMPLETED

	func get_atom_id() -> String: return "io.guide.exit"
	func get_atom_display_name() -> String: return "出口"
	func get_atom_category() -> String: return CATEGORY_FLOW
	func get_ports() -> Array[GDGuideData.GuidePort]: return GDGuideData.GuidePorts.exit_only()
	func _get_completes_on_enter() -> bool: return true
	func _get_is_resume_point() -> bool: return false
	func _get_summary() -> String: return exit_reason_label(reason)

	func set_reason(p_reason: int) -> void:
		reason = p_reason

	func enter(_ctx: RefCounted) -> GDGuideData.GuideSignal:
		return GDGuideData.GuideSignal.end_graph(reason, "到达出口「%s」（%s）" % [title, exit_reason_label(reason)])

	func validate(vctx: RefCounted) -> void:
		if reason == GDGuideData.GuideExitReason.ABORTED:
			vctx.call("add_error", "exit.aborted", "出口的结束原因不能是「中止」，中止只给调试和宿主强停用")

	static func exit_reason_label(r: int) -> String:
		match r:
			GDGuideData.GuideExitReason.COMPLETED: return "完成"
			GDGuideData.GuideExitReason.SKIPPED: return "跳过"
			GDGuideData.GuideExitReason.DEFERRED: return "暂缓"
			GDGuideData.GuideExitReason.FAILED: return "失败"
			GDGuideData.GuideExitReason.ABORTED: return "中止"
			_: return str(r)


# ─────────────────────── 3. BranchAtom ───────────────────────

class BranchAtom extends GuideAtom:
	@export var source: int = GDGuideData.GuideBranchSource.BLACKBOARD_EQUALS
	@export var key: String = ""
	@export var value: String = ""
	@export var level: int = 0
	@export var conditions: Array[GDGuideData.GuideConditionExpr] = []

	func get_atom_id() -> String: return "io.guide.branch"
	func get_atom_display_name() -> String: return "条件跳转"
	func get_atom_category() -> String: return CATEGORY_FLOW
	func get_ports() -> Array[GDGuideData.GuidePort]: return GDGuideData.GuidePorts.branch()
	func get_conditions() -> Array[GDGuideData.GuideConditionExpr]: return conditions
	func _get_completes_on_enter() -> bool: return true
	func _get_is_resume_point() -> bool: return false
	func _get_summary() -> String:
		return "全部满足 → 是；否则 → 否" if not conditions.is_empty() else "请配置条件"

	func set_conditions(vals: Array) -> void:
		conditions.clear()
		if vals != null:
			for v in vals:
				if v is GDGuideData.GuideConditionExpr:
					conditions.append(v)

	func set_blackboard_equals(p_key: String, p_val: String) -> void:
		source = GDGuideData.GuideBranchSource.BLACKBOARD_EQUALS
		key = p_key
		value = p_val
		set_conditions([
			GDGuideData.GuideConditionExpr.create_compare("io.guide.blackboard_has_key", GDGuideData.GuideValue.from_string(p_key), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_bool(true)),
			GDGuideData.GuideConditionExpr.create_compare("io.guide.blackboard", GDGuideData.GuideValue.from_string(p_key), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_string(p_val)),
		])

	func set_checkpoint(cp_name: String) -> void:
		source = GDGuideData.GuideBranchSource.CHECKPOINT
		key = cp_name
		set_conditions([
			GDGuideData.GuideConditionExpr.create_compare("io.guide.has_checkpoint", GDGuideData.GuideValue.from_string(cp_name), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_bool(true))
		])

	func set_predicate(p_key: String, p_arg: String = "") -> void:
		source = GDGuideData.GuideBranchSource.PREDICATE
		key = p_key
		value = p_arg
		set_conditions([
			GDGuideData.GuideConditionExpr.create_compare("io.guide.host_predicate", GDGuideData.GuideValue.from_string(GDGuideData.GuideSignalKeys.compose(p_key, p_arg)), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_bool(true))
		])

	func set_new_player() -> void:
		source = GDGuideData.GuideBranchSource.NEW_PLAYER
		set_conditions([
			GDGuideData.GuideConditionExpr.create_compare("io.guide.is_new_player", GDGuideData.GuideValue.new(), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_bool(true))
		])

	func set_level_at_least(p_level: int) -> void:
		source = GDGuideData.GuideBranchSource.LEVEL_AT_LEAST
		level = maxi(0, p_level)
		set_conditions([
			GDGuideData.GuideConditionExpr.create_compare("io.guide.player_level", GDGuideData.GuideValue.new(), GDGuideData.GuideCompareOp.GREATER_OR_EQUAL, GDGuideData.GuideValue.from_int(level))
		])

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		if not conditions.is_empty():
			var evaluated: GDGuideData.GuideConditionResult = ctx.call("evaluate_conditions", conditions)
			if not evaluated.success:
				return GDGuideData.GuideSignal.fail(evaluated.error)
			var out_p := GDGuideData.GuidePortKind.EXEC_TRUE if evaluated.satisfied else GDGuideData.GuidePortKind.EXEC_FALSE
			return GDGuideData.GuideSignal.succeed(out_p, "条件全部满足=%s → %s" % [str(evaluated.satisfied), "是" if evaluated.satisfied else "否"])
		return GDGuideData.GuideSignal.fail("条件列表为空，请至少配置一行条件")

	func validate(vctx: RefCounted) -> void:
		if not conditions.is_empty():
			for row in conditions:
				var cid := row.left.condition_id if (row != null and row.left != null) else ""
				if cid in ["io.guide.blackboard", "io.guide.has_checkpoint", "io.guide.host_predicate"]:
					if row.left.arg == null or row.left.arg.string_value.is_empty():
						vctx.call("add_error", "branch.no_key", "兼容条件缺少键")
			return
		vctx.call("add_error", "condition.empty", "请至少配置一行条件")


# ─────────────────────── 4. NarrationAtom ───────────────────────

class NarrationAtom extends GuideAtom:
	@export_multiline var text: String = ""
	@export var speaker: String = ""
	@export var text_anchor: int = GDGuideData.GuideAnchor.AUTO
	@export var backdrop_alpha: float = 0.5
	@export var auto_advance_sec: float = 0.0

	func get_atom_id() -> String: return "io.guide.narration"
	func get_atom_display_name() -> String: return "旁白"
	func get_atom_category() -> String: return CATEGORY_GUIDE
	func _get_summary() -> String:
		return text.substr(0, 18) if text != null else ""

	func set_text(p_text: String, p_speaker: String = "") -> void:
		text = p_text if p_text != null else ""
		speaker = p_speaker if p_speaker != null else ""

	func set_auto_advance(seconds: float) -> void:
		auto_advance_sec = maxf(0.0, seconds)

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func tick(ctx: RefCounted, _dt: float) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func _evaluate(ctx: RefCounted) -> GDGuideData.GuideSignal:
		var st: Dictionary = ctx.call("get_node_state")
		if bool(st.get("presented", false)) and bool(ctx.call("consume_click")):
			return GDGuideData.GuideSignal.succeed(GDGuideData.GuidePortKind.EXEC_OUT, "点击继续")
		if auto_advance_sec > 0.0 and float(ctx.get("node_elapsed")) >= auto_advance_sec:
			return GDGuideData.GuideSignal.succeed(GDGuideData.GuidePortKind.EXEC_OUT, "自动继续")
		st["presented"] = true
		return GDGuideData.GuideSignal.running("等点击继续")

	func validate(vctx: RefCounted) -> void:
		if text == null or text.is_empty():
			vctx.call("add_warning", "narration.no_text", "旁白没有文案")


# ─────────────────────── 5. LockWaitAtom ───────────────────────

class LockWaitAtom extends GuideAtom:
	@export var condition: int = GDGuideData.GuideWaitCondition.EVENT_KEY
	@export var raw_event_key: String = ""
	@export var event_ref: GDGuideData.GuideEventRef = GDGuideData.GuideEventRef.new()
	@export var delay_sec: float = 1.0
	@export var predicate_key: String = ""
	@export var predicate_arg: String = ""
	@export_multiline var text: String = ""
	@export var show_skip: bool = false
	@export var backdrop_alpha: float = 0.0
	@export var raw_timeout_sec: float = 0.0
	@export var conditions: Array[GDGuideData.GuideConditionExpr] = []

	func get_atom_id() -> String: return "io.guide.lockwait"
	func get_atom_display_name() -> String: return "锁屏等待"
	func get_atom_category() -> String: return CATEGORY_WAIT
	func get_ports() -> Array[GDGuideData.GuidePort]: return GDGuideData.GuidePorts.in_out_timeout()
	func get_conditions() -> Array[GDGuideData.GuideConditionExpr]:
		return conditions if condition == GDGuideData.GuideWaitCondition.CONDITIONS else []
	func _get_blocks_input() -> bool: return true
	func _get_timeout_sec() -> float: return raw_timeout_sec
	func _get_completes_on_enter() -> bool:
		return condition == GDGuideData.GuideWaitCondition.DELAY and delay_sec <= 0.0
	var event_key: String:
		get: return event_ref.key if event_ref != null else ""
	func _get_summary() -> String: return _describe()

	func set_event_key(p_key: String) -> void:
		condition = GDGuideData.GuideWaitCondition.EVENT_KEY
		raw_event_key = p_key
		event_ref = GDGuideData.GuideEventRef.parse(p_key)

	func set_delay(p_sec: float) -> void:
		condition = GDGuideData.GuideWaitCondition.DELAY
		delay_sec = maxf(0.0, p_sec)

	func set_conditions(vals: Array) -> void:
		condition = GDGuideData.GuideWaitCondition.CONDITIONS
		conditions.clear()
		if vals != null:
			for v in vals:
				if v is GDGuideData.GuideConditionExpr:
					conditions.append(v)

	func set_text(p_text: String) -> void:
		text = p_text

	func set_timeout(p_timeout: float) -> void:
		raw_timeout_sec = p_timeout

	func migrate_event() -> void:
		event_ref = GDGuideData.GuideEventRef.parse(raw_event_key)

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func tick(ctx: RefCounted, _dt: float) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func _evaluate(ctx: RefCounted) -> GDGuideData.GuideSignal:
		match condition:
			GDGuideData.GuideWaitCondition.EVENT_KEY:
				if bool(ctx.call("try_consume_signal", event_key)):
					return GDGuideData.GuideSignal.succeed(GDGuideData.GuidePortKind.EXEC_OUT, "收到 " + event_key)
			GDGuideData.GuideWaitCondition.DELAY:
				if float(ctx.get("node_elapsed")) >= delay_sec:
					return GDGuideData.GuideSignal.succeed(GDGuideData.GuidePortKind.EXEC_OUT, "延迟到点")
			GDGuideData.GuideWaitCondition.CONDITIONS:
				var res: GDGuideData.GuideConditionResult = ctx.call("evaluate_conditions", conditions)
				if not res.success:
					return GDGuideData.GuideSignal.fail(res.error)
				if res.satisfied:
					return GDGuideData.GuideSignal.succeed()
		return GDGuideData.GuideSignal.waiting(_describe())

	func validate(vctx: RefCounted) -> void:
		if condition == GDGuideData.GuideWaitCondition.EVENT_KEY and event_key.is_empty():
			vctx.call("add_error", "lockwait.no_event_key", "等待条件是「事件键」，但没填事件键")
		if condition == GDGuideData.GuideWaitCondition.CONDITIONS and conditions.is_empty():
			vctx.call("add_error", "condition.empty", "请至少配置一行条件")

	func _describe() -> String:
		match condition:
			GDGuideData.GuideWaitCondition.EVENT_KEY:
				return "等事件 " + (event_key if not event_key.is_empty() else "—")
			GDGuideData.GuideWaitCondition.DELAY:
				return "等 %.2fs" % delay_sec
			GDGuideData.GuideWaitCondition.CONDITIONS:
				return "等条件全部满足"
			_:
				return str(condition)


# ─────────────────────── 6. WaitEventAtom ───────────────────────

class WaitEventAtom extends GuideAtom:
	@export var raw_event_key: String = ""
	@export var event_ref: GDGuideData.GuideEventRef = GDGuideData.GuideEventRef.new()
	@export var raw_timeout_sec: float = 0.0

	func get_atom_id() -> String: return "io.guide.wait_event"
	func get_atom_display_name() -> String: return "等事件"
	func get_atom_category() -> String: return CATEGORY_WAIT
	func get_ports() -> Array[GDGuideData.GuidePort]: return GDGuideData.GuidePorts.in_out_timeout()
	func _get_timeout_sec() -> float: return raw_timeout_sec
	var event_key: String:
		get: return event_ref.key if event_ref != null else ""
	func _get_summary() -> String:
		return "等 " + (event_key if not event_key.is_empty() else "—")

	func set_event_key(p_key: String) -> void:
		raw_event_key = p_key
		event_ref = GDGuideData.GuideEventRef.parse(p_key)

	func set_timeout(p_timeout: float) -> void:
		raw_timeout_sec = p_timeout

	func migrate_event() -> void:
		event_ref = GDGuideData.GuideEventRef.parse(raw_event_key)

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func tick(ctx: RefCounted, _dt: float) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func _evaluate(ctx: RefCounted) -> GDGuideData.GuideSignal:
		if bool(ctx.call("try_consume_signal", event_key)):
			return GDGuideData.GuideSignal.succeed(GDGuideData.GuidePortKind.EXEC_OUT, "收到 " + event_key)
		return GDGuideData.GuideSignal.waiting("等事件 " + event_key)

	func validate(vctx: RefCounted) -> void:
		if event_key.is_empty():
			vctx.call("add_error", "wait_event.no_key", "没填事件键")


# ─────────────────────── 7. ConditionWaitAtom ───────────────────────

class ConditionWaitAtom extends GuideAtom:
	@export var conditions: Array[GDGuideData.GuideConditionExpr] = []
	@export var interval_sec: float = 0.1
	@export var raw_timeout_sec: float = 0.0

	func get_atom_id() -> String: return "io.guide.wait_condition"
	func get_atom_display_name() -> String: return "条件等待"
	func get_atom_category() -> String: return CATEGORY_WAIT
	func get_ports() -> Array[GDGuideData.GuidePort]: return GDGuideData.GuidePorts.in_out_timeout()
	func get_conditions() -> Array[GDGuideData.GuideConditionExpr]: return conditions
	func _get_timeout_sec() -> float: return raw_timeout_sec
	func _get_summary() -> String:
		return "等待 %d 个条件全部满足" % conditions.size()

	func configure(p_conditions: Array, p_timeout: float = 0.0, p_interval: float = 0.1) -> void:
		conditions.clear()
		if p_conditions != null:
			for c in p_conditions:
				if c is GDGuideData.GuideConditionExpr:
					conditions.append(c)
		raw_timeout_sec = p_timeout
		interval_sec = maxf(0.0, p_interval)

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func tick(ctx: RefCounted, dt: float) -> GDGuideData.GuideSignal:
		var st: Dictionary = ctx.call("get_node_state")
		var rem := float(st.get("remaining", 0.0)) - dt
		st["remaining"] = rem
		return _evaluate(ctx) if rem <= 0.0 else GDGuideData.GuideSignal.waiting("等条件满足")

	func _evaluate(ctx: RefCounted) -> GDGuideData.GuideSignal:
		var st: Dictionary = ctx.call("get_node_state")
		st["remaining"] = interval_sec
		var res: GDGuideData.GuideConditionResult = ctx.call("evaluate_conditions", conditions)
		if not res.success:
			return GDGuideData.GuideSignal.fail(res.error)
		return GDGuideData.GuideSignal.succeed() if res.satisfied else GDGuideData.GuideSignal.waiting("等条件满足")

	func validate(vctx: RefCounted) -> void:
		if conditions.is_empty():
			vctx.call("add_error", "condition.empty", "条件等待至少配置一行条件")
		if is_nan(interval_sec) or is_inf(interval_sec) or interval_sec < 0.0:
			vctx.call("add_error", "condition.interval", "检查间隔必须为有限非负数")


# ─────────────────────── 8. DelayAtom ───────────────────────

class DelayAtom extends GuideAtom:
	@export var delay_sec: float = 1.0

	func get_atom_id() -> String: return "io.guide.delay"
	func get_atom_display_name() -> String: return "延迟"
	func get_atom_category() -> String: return CATEGORY_WAIT
	func _get_completes_on_enter() -> bool: return delay_sec <= 0.0
	func _get_summary() -> String: return "%.2fs" % delay_sec

	func set_delay(p_sec: float) -> void:
		delay_sec = maxf(0.0, p_sec)

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func tick(ctx: RefCounted, _dt: float) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func _evaluate(ctx: RefCounted) -> GDGuideData.GuideSignal:
		if float(ctx.get("node_elapsed")) >= delay_sec:
			return GDGuideData.GuideSignal.succeed(GDGuideData.GuidePortKind.EXEC_OUT, "延迟到点")
		return GDGuideData.GuideSignal.waiting("等 %.2fs" % delay_sec)


# ─────────────────────── 9. SubgraphAtom ───────────────────────

class SubgraphAtom extends GuideAtom:
	@export var graph: Resource = null

	func get_atom_id() -> String: return "io.guide.subgraph"
	func get_atom_display_name() -> String: return "子图"
	func get_atom_category() -> String: return CATEGORY_FLOW
	func _get_summary() -> String:
		if graph != null and graph.has_method("get_graph_display_name"):
			return str(graph.call("get_graph_display_name"))
		return "未选择子图"

	func set_graph(p_graph: Resource) -> void:
		graph = p_graph

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		if graph == null:
			return GDGuideData.GuideSignal.fail("子图为空")
		var child_runner: RefCounted = ctx.call("start_subgraph_runner", graph)
		if child_runner == null:
			return GDGuideData.GuideSignal.fail("子图启动失败或递归超过 16 层")
		return _result(child_runner)

	func tick(ctx: RefCounted, dt: float) -> GDGuideData.GuideSignal:
		var st: Dictionary = ctx.call("get_node_state")
		var child_runner: RefCounted = st.get("runner", null)
		if child_runner == null:
			return GDGuideData.GuideSignal.fail("子图会话丢失")
		child_runner.call("tick", dt)
		return _result(child_runner)

	func exit(ctx: RefCounted) -> void:
		var st: Dictionary = ctx.call("get_node_state")
		var child_runner: RefCounted = st.get("runner", null)
		if child_runner != null and child_runner.has_method("dispose"):
			child_runner.call("dispose")

	func validate(vctx: RefCounted) -> void:
		if graph == null:
			vctx.call("add_error", "subgraph.missing", "请选择子图")

	static func _result(child_runner: RefCounted) -> GDGuideData.GuideSignal:
		if bool(child_runner.get("is_running")):
			return GDGuideData.GuideSignal.waiting("子图 #%d 运行中" % int(child_runner.get("active_node_id")))
		var exit_r := int(child_runner.call("get_current_exit_reason"))
		var exit_msg := str(child_runner.call("get_current_exit_message"))
		if exit_r == GDGuideData.GuideExitReason.COMPLETED:
			return GDGuideData.GuideSignal.succeed()
		return GDGuideData.GuideSignal.end_graph(exit_r, "子图：" + exit_msg)


# ─────────────────────── GuideTargetAtom & 10/11. Strong / Weak GuideAtom ───────────────────────

class GuideTargetAtom extends GuideAtom:
	@export var target: GDGuideData.GuideTargetRef = GDGuideData.GuideTargetRef.new()
	@export var show_text: bool = false
	@export_multiline var text: String = ""
	@export var speaker: String = ""
	@export var finger_anchor: int = GDGuideData.GuideAnchor.AUTO
	@export var finger_anchor_offset: Vector2 = Vector2.ZERO
	@export var text_anchor: int = GDGuideData.GuideAnchor.AUTO
	@export var complete_mode: int = GDGuideData.GuideCompleteMode.TARGET_CLICK
	@export var raw_event_key: String = ""
	@export var event_ref: GDGuideData.GuideEventRef = GDGuideData.GuideEventRef.new()
	@export var raw_timeout_sec: float = 0.0

	func get_ports() -> Array[GDGuideData.GuidePort]: return GDGuideData.GuidePorts.in_out_timeout()
	func _get_timeout_sec() -> float: return raw_timeout_sec
	var event_key: String:
		get: return event_ref.key if event_ref != null else ""

	func _get_capture_clicks() -> bool:
		return false

	func _get_alternate_type_id() -> String:
		return ""

	var capture_clicks: bool:
		get: return _get_capture_clicks()

	var alternate_type_id: String:
		get: return _get_alternate_type_id()

	func _get_summary() -> String:
		var t_str := "无目标" if (target == null or target.is_none) else target.format_target()
		var done := "点中完成" if complete_mode == GDGuideData.GuideCompleteMode.TARGET_CLICK else ("等 " + (event_key if not event_key.is_empty() else "—"))
		var txt := text.substr(0, 14) if (show_text and not text.is_empty()) else ""
		return t_str + " · " + done + ("\n" + txt if not txt.is_empty() else "")

	func set_target(p_target: GDGuideData.GuideTargetRef) -> void:
		target = p_target if p_target != null else GDGuideData.GuideTargetRef.new()

	func set_text(p_text: String, p_speaker: String = "") -> void:
		text = p_text if p_text != null else ""
		speaker = p_speaker if p_speaker != null else ""
		show_text = not text.strip_edges().is_empty()

	func set_show_text(p_show: bool) -> void:
		show_text = p_show

	func set_completion(p_mode: int, p_event_key: String = "") -> void:
		complete_mode = p_mode
		raw_event_key = p_event_key
		event_ref = GDGuideData.GuideEventRef.parse(p_event_key)

	func set_timeout(p_timeout: float) -> void:
		raw_timeout_sec = p_timeout

	func migrate_event() -> void:
		event_ref = GDGuideData.GuideEventRef.parse(raw_event_key)

	func validate(vctx: RefCounted) -> void:
		if complete_mode == GDGuideData.GuideCompleteMode.EVENT_KEY and event_key.is_empty():
			vctx.call("add_error", "target.no_event_key", "完成方式是「事件键」，但没填完成事件键")
		if complete_mode == GDGuideData.GuideCompleteMode.TARGET_CLICK and (target == null or target.is_none):
			vctx.call("add_error", "target.click_without_target", "完成方式是「点中目标」，但没填目标")
		if target != null and target.kind == GDGuideData.GuideTargetKind.UI_WIDGET and target.widget.is_empty() and target.rule.is_empty():
			vctx.call("add_warning", "target.no_widget", "目标是 UI 控件，但控件路径和动态规则都没填")
		if target != null and target.kind == GDGuideData.GuideTargetKind.WORLD_ID and target.world_key.is_empty() and target.rule.is_empty():
			vctx.call("add_warning", "target.no_world_key", "目标是世界物体，但世界键和动态规则都没填")

	func _try_complete(ctx: RefCounted, st: Dictionary) -> bool:
		if complete_mode == GDGuideData.GuideCompleteMode.EVENT_KEY:
			return bool(ctx.call("try_consume_signal", event_key))
		return bool(st.get("presented", false)) and bool(ctx.call("consume_click"))


class StrongGuideAtom extends GuideTargetAtom:
	@export var click_mode: int = GDGuideData.GuideClickMode.FORWARD
	@export var backdrop_alpha: float = 0.7
	@export var highlight_scale: float = 1.0

	func _init() -> void:
		complete_mode = GDGuideData.GuideCompleteMode.TARGET_CLICK

	func get_atom_id() -> String: return "io.guide.strong"
	func get_atom_display_name() -> String: return "强引导"
	func get_atom_category() -> String: return CATEGORY_GUIDE
	func _get_blocks_input() -> bool: return true
	func _get_capture_clicks() -> bool: return true
	func _get_alternate_type_id() -> String: return "io.guide.weak"

	func set_click_mode(p_mode: int) -> void:
		click_mode = p_mode

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func tick(ctx: RefCounted, _dt: float) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func _evaluate(ctx: RefCounted) -> GDGuideData.GuideSignal:
		var st: Dictionary = ctx.call("get_node_state")
		if bool(st.get("presented", false)) and _try_complete(ctx, st):
			return GDGuideData.GuideSignal.succeed(GDGuideData.GuidePortKind.EXEC_OUT, "完成强引导")
		if _try_complete(ctx, st):
			return GDGuideData.GuideSignal.succeed(GDGuideData.GuidePortKind.EXEC_OUT, "完成强引导")
		var gate := target.gate_panel if target != null else ""
		if not bool(ctx.call("is_panel_ready", gate)):
			st["presented"] = false
			return GDGuideData.GuideSignal.stall("等面板 " + gate)
		var count := int(ctx.call("locate_targets", target))
		var needs_target := (target != null and not target.is_none) or click_mode == GDGuideData.GuideClickMode.FORWARD or complete_mode == GDGuideData.GuideCompleteMode.TARGET_CLICK
		if needs_target and count == 0:
			st["presented"] = false
			return GDGuideData.GuideSignal.stall("等目标 " + (target.format_target() if target != null else ""))
		st["presented"] = true
		return GDGuideData.GuideSignal.running("等待点击目标")

	func validate(vctx: RefCounted) -> void:
		super.validate(vctx)
		if complete_mode == GDGuideData.GuideCompleteMode.TARGET_CLICK and click_mode == GDGuideData.GuideClickMode.NONE:
			vctx.call("add_error", "strong.click_disabled", "点击方式是「不可点」，却要靠「点中目标」完成，永远走不下去")
		if click_mode == GDGuideData.GuideClickMode.FORWARD and (target == null or target.is_none):
			vctx.call("add_error", "strong.forward_without_target", "点击方式是「转发到真目标」，但没填目标")


class WeakGuideAtom extends GuideTargetAtom:
	@export var show_arrow: bool = true
	@export var highlight_scale: float = 1.0

	func _init() -> void:
		complete_mode = GDGuideData.GuideCompleteMode.EVENT_KEY

	func get_atom_id() -> String: return "io.guide.weak"
	func get_atom_display_name() -> String: return "弱引导"
	func get_atom_category() -> String: return CATEGORY_GUIDE
	func _get_alternate_type_id() -> String: return "io.guide.strong"

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func tick(ctx: RefCounted, _dt: float) -> GDGuideData.GuideSignal:
		return _evaluate(ctx)

	func _evaluate(ctx: RefCounted) -> GDGuideData.GuideSignal:
		var st: Dictionary = ctx.call("get_node_state")
		if _try_complete(ctx, st):
			return GDGuideData.GuideSignal.succeed(GDGuideData.GuidePortKind.EXEC_OUT, "完成弱引导")
		var gate := target.gate_panel if target != null else ""
		if not bool(ctx.call("is_panel_ready", gate)):
			st["presented"] = false
			return GDGuideData.GuideSignal.waiting("等面板 " + gate)
		var count := int(ctx.call("locate_targets", target))
		if target != null and not target.is_none and count == 0:
			st["presented"] = false
			return GDGuideData.GuideSignal.waiting("等目标 " + target.format_target())
		st["presented"] = true
		return GDGuideData.GuideSignal.running("弱引导展示中")


# ─────────────────────── 对话 / 列表 / 检查点 / 完成 ───────────────────────

class GuideDialogueAtom extends GuideAtom:
	@export_multiline var text: String = ""
	@export var speaker: String = ""
	@export var target: GDGuideData.GuideTargetRef = GDGuideData.GuideTargetRef.new()
	@export var backdrop_alpha: float = 0.4

	func get_atom_id() -> String: return "io.guide.dialogue"
	func get_atom_display_name() -> String: return "对话"
	func get_atom_category() -> String: return CATEGORY_GUIDE
	func _get_blocks_input() -> bool: return true
	func _get_summary() -> String: return text

	func tick(ctx: RefCounted, _dt: float) -> GDGuideData.GuideSignal:
		var st: Dictionary = ctx.call("get_node_state")
		if bool(st.get("presented", false)) and bool(ctx.call("consume_click")):
			return GDGuideData.GuideSignal.succeed()
		st["presented"] = true
		return GDGuideData.GuideSignal.waiting("阅读对话")


class GuideListFocusAtom extends GuideAtom:
	@export var target: GDGuideData.GuideTargetRef = GDGuideData.GuideTargetRef.new()
	@export var raw_timeout_sec: float = 10.0

	func get_atom_id() -> String: return "io.guide.list_focus"
	func get_atom_display_name() -> String: return "聚焦列表项"
	func get_atom_category() -> String: return CATEGORY_GUIDE
	func get_ports() -> Array[GDGuideData.GuidePort]: return GDGuideData.GuidePorts.in_out_timeout()
	func _get_timeout_sec() -> float: return raw_timeout_sec
	func _get_summary() -> String:
		return target.format_target() if target != null else ""

	func configure(p_target: GDGuideData.GuideTargetRef, p_timeout: float = 10.0) -> void:
		target = p_target if p_target != null else GDGuideData.GuideTargetRef.new()
		raw_timeout_sec = p_timeout

	func enter(_ctx: RefCounted) -> GDGuideData.GuideSignal:
		return GDGuideData.GuideSignal.succeed(GDGuideData.GuidePortKind.EXEC_OUT, "列表聚焦完成")

	func validate(vctx: RefCounted) -> void:
		if target == null or target.kind != GDGuideData.GuideTargetKind.UI_WIDGET or target.panel.strip_edges().is_empty() or (target.widget.strip_edges().is_empty() and target.rule.strip_edges().is_empty()):
			vctx.call("add_error", "io.guide.list_focus.target", "列表聚焦需要 UI 面板及单个控件路径或动态规则")
		if target != null and target.widget.contains(";"):
			vctx.call("add_error", "io.guide.list_focus.multiple", "列表聚焦每次只能指定一个目标")


class GuideCheckpointAtom extends GuideAtom:
	@export var checkpoint: String = ""

	func get_atom_id() -> String: return "io.guide.checkpoint"
	func get_atom_display_name() -> String: return "记录检查点"
	func get_atom_category() -> String: return CATEGORY_FLOW
	func _get_completes_on_enter() -> bool: return true
	func _get_is_resume_point() -> bool: return false
	func _get_summary() -> String: return checkpoint

	func configure(p_checkpoint: String) -> void:
		checkpoint = p_checkpoint if p_checkpoint != null else ""

	func enter(ctx: RefCounted) -> GDGuideData.GuideSignal:
		ctx.call("record_checkpoint", checkpoint)
		return GDGuideData.GuideSignal.succeed()

	func validate(vctx: RefCounted) -> void:
		if checkpoint == null or checkpoint.strip_edges().is_empty():
			vctx.call("add_error", "checkpoint.empty", "检查点不能为空")


class GuideTutorialCompleteAtom extends GuideAtom:
	func get_atom_id() -> String: return "io.guide.complete"
	func get_atom_display_name() -> String: return "结束引导"
	func get_atom_category() -> String: return CATEGORY_FLOW
	func get_ports() -> Array[GDGuideData.GuidePort]: return GDGuideData.GuidePorts.exit_only()
	func _get_completes_on_enter() -> bool: return true
	func _get_is_resume_point() -> bool: return false

	func enter(_ctx: RefCounted) -> GDGuideData.GuideSignal:
		return GDGuideData.GuideSignal.end_graph(GDGuideData.GuideExitReason.COMPLETED, "结束引导")


# ─────────────────────── Atom Registry / Factory ───────────────────────

static func get_all_atom_descriptors() -> Array[Dictionary]:
	return [
		{"id": "io.guide.entry", "display": "入口", "category": CATEGORY_FLOW},
		{"id": "io.guide.exit", "display": "出口", "category": CATEGORY_FLOW},
		{"id": "io.guide.branch", "display": "条件跳转", "category": CATEGORY_FLOW},
		{"id": "io.guide.subgraph", "display": "子图", "category": CATEGORY_FLOW},
		{"id": "io.guide.narration", "display": "旁白", "category": CATEGORY_GUIDE},
		{"id": "io.guide.lockwait", "display": "锁屏等待", "category": CATEGORY_WAIT},
		{"id": "io.guide.wait_event", "display": "等事件", "category": CATEGORY_WAIT},
		{"id": "io.guide.wait_condition", "display": "条件等待", "category": CATEGORY_WAIT},
		{"id": "io.guide.delay", "display": "延迟", "category": CATEGORY_WAIT},
		{"id": "io.guide.strong", "display": "强引导", "category": CATEGORY_GUIDE},
		{"id": "io.guide.weak", "display": "弱引导", "category": CATEGORY_GUIDE},
		{"id": "io.guide.dialogue", "display": "对话", "category": CATEGORY_GUIDE},
		{"id": "io.guide.list_focus", "display": "聚焦列表项", "category": CATEGORY_GUIDE},
		{"id": "io.guide.checkpoint", "display": "记录检查点", "category": CATEGORY_FLOW},
		{"id": "io.guide.complete", "display": "结束引导", "category": CATEGORY_FLOW},
	]

static func create_atom_by_id(atom_id: String) -> GuideAtom:
	match atom_id:
		"io.guide.entry": return EntryAtom.new()
		"io.guide.exit": return ExitAtom.new()
		"io.guide.branch": return BranchAtom.new()
		"io.guide.subgraph": return SubgraphAtom.new()
		"io.guide.narration": return NarrationAtom.new()
		"io.guide.lockwait": return LockWaitAtom.new()
		"io.guide.wait_event": return WaitEventAtom.new()
		"io.guide.wait_condition": return ConditionWaitAtom.new()
		"io.guide.delay": return DelayAtom.new()
		"io.guide.strong": return StrongGuideAtom.new()
		"io.guide.weak": return WeakGuideAtom.new()
		"io.guide.dialogue": return GuideDialogueAtom.new()
		"io.guide.list_focus": return GuideListFocusAtom.new()
		"io.guide.checkpoint": return GuideCheckpointAtom.new()
		"io.guide.complete": return GuideTutorialCompleteAtom.new()
		_: return null
