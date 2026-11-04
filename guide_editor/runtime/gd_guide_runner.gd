@tool
class_name GDGuideRunnerSystem
extends RefCounted

## 新手引导执行器（GuideRunner）、运行状态（GuideRun）、上下文（GuideContext）、
## 触发器系统（GuideTriggerSystem）、断点与调试会话登记表（GuideDebugRegistry）
## 对应 GuideRunner / GuideRunner.Debug / GuideRun / GuideContext / GuideTriggerSystem / GuideDebugRegistry / GuideBreakpoints

# ─────────────────────── GuideBreakpoints & GuideDebugRegistry ───────────────────────

class GuideBreakpoints extends RefCounted:
	static var _by_graph: Dictionary = {} # GuideGraphRes -> Dictionary (node_id -> true)

	static func contains(graph: GDGuideGraphRes, node_id: int) -> bool:
		if graph == null or not _by_graph.has(graph):
			return false
		return (_by_graph[graph] as Dictionary).has(node_id)

	static func set_breakpoint(graph: GDGuideGraphRes, node_id: int, enabled: bool) -> void:
		if graph == null or node_id <= 0:
			return
		if not _by_graph.has(graph):
			_by_graph[graph] = {}
		var map := _by_graph[graph] as Dictionary
		if enabled:
			map[node_id] = true
		else:
			map.erase(node_id)

	static func toggle(graph: GDGuideGraphRes, node_id: int) -> void:
		set_breakpoint(graph, node_id, not contains(graph, node_id))

	static func get_all(graph: GDGuideGraphRes) -> Array[int]:
		var out: Array[int] = []
		if graph != null and _by_graph.has(graph):
			for k in (_by_graph[graph] as Dictionary).keys():
				out.append(int(k))
		out.sort()
		return out

	static func clear(graph: GDGuideGraphRes) -> void:
		if graph != null:
			_by_graph.erase(graph)


class GuideDebugRegistry extends RefCounted:
	static var _sessions: Array = [] # Array[GuideRunner]
	static var version: int = 0

	static func register_session(session: RefCounted) -> void:
		if session == null or _sessions.has(session):
			return
		_sessions.append(session)
		version += 1

	static func unregister_session(session: RefCounted) -> void:
		if session != null and _sessions.has(session):
			_sessions.erase(session)
			version += 1

	static func find_by_graph(graph: GDGuideGraphRes) -> RefCounted:
		if graph == null:
			return null
		var fallback: RefCounted = null
		for i in range(_sessions.size() - 1, -1, -1):
			var s = _sessions[i]
			if s == null or s.get("graph") != graph:
				continue
			if bool(s.get("is_running")):
				return s
			if fallback == null:
				fallback = s
		return fallback


# ─────────────────────── GuideTraceEvent & GuideRunSnapshot ───────────────────────

class GuideTraceEvent extends RefCounted:
	var seq: int = 0
	var kind: int = GDGuideData.GuideTraceKind.LOG
	var graph_id: int = 0
	var run_id: int = 0
	var node_id: int = 0
	var phase: int = GDGuideData.GuideNodePhase.IDLE
	var port: int = GDGuideData.GuidePortKind.EXEC_OUT
	var to_node_id: int = 0
	var time_since_start: float = 0.0
	var message: String = ""

	func _init(
		p_seq: int,
		p_kind: int,
		p_graph_id: int,
		p_run_id: int,
		p_node_id: int,
		p_phase: int,
		p_port: int,
		p_to_node_id: int,
		p_time: float,
		p_msg: String
	) -> void:
		seq = p_seq
		kind = p_kind
		graph_id = p_graph_id
		run_id = p_run_id
		node_id = p_node_id
		phase = p_phase
		port = p_port
		to_node_id = p_to_node_id
		time_since_start = p_time
		message = p_msg

	func format_trace() -> String:
		var head := "#%d %.2fs " % [seq, time_since_start]
		match kind:
			GDGuideData.GuideTraceKind.EDGE:
				return head + "#%d.%s -> #%d" % [node_id, GDGuideData.GuidePorts.label(port), to_node_id]
			GDGuideData.GuideTraceKind.PHASE:
				return head + "#%d phase=%d %s" % [node_id, phase, message]
			_:
				return head + "node=%d %s" % [node_id, message]


class GuideRunSnapshot extends RefCounted:
	var timed_out: bool = false
	var condition_results: Dictionary = {} # node_id -> Array[GuideConditionResult]
	var session_name: String = ""
	var graph_id: int = 0
	var graph_name: String = ""
	var run_id: int = 0
	var is_running: bool = false
	var is_paused: bool = false
	var is_finished: bool = false
	var exit_reason: int = GDGuideData.GuideExitReason.COMPLETED
	var exit_message: String = ""
	var active_node_ids: Array[int] = []
	var phases: Dictionary = {} # int -> GuideNodePhase
	var visit_counts: Dictionary = {} # int -> int
	var blackboard: Dictionary = {} # String -> String
	var breakpoints: Array[int] = []
	var node_elapsed: float = 0.0
	var active_message: String = ""
	var time_since_start: float = 0.0
	var last_trace_seq: int = 0

	var has_run: bool:
		get:
			return run_id > 0

	var active_node_id: int:
		get:
			return active_node_ids[0] if not active_node_ids.is_empty() else 0

	func phase_of(nid: int) -> int:
		return int(phases.get(nid, GDGuideData.GuideNodePhase.IDLE))

	func visits_of(nid: int) -> int:
		return int(visit_counts.get(nid, 0))


# ─────────────────────── GuideRunnerOptions & GuideRun & GuideContext ───────────────────────

class GuideRunnerOptions extends RefCounted:
	var debug_name: String = "GuideRunner"
	var stall_timeout_sec: float = 15.0
	var max_immediate_hops: int = 64
	var trace_capacity: int = 512
	var validate_on_start: bool = true
	var register_debug_session: bool = true
	var log_trace: bool = false
	var publish_graph_finished: bool = true
	var shared_blackboard: GDGuideData.GuideBlackboard = null
	var subgraph_depth: int = 0


class GuideRun extends RefCounted:
	var run_id: int = 0
	var graph: GDGuideGraphRes = null
	var graph_id: int = 0
	var graph_name: String = ""
	var force: bool = false
	var is_running: bool = false
	var is_finished: bool = false
	var exit_reason: int = GDGuideData.GuideExitReason.COMPLETED
	var exit_message: String = ""
	var start_node_id: int = 0
	var active_node_id: int = 0
	var last_node_id: int = 0
	var active_atom: GDGuideAtoms.GuideAtom = null
	var total_elapsed: float = 0.0
	var node_elapsed: float = 0.0
	var node_clock: float = 0.0
	var active_elapsed: float = 0.0
	var stall_elapsed: float = 0.0
	var active_message: String = ""
	var enter_count: int = 0
	var timed_out: bool = false
	var node_enter_seq: int = 0

	var blackboard: GDGuideData.GuideBlackboard = null
	var phases: Dictionary = {}
	var visit_counts: Dictionary = {}
	var states: Dictionary = {} # node_id -> Dictionary
	var condition_results: Dictionary = {} # node_id -> Array[GuideConditionResult]

	func _init(
		p_run_id: int,
		p_graph: GDGuideGraphRes,
		p_force: bool,
		p_bb: GDGuideData.GuideBlackboard = null
	) -> void:
		run_id = p_run_id
		graph = p_graph
		graph_id = p_graph.graph_id if p_graph != null else 0
		graph_name = p_graph.display_name if p_graph != null else ""
		force = p_force
		blackboard = p_bb if p_bb != null else GDGuideData.GuideBlackboard.new()

	func get_phase(nid: int) -> int:
		return int(phases.get(nid, GDGuideData.GuideNodePhase.IDLE))

	func set_phase(nid: int, p_phase: int) -> void:
		phases[nid] = p_phase

	func get_visit_count(nid: int) -> int:
		return int(visit_counts.get(nid, 0))

	func mark_entered(nid: int) -> void:
		visit_counts[nid] = get_visit_count(nid) + 1
		enter_count += 1

	func get_or_create_state(nid: int) -> Dictionary:
		if not states.has(nid):
			states[nid] = {}
		return states[nid]

	func clear_state(nid: int) -> void:
		states.erase(nid)


class GuideContext extends RefCounted:
	var runner: GuideRunner = null
	var run: GuideRun = null

	func _init(p_runner: GuideRunner, p_run: GuideRun) -> void:
		runner = p_runner
		run = p_run

	var node_elapsed: float:
		get:
			return run.node_clock if run != null else 0.0

	var stall_elapsed: float:
		get:
			return run.stall_elapsed if run != null else 0.0

	func get_node_state() -> Dictionary:
		return run.get_or_create_state(run.active_node_id)

	func try_consume_signal(expected: String) -> bool:
		return runner._try_consume_signal(run, expected)

	func consume_click() -> bool:
		return runner._consume_click(run)

	func is_panel_ready(panel_key: String) -> bool:
		return runner.host.is_panel_ready(panel_key)

	func locate_targets(target: GDGuideData.GuideTargetRef) -> int:
		return runner.host.locate_targets(target)

	func evaluate_conditions(rows: Array) -> GDGuideData.GuideConditionResult:
		var out_rows: Array[GDGuideData.GuideConditionResult] = []
		var ctx_dict := {
			"host": runner.host,
			"graph_id": run.graph_id,
			"blackboard": run.blackboard,
		}
		var res := runner.host.conditions.evaluate_rows(rows, ctx_dict, out_rows)
		run.condition_results[run.active_node_id] = out_rows
		return res

	func record_checkpoint(cp_name: String) -> void:
		if runner.host.progress != null:
			runner.host.progress.set_checkpoint(run.graph_id, cp_name)
			runner.host.progress.flush()

	func start_subgraph_runner(sub_graph: GDGuideGraphRes) -> GuideRunner:
		if runner.options.subgraph_depth >= 16:
			return null
		if sub_graph == run.graph:
			return null
		var sub_opts := GuideRunnerOptions.new()
		sub_opts.debug_name = "%s / %s" % [run.graph_name, sub_graph.display_name]
		sub_opts.shared_blackboard = run.blackboard
		sub_opts.publish_graph_finished = false
		sub_opts.subgraph_depth = runner.options.subgraph_depth + 1
		var sub_runner := GuideRunner.new(runner.host, sub_opts)
		if not sub_runner.try_start(sub_graph, 0, true):
			sub_runner.dispose()
			return null
		var st := get_node_state()
		st["runner"] = sub_runner
		return sub_runner


# ─────────────────────── GuideRunner ───────────────────────

class GuideRunner extends RefCounted:
	signal graph_started(evt: Dictionary)
	signal node_changed(evt: Dictionary)
	signal graph_finished(evt: Dictionary)
	signal traced(evt: GuideTraceEvent)

	static var _next_run_id: int = 0

	var host: GDGuideServices.GuideHost = null
	var options: GuideRunnerOptions = null
	var current_run: GuideRun = null
	var is_disposed: bool = false

	var _ctx: GuideContext = null
	var _inputs: Array[Dictionary] = [] # {"seq": int, "kind": "signal"|"click", "key": String, "node_id": int, "consumed": bool}
	var _suspended: Dictionary = {} # graph_id -> true
	var _trace: Array[GuideTraceEvent] = []
	var _trace_seq: int = 0
	var _input_seq: int = 0
	var _consumed_seq: int = 0
	var _tick_watermark: int = 0
	var _invocation: String = "none" # "none" | "enter" | "tick"
	var _hops: int = 0
	var _skip_requested: bool = false
	var _paused: bool = false
	var _pending_enter: bool = false
	var _stepping: bool = false
	var _debug_start_node: bool = false
	var _signal_connected: bool = false

	func _init(p_host: GDGuideServices.GuideHost, p_options: GuideRunnerOptions = null) -> void:
		host = p_host if p_host != null else GDGuideServices.GuideHost.new()
		options = p_options if p_options != null else GuideRunnerOptions.new()
		_ensure_hooks()
		if options.register_debug_session:
			GuideDebugRegistry.register_session(self)

	var graph: GDGuideGraphRes:
		get:
			return current_run.graph if current_run != null else null

	var is_running: bool:
		get:
			return current_run != null and current_run.is_running

	var is_paused: bool:
		get:
			return is_running and _paused

	var active_node_id: int:
		get:
			return current_run.active_node_id if is_running else 0

	var active_atom: GDGuideAtoms.GuideAtom:
		get:
			return current_run.active_atom if is_running else null

	func is_suspended(p_graph_id: int) -> bool:
		return _suspended.has(p_graph_id)

	func clear_suspended() -> void:
		_suspended.clear()

	func get_current_exit_reason() -> int:
		return current_run.exit_reason if current_run != null else GDGuideData.GuideExitReason.ABORTED

	func get_current_exit_message() -> String:
		return current_run.exit_message if current_run != null else ""

	func try_start(
		p_graph: GDGuideGraphRes,
		resume_node_id: int = 0,
		force: bool = false
	) -> bool:
		if is_disposed or p_graph == null:
			return false
		if p_graph.schema_version != GDGuideGraphRes.CURRENT_SCHEMA_VERSION:
			GDGameLogger.log_warning("[Guide] 数据版本不支持，请先迁移到 v2")
			return false

		if is_running:
			if not force:
				return false
			_finish(current_run, GDGuideData.GuideExitReason.ABORTED, "被强制启动「%s」打断" % p_graph.display_name)

		if not force:
			var auto_check := _can_auto_start(p_graph)
			if not bool(auto_check.get("ok", false)):
				return false

		_inputs.clear()
		_skip_requested = false
		_hops = 0
		_invocation = "none"
		_consumed_seq = 0
		_paused = false
		_pending_enter = false

		_next_run_id += 1
		var run := GuideRun.new(_next_run_id, p_graph, force, options.shared_blackboard)
		current_run = run
		_ctx = GuideContext.new(self, run)
		run.is_running = true
		_ensure_hooks()
		run.node_enter_seq = _input_seq

		_record_trace(run, GDGuideData.GuideTraceKind.RUN_STARTED, 0, GDGuideData.GuideNodePhase.IDLE, GDGuideData.GuidePortKind.EXEC_OUT, 0, "强制启动" if force else "启动")

		if options.validate_on_start:
			var report := GDGuideValidation.GuideGraphValidator.validate(p_graph, [], host.conditions)
			if report.has_errors:
				graph_started.emit({"graph_id": run.graph_id, "run_id": run.run_id, "start_node_id": 0})
				_finish(run, GDGuideData.GuideExitReason.FAILED, "图校验失败：" + report.summarize(3))
				return false

		var start_id := _resolve_start_node(run, resume_node_id)
		run.start_node_id = start_id
		graph_started.emit({"graph_id": run.graph_id, "run_id": run.run_id, "start_node_id": start_id})
		if not _is_live(run):
			return false
		if start_id <= 0:
			_finish(run, GDGuideData.GuideExitReason.FAILED, "图里没有入口节点")
			return false

		_enter_node(run, start_id, _input_seq)
		return true

	## 调试用：从任意从入口可达的节点开跑，不要求它是续跑点。
	func try_start_from(p_graph: GDGuideGraphRes, node_id: int) -> bool:
		_debug_start_node = true
		var started := try_start(p_graph, node_id, true)
		_debug_start_node = false
		return started

	func stop(reason: int = GDGuideData.GuideExitReason.ABORTED) -> void:
		if is_running:
			_finish(current_run, reason, "外部结束")

	func request_skip() -> void:
		if is_running:
			_skip_requested = true

	func tick(dt: float) -> void:
		if is_disposed or current_run == null or not current_run.is_running or _paused:
			return
		var run := current_run
		_ensure_hooks()
		_hops = 0
		var safe_dt := 0.0 if (is_nan(dt) or dt < 0.0) else dt

		if _skip_requested:
			_skip_requested = false
			var r := GDGuideData.GuideExitReason.SKIPPED if run.graph.allow_skip else GDGuideData.GuideExitReason.DEFERRED
			var m := "玩家结束引导" if run.graph.allow_skip else "玩家选择稍后继续"
			_finish(run, r, m)
			return

		run.total_elapsed += safe_dt
		run.node_clock += safe_dt
		if not run.timed_out:
			run.node_elapsed += safe_dt

		var nid := run.active_node_id
		var atom := run.active_atom
		var enter_cnt := run.enter_count
		_tick_watermark = _input_seq

		_invocation = "tick"
		_consumed_seq = 0
		var sig := atom.tick(_ctx, safe_dt)
		_apply_signal(run, atom, nid, sig, safe_dt)
		_expire_inputs(run, enter_cnt)
		_invocation = "none"

	# ── Debug Session API ──

	func enqueue_debug_command(cmd_kind: int, node_id: int = 0, exit_reason: int = GDGuideData.GuideExitReason.ABORTED) -> void:
		if is_disposed:
			return
		match cmd_kind:
			GDGuideData.GuideDebugCommandKind.SET_BREAKPOINT:
				GuideBreakpoints.set_breakpoint(graph, node_id, true)
			GDGuideData.GuideDebugCommandKind.CLEAR_BREAKPOINT:
				GuideBreakpoints.set_breakpoint(graph, node_id, false)
			GDGuideData.GuideDebugCommandKind.PAUSE:
				if is_running:
					_paused = true
					_record_trace(current_run, GDGuideData.GuideTraceKind.LOG, active_node_id, GDGuideData.GuideNodePhase.PAUSED, GDGuideData.GuidePortKind.EXEC_OUT, 0, "调试暂停；计时冻结，输入保留")
			GDGuideData.GuideDebugCommandKind.CONTINUE:
				if is_paused:
					_paused = false
					_hops = 0
					_invoke_pending_enter(current_run)
			GDGuideData.GuideDebugCommandKind.STEP_ONCE:
				if is_paused:
					_paused = false
					_stepping = true
					_hops = 0
					if _pending_enter:
						_invoke_pending_enter(current_run)
					else:
						tick(1.0 / 60.0)
					_stepping = false
					if is_running and not _paused:
						_paused = true
						_record_trace(current_run, GDGuideData.GuideTraceKind.LOG, active_node_id, GDGuideData.GuideNodePhase.PAUSED, GDGuideData.GuidePortKind.EXEC_OUT, 0, "单步完成")
			GDGuideData.GuideDebugCommandKind.SKIP_NODE:
				if is_running:
					_skip_active_node(current_run, "调试跳过")
			GDGuideData.GuideDebugCommandKind.RESTART_FROM:
				if graph != null and graph.find_atom(node_id) != null and graph.is_reachable_from_entry(node_id):
					_debug_start_node = true
					try_start(graph, node_id, true)
					_debug_start_node = false
			GDGuideData.GuideDebugCommandKind.STOP:
				if is_running:
					_finish(current_run, exit_reason, "调试结束")

	func capture_snapshot() -> GuideRunSnapshot:
		var snap := GuideRunSnapshot.new()
		snap.session_name = options.debug_name
		snap.last_trace_seq = _trace_seq
		if current_run == null:
			return snap
		var r := current_run
		snap.timed_out = r.timed_out
		snap.condition_results = r.condition_results.duplicate()
		snap.graph_id = r.graph_id
		snap.graph_name = r.graph_name
		snap.run_id = r.run_id
		snap.is_running = r.is_running
		snap.is_paused = is_paused
		snap.breakpoints = GuideBreakpoints.get_all(r.graph)
		snap.is_finished = r.is_finished
		snap.exit_reason = r.exit_reason
		snap.exit_message = r.exit_message
		snap.active_node_ids.assign([r.active_node_id] if (r.is_running and r.active_node_id > 0) else [])
		snap.phases = r.phases.duplicate()
		if is_paused and r.active_node_id > 0:
			snap.phases[r.active_node_id] = GDGuideData.GuideNodePhase.PAUSED
		snap.visit_counts = r.visit_counts.duplicate()
		snap.blackboard = r.blackboard.values.duplicate()
		snap.node_elapsed = r.node_elapsed if r.is_running else 0.0
		snap.active_message = r.active_message if r.is_running else r.exit_message
		snap.time_since_start = r.total_elapsed
		return snap

	func copy_trace(after_seq: int) -> Array[GuideTraceEvent]:
		var out: Array[GuideTraceEvent] = []
		for evt in _trace:
			if evt.seq > after_seq:
				out.append(evt)
		return out

	func dispose() -> void:
		if is_disposed:
			return
		if is_running:
			_finish(current_run, GDGuideData.GuideExitReason.ABORTED, "Runner 已释放")
		if _signal_connected and host != null and host.signals != null:
			if host.signals.raised.is_connected(_on_signal_raised):
				host.signals.raised.disconnect(_on_signal_raised)
			_signal_connected = false
		if host != null:
			host.bind_target_click(Callable())
			host.bind_skip(Callable())
		if _ctx != null:
			_ctx.runner = null
			_ctx.run = null
			_ctx = null
		current_run = null
		is_disposed = true
		GuideDebugRegistry.unregister_session(self)

	# ── Internal Execution ──

	func _is_live(run: GuideRun) -> bool:
		return run != null and run == current_run and run.is_running

	func _can_auto_start(p_graph: GDGuideGraphRes) -> Dictionary:
		if not p_graph.enabled:
			return {"ok": false, "reason": "图未启用"}
		if host.progress != null and host.progress.is_graph_completed(p_graph.graph_id):
			return {"ok": false, "reason": "已完成"}
		if host.progress != null and host.progress.is_graph_skipped(p_graph.graph_id):
			return {"ok": false, "reason": "已跳过"}
		if _suspended.has(p_graph.graph_id):
			return {"ok": false, "reason": "本局已暂缓或失败过"}
		return {"ok": true, "reason": ""}

	func _resolve_start_node(run: GuideRun, resume_node_id: int) -> int:
		if run.graph.resume_from_entry and not run.force:
			return run.graph.find_entry_id()
		if resume_node_id > 0:
			var resume_a := run.graph.find_atom(resume_node_id)
			if resume_a != null and (resume_a.is_resume_point or _debug_start_node) and run.graph.is_reachable_from_entry(resume_node_id):
				return resume_node_id
			_record_trace(run, GDGuideData.GuideTraceKind.WARNING, resume_node_id, GDGuideData.GuideNodePhase.IDLE, GDGuideData.GuidePortKind.EXEC_OUT, 0, "断点 #%d 不可续跑或从入口不可达，从入口开始" % resume_node_id)
		return run.graph.find_entry_id()

	func _enter_node(run: GuideRun, nid: int, enter_seq: int) -> void:
		if not _is_live(run):
			return
		_hops += 1
		if _hops > maxi(1, options.max_immediate_hops):
			_finish(run, GDGuideData.GuideExitReason.FAILED, "一帧内连续进入超过 %d 个节点（无等待环？），停在 #%d" % [options.max_immediate_hops, nid], true)
			return
		var atom := run.graph.find_atom(nid)
		if atom == null or atom is GDGuideAtoms.MissingAtom:
			_finish(run, GDGuideData.GuideExitReason.FAILED, "节点 #%d 不存在（类型缺失或已删除）" % nid, true)
			return

		run.active_node_id = nid
		run.last_node_id = nid
		run.active_atom = atom
		run.node_elapsed = 0.0
		run.timed_out = false
		run.node_clock = 0.0
		run.active_elapsed = 0.0
		run.stall_elapsed = 0.0
		run.active_message = ""
		run.node_enter_seq = enter_seq
		run.clear_state(nid)
		run.mark_entered(nid)
		_set_phase(run, nid, GDGuideData.GuideNodePhase.ENTERING, "")

		if atom.is_resume_point and host.progress != null:
			host.progress.set_resume_node_id(run.graph_id, nid)
			host.progress.flush()

		node_changed.emit({"graph_id": run.graph_id, "run_id": run.run_id, "node_id": nid})
		if not _is_live(run) or run.active_node_id != nid:
			return

		_pending_enter = true
		if _paused or _stepping or GuideBreakpoints.contains(run.graph, nid):
			_paused = true
			_record_trace(run, GDGuideData.GuideTraceKind.LOG, nid, GDGuideData.GuideNodePhase.PAUSED, GDGuideData.GuidePortKind.EXEC_OUT, 0, "进入节点前暂停")
			return
		_invoke_pending_enter(run)

	func _invoke_pending_enter(run: GuideRun) -> void:
		if not _is_live(run) or not _pending_enter:
			return
		var atom := run.active_atom
		var nid := run.active_node_id
		_pending_enter = false
		_invocation = "enter"
		_consumed_seq = 0
		var sig := atom.enter(_ctx)
		_apply_signal(run, atom, nid, sig, 0.0)
		_invocation = "none"

	func _apply_signal(run: GuideRun, atom: GDGuideAtoms.GuideAtom, nid: int, sig: GDGuideData.GuideSignal, dt: float) -> void:
		if not _is_live(run) or run.active_node_id != nid:
			return
		if sig.ends_graph:
			_set_phase(run, nid, GDGuideData.GuideNodePhase.SUCCEEDED, sig.log)
			atom.exit(_ctx)
			_finish(run, sig.exit_reason, sig.log if not sig.log.is_empty() else ("到达出口「%s」" % atom.title), true)
			return
		match sig.phase:
			GDGuideData.GuideNodePhase.SUCCEEDED, GDGuideData.GuideNodePhase.SKIPPED:
				_leave(run, atom, nid, sig.phase, sig.out_port, sig.log)
			GDGuideData.GuideNodePhase.FAILED:
				_set_phase(run, nid, GDGuideData.GuideNodePhase.FAILED, sig.log)
				atom.exit(_ctx)
				_finish(run, GDGuideData.GuideExitReason.FAILED, "「%s」失败：%s" % [atom.title, sig.log], true)
			_:
				_stay(run, atom, nid, sig, dt)

	func _stay(run: GuideRun, atom: GDGuideAtoms.GuideAtom, nid: int, sig: GDGuideData.GuideSignal, dt: float) -> void:
		if run.timed_out:
			run.active_message = "已超时，卡在本节点；完成条件仍有效"
			return
		var ph := GDGuideData.GuideNodePhase.WAITING if sig.phase == GDGuideData.GuideNodePhase.WAITING else GDGuideData.GuideNodePhase.RUNNING
		var ph_changed := run.get_phase(nid) != ph
		var msg_changed := run.active_message != sig.log
		run.active_message = sig.log
		if ph_changed:
			_set_phase(run, nid, ph, sig.log)
		elif msg_changed and not sig.log.is_empty():
			_record_trace(run, GDGuideData.GuideTraceKind.LOG, nid, ph, GDGuideData.GuidePortKind.EXEC_OUT, 0, sig.log)

		if sig.stalled:
			run.stall_elapsed += dt
			var cap := maxf(options.stall_timeout_sec, maxf(0.0, atom.timeout_sec))
			if cap > 0.0 and run.stall_elapsed >= cap:
				_handle_timeout(run, atom, nid, "前置等待超过 %.1fs" % cap)
			return

		run.stall_elapsed = 0.0
		run.active_elapsed += dt
		var t_sec := maxf(0.0, atom.timeout_sec)
		if t_sec > 0.0 and run.active_elapsed >= t_sec:
			_handle_timeout(run, atom, nid, "超时 %.1fs" % t_sec)

	func _handle_timeout(run: GuideRun, atom: GDGuideAtoms.GuideAtom, nid: int, text: String) -> void:
		if atom.has_port(GDGuideData.GuidePortKind.EXEC_TIMEOUT) and bool(run.graph.try_get_edge(nid, GDGuideData.GuidePortKind.EXEC_TIMEOUT).get("ok", false)):
			_leave(run, atom, nid, GDGuideData.GuideNodePhase.SKIPPED, GDGuideData.GuidePortKind.EXEC_TIMEOUT, text)
			return
		if not atom.exit_on_timeout:
			run.timed_out = true
			run.active_message = "已超时，卡在本节点；完成条件仍有效"
			_record_trace(run, GDGuideData.GuideTraceKind.WARNING, nid, GDGuideData.GuideNodePhase.FAILED, GDGuideData.GuidePortKind.EXEC_TIMEOUT, 0, text)
			return
		_set_phase(run, nid, GDGuideData.GuideNodePhase.SKIPPED, text + "，没有超时边")
		atom.exit(_ctx)
		_finish(run, GDGuideData.GuideExitReason.DEFERRED, "「%s」%s，没有超时边，暂缓" % [atom.title, text], true)

	func _leave(run: GuideRun, atom: GDGuideAtoms.GuideAtom, nid: int, ph: int, port: int, p_log: String) -> void:
		var next_enter_seq := _next_enter_seq(run)
		_set_phase(run, nid, ph, p_log)
		atom.exit(_ctx)
		if not _is_live(run):
			return
		var edge_res := run.graph.try_get_edge(nid, port)
		if not bool(edge_res.get("ok", false)):
			if port == GDGuideData.GuidePortKind.EXEC_FALSE:
				var r := GDGuideData.GuideExitReason.DEFERRED if atom.exit_on_condition_fail else GDGuideData.GuideExitReason.FAILED
				_finish(run, r, "条件不满足且没有否边：" + p_log, true)
			elif port == GDGuideData.GuidePortKind.EXEC_TIMEOUT:
				_finish(run, GDGuideData.GuideExitReason.DEFERRED, "超时口没有连线，暂缓", true)
			else:
				_finish(run, GDGuideData.GuideExitReason.FAILED, "「%s」的「%s」口没有连线" % [atom.title, GDGuideData.GuidePorts.label(port)], true)
			return
		var edge: GDGuideData.GuideEdge = edge_res["edge"]
		_record_trace(run, GDGuideData.GuideTraceKind.EDGE, nid, ph, port, edge.to_id, "")
		_enter_node(run, edge.to_id, next_enter_seq)

	func _skip_active_node(run: GuideRun, reason: String) -> void:
		var atom := run.active_atom
		if atom == null:
			return
		var port := GDGuideData.GuidePortKind.EXEC_OUT
		if not atom.has_port(GDGuideData.GuidePortKind.EXEC_OUT):
			for p in atom.get_ports():
				if not p.is_input:
					port = p.kind
					break
		_hops = 0
		_leave(run, atom, run.active_node_id, GDGuideData.GuideNodePhase.SKIPPED, port, reason)

	func _finish(run: GuideRun, reason: int, message: String, node_already_exited: bool = false) -> void:
		if run == null or not run.is_running:
			return
		var nid := run.active_node_id
		var atom := run.active_atom
		run.is_running = false
		if not node_already_exited and atom != null and nid > 0:
			var cur_ph := run.get_phase(nid)
			if cur_ph in [GDGuideData.GuideNodePhase.ENTERING, GDGuideData.GuideNodePhase.RUNNING, GDGuideData.GuideNodePhase.WAITING, GDGuideData.GuideNodePhase.PAUSED]:
				_set_phase(run, nid, GDGuideData.GuideNodePhase.FAILED if reason == GDGuideData.GuideExitReason.FAILED else GDGuideData.GuideNodePhase.SKIPPED, message)
			atom.exit(_ctx)

		_apply_progress(run, reason)
		if reason == GDGuideData.GuideExitReason.DEFERRED or reason == GDGuideData.GuideExitReason.FAILED:
			_suspended[run.graph_id] = true

		run.is_finished = true
		run.exit_reason = reason
		run.exit_message = message
		run.active_node_id = 0
		run.active_atom = null
		_inputs.clear()
		_skip_requested = false

		_record_trace(run, GDGuideData.GuideTraceKind.RUN_FINISHED, nid, GDGuideData.GuideNodePhase.IDLE, GDGuideData.GuidePortKind.EXEC_OUT, 0, "%d：%s" % [reason, message])
		graph_finished.emit({"graph_id": run.graph_id, "run_id": run.run_id, "reason": reason, "message": message})
		if options.publish_graph_finished and (reason == GDGuideData.GuideExitReason.COMPLETED or reason == GDGuideData.GuideExitReason.SKIPPED):
			if host != null and host.signals != null:
				host.signals.publish("GraphFinished", str(run.graph_id))

	func _apply_progress(run: GuideRun, reason: int) -> void:
		if host.progress == null or reason == GDGuideData.GuideExitReason.ABORTED:
			return
		if reason == GDGuideData.GuideExitReason.COMPLETED:
			host.progress.mark_completed(run.graph_id)
		elif reason == GDGuideData.GuideExitReason.SKIPPED:
			host.progress.mark_skipped(run.graph_id)
		host.progress.flush()

	# ── Input Consumption & Watermark ──

	func _ensure_hooks() -> void:
		if host != null and host.signals != null and not _signal_connected:
			host.signals.raised.connect(_on_signal_raised)
			_signal_connected = true
		if host != null:
			host.bind_target_click(Callable(self, "_on_target_clicked"))
			host.bind_skip(Callable(self, "request_skip"))

	func _on_signal_raised(full_key: String) -> void:
		if not is_running or full_key.is_empty():
			return
		_add_input("signal", full_key, 0)

	func _on_target_clicked() -> void:
		if not is_running:
			return
		_add_input("click", "", current_run.active_node_id)

	func _add_input(kind: String, key: String, nid: int) -> void:
		if _inputs.size() >= 64:
			_inputs.pop_front()
		_input_seq += 1
		_inputs.append({
			"seq": _input_seq,
			"kind": kind,
			"key": key,
			"node_id": nid,
			"consumed": false,
		})

	func _try_consume_signal(run: GuideRun, expected: String) -> bool:
		if not _is_live(run) or expected.is_empty():
			return false
		for i in range(_inputs.size()):
			var inp := _inputs[i]
			if bool(inp["consumed"]) or str(inp["kind"]) != "signal" or int(inp["seq"]) <= run.node_enter_seq:
				continue
			var pub_key := str(inp["key"])
			var matched := host.signals.matches(pub_key, expected) if (host != null and host.signals != null) else GDGuideData.GuideSignalKeys.matches(pub_key, expected)
			if not matched:
				continue
			inp["consumed"] = true
			if int(inp["seq"]) > _consumed_seq:
				_consumed_seq = int(inp["seq"])
			_record_trace(run, GDGuideData.GuideTraceKind.LOG, run.active_node_id, run.get_phase(run.active_node_id), GDGuideData.GuidePortKind.EXEC_OUT, 0, "收到事件 " + pub_key)
			return true
		return false

	func _consume_click(run: GuideRun) -> bool:
		if not _is_live(run):
			return false
		for i in range(_inputs.size()):
			var inp := _inputs[i]
			if bool(inp["consumed"]) or str(inp["kind"]) != "click" or int(inp["seq"]) <= run.node_enter_seq or int(inp["node_id"]) != run.active_node_id:
				continue
			inp["consumed"] = true
			if int(inp["seq"]) > _consumed_seq:
				_consumed_seq = int(inp["seq"])
			_record_trace(run, GDGuideData.GuideTraceKind.LOG, run.active_node_id, run.get_phase(run.active_node_id), GDGuideData.GuidePortKind.EXEC_OUT, 0, "收到点击")
			return true
		return false

	func _next_enter_seq(run: GuideRun) -> int:
		if _consumed_seq > 0:
			return _consumed_seq
		match _invocation:
			"enter": return run.node_enter_seq
			"tick": return _tick_watermark
			_: return _input_seq

	func _expire_inputs(run: GuideRun, enter_count_at_tick_start: int) -> void:
		if not _is_live(run):
			_inputs.clear()
			return
		var drop_up_to := _tick_watermark if run.enter_count == enter_count_at_tick_start else run.node_enter_seq
		for i in range(_inputs.size() - 1, -1, -1):
			var inp := _inputs[i]
			if bool(inp["consumed"]) or int(inp["seq"]) <= drop_up_to:
				_inputs.remove_at(i)

	func _set_phase(run: GuideRun, nid: int, ph: int, msg: String) -> void:
		run.set_phase(nid, ph)
		_record_trace(run, GDGuideData.GuideTraceKind.PHASE, nid, ph, GDGuideData.GuidePortKind.EXEC_OUT, 0, msg)

	func _record_trace(run: GuideRun, kind: int, nid: int, ph: int, port: int, to_nid: int, msg: String) -> void:
		_trace_seq += 1
		var evt := GuideTraceEvent.new(
			_trace_seq,
			kind,
			run.graph_id if run != null else 0,
			run.run_id if run != null else 0,
			nid,
			ph,
			port,
			to_nid,
			run.total_elapsed if run != null else 0.0,
			msg
		)
		var cap := maxi(16, options.trace_capacity)
		if _trace.size() >= cap:
			_trace.pop_front()
		_trace.append(evt)
		traced.emit(evt)


# ─────────────────────── GuideTriggerSystem ───────────────────────

class GuideTriggerSystem extends RefCounted:
	var runner: GuideRunner = null
	var graphs: Array[GDGuideGraphRes] = []
	var eligible_graphs: Array[GDGuideGraphRes] = []
	var diagnostics: Dictionary = {} # graph_id -> {"event": String, "message": String, "rows": Array}

	var _by_event: Dictionary = {} # event_key -> Array[GuideGraphRes]
	var _started: Dictionary = {} # graph_id -> true
	var _pending: Array[String] = []
	var _dispatching: bool = false
	var _disposed: bool = false

	func _init(p_runner: GuideRunner, p_graphs: Array) -> void:
		runner = p_runner
		for g in p_graphs:
			if g is GDGuideGraphRes:
				graphs.append(g)
		graphs.sort_custom(func(a: GDGuideGraphRes, b: GDGuideGraphRes) -> bool:
			if a.priority == b.priority:
				return a.graph_id < b.graph_id
			return a.priority > b.priority
		)
		runner.graph_started.connect(func(evt: Dictionary) -> void:
			_started[int(evt.get("graph_id", 0))] = true
			refresh_candidates()
		)
		runner.graph_finished.connect(func(_evt: Dictionary) -> void:
			refresh_candidates()
		)
		if runner.host != null and runner.host.signals != null:
			runner.host.signals.raised.connect(_on_signal)
		refresh_candidates()

	func refresh_candidates() -> void:
		if _disposed:
			return
		eligible_graphs.clear()
		_by_event.clear()
		for g in graphs:
			if not bool(_can_trigger(g).get("ok", false)):
				continue
			var entry := g.find_atom(g.find_entry_id()) as GDGuideAtoms.EntryAtom
			var sp := GDGuideData.GuideSignalKeys.split(entry.trigger_event.key)
			var k := str(sp["key"])
			if not _by_event.has(k):
				_by_event[k] = []
			(_by_event[k] as Array).append(g)
			eligible_graphs.append(g)

	func try_trigger_graph(p_graph_id: int) -> Dictionary:
		if _disposed or runner.is_disposed:
			return {"ok": false, "message": "引导服务已关闭"}
		if runner.is_running or _dispatching:
			return {"ok": false, "message": "已有引导正在运行，请先完成或结束当前引导"}
		var target_g: GDGuideGraphRes = null
		for g in graphs:
			if g != null and g.graph_id == p_graph_id:
				target_g = g
				break
		var check := _can_trigger(target_g)
		if not bool(check.get("ok", false)):
			return {"ok": false, "message": str(check.get("reason", ""))}
		var entry := target_g.find_atom(target_g.find_entry_id()) as GDGuideAtoms.EntryAtom
		var started := _dispatch_graph(target_g, entry.trigger_event.key)
		var msg := ("已发送 %s，触发「%s」" % [entry.trigger_event.key, target_g.display_name]) if started else "触发未启动，请检查运行轨迹和图校验结果"
		return {"ok": started, "message": msg}

	func check_preconditions(g: GDGuideGraphRes, sig: String = "") -> GDGuideData.GuideConditionResult:
		var entry := g.find_atom(g.find_entry_id()) as GDGuideAtoms.EntryAtom
		if entry == null:
			diagnostics[g.graph_id] = {"event": sig, "message": "缺少入口", "rows": []}
			return GDGuideData.GuideConditionResult.new(false, "缺少入口")
		var rows_out: Array[GDGuideData.GuideConditionResult] = []
		var res := runner.host.conditions.evaluate_rows(entry.conditions, {"host": runner.host, "graph_id": g.graph_id}, rows_out)
		diagnostics[g.graph_id] = {
			"event": sig,
			"message": res.error if not res.error.is_empty() else ("前置条件通过" if res.satisfied else "前置条件未满足"),
			"rows": rows_out,
		}
		return res

	func dispose() -> void:
		if _disposed:
			return
		_disposed = true
		if runner != null and runner.host != null and runner.host.signals != null:
			if runner.host.signals.raised.is_connected(_on_signal):
				runner.host.signals.raised.disconnect(_on_signal)
		eligible_graphs.clear()
		_by_event.clear()
		_pending.clear()

	func _can_trigger(g: GDGuideGraphRes) -> Dictionary:
		if g == null:
			return {"ok": false, "reason": "当前引导不在已加载候选图中"}
		var p := runner.host.progress
		if not g.enabled:
			return {"ok": false, "reason": "引导未启用"}
		if g.schema_version != GDGuideGraphRes.CURRENT_SCHEMA_VERSION:
			return {"ok": false, "reason": "引导图需要先迁移数据版本"}
		if p != null and p.is_graph_completed(g.graph_id):
			return {"ok": false, "reason": "该引导已完成"}
		if p != null and p.is_graph_skipped(g.graph_id):
			return {"ok": false, "reason": "该引导已跳过"}
		if _started.has(g.graph_id):
			return {"ok": false, "reason": "该引导本次会话已触发"}
		if runner.is_suspended(g.graph_id):
			return {"ok": false, "reason": "该引导处于挂起状态"}
		var entry := g.find_atom(g.find_entry_id()) as GDGuideAtoms.EntryAtom
		if entry == null or entry.trigger_event == null or entry.trigger_event.is_empty:
			return {"ok": false, "reason": "入口未配置触发事件"}
		if _resume_node(g) > 0:
			return {"ok": true, "reason": ""}
		var pre := check_preconditions(g)
		if pre.success and pre.satisfied:
			return {"ok": true, "reason": ""}
		return {"ok": false, "reason": pre.error if not pre.error.is_empty() else "前置条件未满足"}

	func _resume_node(g: GDGuideGraphRes) -> int:
		var nid := runner.host.progress.get_resume_node_id(g.graph_id) if runner.host.progress != null else 0
		var a := g.find_atom(nid)
		return nid if (a != null and a.is_resume_point and g.is_reachable_from_entry(nid)) else 0

	func _on_signal(sig: String) -> void:
		if _disposed or runner.is_disposed or runner.is_running:
			return
		if _pending.size() >= 64:
			return
		_pending.append(sig)
		if _dispatching:
			return
		_dispatching = true
		var budget := 64
		while not _pending.is_empty() and budget > 0:
			budget -= 1
			var next_s := _pending.pop_front()
			if not runner.is_running:
				_dispatch(next_s)
		_pending.clear()
		_dispatching = false

	func _dispatch(sig: String) -> void:
		var sp := GDGuideData.GuideSignalKeys.split(sig)
		var k := str(sp["key"])
		if not _by_event.has(k):
			return
		var snapshot: Array = (_by_event[k] as Array).duplicate()
		for g in snapshot:
			if _dispatch_graph(g, sig):
				return

	func _dispatch_graph(g: GDGuideGraphRes, sig: String) -> bool:
		if not bool(_can_trigger(g).get("ok", false)):
			refresh_candidates()
			return false
		var entry := g.find_atom(g.find_entry_id()) as GDGuideAtoms.EntryAtom
		if entry == null or entry.trigger_event.is_empty or not GDGuideData.GuideSignalKeys.matches(sig, entry.trigger_event.key):
			return false
		var resume_id := _resume_node(g)
		if resume_id == 0:
			var check := check_preconditions(g, sig)
			if not check.success or not check.satisfied:
				return false
		return runner.try_start(g, resume_id)
