@tool
class_name GDGuideServices
extends RefCounted

## 新手引导 Host 接口、内存信号总线、内存进度存储（c=...;r=...;s=...;p=... 同构编码）、条件注册表与内置条件集
## 对应 IGuideHost / GuideMemorySignalBus / GuideMemoryProgressStore / GuideConditionRegistry / GuideBuiltinConditions

class GuideMemorySignalBus extends RefCounted:
	signal raised(full_key: String)

	func publish(key: String, arg: String = "") -> void:
		var full := GDGuideData.GuideSignalKeys.compose(key, arg)
		if not full.is_empty():
			raised.emit(full)

	func matches(published: String, expected: String) -> bool:
		return GDGuideData.GuideSignalKeys.matches(published, expected)


class GuideMemoryProgressStore extends RefCounted:
	var player_key: String = ""
	var is_dirty: bool = false
	var flush_count: int = 0
	var _on_flush: Callable = Callable()

	var _players: Dictionary = {} # player_key -> {"completed": Dictionary, "skipped": Dictionary, "resume": Dictionary, "checkpoints": Dictionary}
	var _current: Dictionary = {}

	func _init(p_on_flush: Callable = Callable()) -> void:
		_on_flush = p_on_flush
		bind("")

	func bind(p_player_key: String) -> void:
		player_key = p_player_key
		if not _players.has(player_key):
			_players[player_key] = {
				"completed": {},
				"skipped": {},
				"resume": {},
				"checkpoints": {},
			}
		_current = _players[player_key]

	func is_graph_completed(graph_id: int) -> bool:
		return (_current["completed"] as Dictionary).has(graph_id)

	func is_graph_skipped(graph_id: int) -> bool:
		return (_current["skipped"] as Dictionary).has(graph_id)

	func get_resume_node_id(graph_id: int) -> int:
		return int((_current["resume"] as Dictionary).get(graph_id, 0))

	func set_resume_node_id(graph_id: int, node_id: int) -> void:
		var res_map := _current["resume"] as Dictionary
		if node_id <= 0:
			if res_map.erase(graph_id):
				is_dirty = true
			return
		if int(res_map.get(graph_id, 0)) == node_id:
			return
		res_map[graph_id] = node_id
		is_dirty = true

	func has_checkpoint(graph_id: int, cp_name: String) -> bool:
		if cp_name.is_empty():
			return false
		var cp_map := _current["checkpoints"] as Dictionary
		if not cp_map.has(graph_id):
			return false
		return (cp_map[graph_id] as Dictionary).has(cp_name)

	func set_checkpoint(graph_id: int, cp_name: String) -> void:
		if not _is_valid_checkpoint_name(cp_name):
			GDGameLogger.log_warning("[Guide] 检查点名不能为空，也不能含 , ; : = 空白：" + str(cp_name))
			return
		var cp_map := _current["checkpoints"] as Dictionary
		if not cp_map.has(graph_id):
			cp_map[graph_id] = {}
		var set_dict := cp_map[graph_id] as Dictionary
		if not set_dict.has(cp_name):
			set_dict[cp_name] = true
			is_dirty = true

	func mark_completed(graph_id: int) -> void:
		var c_map := _current["completed"] as Dictionary
		var s_map := _current["skipped"] as Dictionary
		var r_map := _current["resume"] as Dictionary
		var changed := not c_map.has(graph_id)
		c_map[graph_id] = true
		if s_map.erase(graph_id):
			changed = true
		if r_map.erase(graph_id):
			changed = true
		if changed:
			is_dirty = true

	func mark_skipped(graph_id: int) -> void:
		var c_map := _current["completed"] as Dictionary
		var s_map := _current["skipped"] as Dictionary
		var r_map := _current["resume"] as Dictionary
		var changed := not s_map.has(graph_id)
		s_map[graph_id] = true
		if c_map.erase(graph_id):
			changed = true
		if r_map.erase(graph_id):
			changed = true
		if changed:
			is_dirty = true

	func clear_graph(graph_id: int) -> void:
		var changed := false
		if (_current["completed"] as Dictionary).erase(graph_id): changed = true
		if (_current["skipped"] as Dictionary).erase(graph_id): changed = true
		if (_current["resume"] as Dictionary).erase(graph_id): changed = true
		if (_current["checkpoints"] as Dictionary).erase(graph_id): changed = true
		if changed:
			is_dirty = true

	func clear_all() -> void:
		(_current["completed"] as Dictionary).clear()
		(_current["skipped"] as Dictionary).clear()
		(_current["resume"] as Dictionary).clear()
		(_current["checkpoints"] as Dictionary).clear()
		is_dirty = true

	func flush() -> void:
		flush_count += 1
		if not is_dirty:
			return
		is_dirty = false
		if _on_flush.is_valid():
			_on_flush.call(player_key, encode())

	func encode() -> String:
		var c_ids := _sorted_int_keys(_current["completed"] as Dictionary)
		var c_parts: PackedStringArray = PackedStringArray()
		for id in c_ids:
			c_parts.append(str(id))

		var r_map := _current["resume"] as Dictionary
		var r_ids := _sorted_int_keys(r_map)
		var r_parts: PackedStringArray = PackedStringArray()
		for gid in r_ids:
			r_parts.append("%d:%d" % [gid, int(r_map[gid])])

		var s_ids := _sorted_int_keys(_current["skipped"] as Dictionary)
		var s_parts: PackedStringArray = PackedStringArray()
		for id in s_ids:
			s_parts.append(str(id))

		var cp_map := _current["checkpoints"] as Dictionary
		var cp_ids := _sorted_int_keys(cp_map)
		var p_parts: PackedStringArray = PackedStringArray()
		for gid in cp_ids:
			var names_dict := cp_map[gid] as Dictionary
			var names: Array[String] = []
			for k in names_dict.keys():
				names.append(str(k))
			names.sort()
			for n in names:
				p_parts.append("%d:%s" % [gid, n])

		return "c=%s;r=%s;s=%s;p=%s" % [
			",".join(c_parts),
			",".join(r_parts),
			",".join(s_parts),
			",".join(p_parts),
		]

	func decode(data: String) -> void:
		clear_all()
		is_dirty = false
		if data.is_empty():
			return
		for section in data.split(";"):
			var eq := section.find("=")
			if eq <= 0:
				continue
			var tag := section.substr(0, eq).strip_edges()
			var body := section.substr(eq + 1)
			if body.is_empty():
				continue
			for item in body.split(","):
				_decode_item(tag, item.strip_edges())

	func _decode_item(tag: String, item: String) -> void:
		if item.is_empty():
			return
		match tag:
			"c":
				if item.is_valid_int():
					(_current["completed"] as Dictionary)[item.to_int()] = true
			"s":
				if item.is_valid_int():
					(_current["skipped"] as Dictionary)[item.to_int()] = true
			"r":
				var colon := item.find(":")
				if colon > 0:
					var g_str := item.substr(0, colon)
					var n_str := item.substr(colon + 1)
					if g_str.is_valid_int() and n_str.is_valid_int() and n_str.to_int() > 0:
						(_current["resume"] as Dictionary)[g_str.to_int()] = n_str.to_int()
			"p":
				var colon := item.find(":")
				if colon > 0:
					var g_str := item.substr(0, colon)
					var cp_name := item.substr(colon + 1)
					if g_str.is_valid_int() and _is_valid_checkpoint_name(cp_name):
						var gid := g_str.to_int()
						var cp_map := _current["checkpoints"] as Dictionary
						if not cp_map.has(gid):
							cp_map[gid] = {}
						(cp_map[gid] as Dictionary)[cp_name] = true

	static func _is_valid_checkpoint_name(cp_name: String) -> bool:
		if cp_name.is_empty():
			return false
		for i in range(cp_name.length()):
			var ch := cp_name[i]
			if ch == "," or ch == ";" or ch == ":" or ch == "=" or ch == " " or ch == "\t" or ch == "\n" or ch == "\r":
				return false
		return true

	static func _sorted_int_keys(d: Dictionary) -> Array[int]:
		var arr: Array[int] = []
		for k in d.keys():
			arr.append(int(k))
		arr.sort()
		return arr


# ─────────────────────── GuideConditionRegistry ───────────────────────

class GuideConditionRegistry extends RefCounted:
	var _entries: Dictionary = {} # id -> {"has_arg": bool, "arg_type": int, "result_type": int, "display": String, "category": String, "evaluate": Callable}
	var registration_errors: Array[String] = []
	var log_registration_errors: bool = true

	func _init(include_builtins: bool = true) -> void:
		if include_builtins:
			_register_builtins()

	func contains(id: String) -> bool:
		return _entries.has(id)

	func get_all_ids() -> Array:
		return _entries.keys()

	func get_entry_info(id: String) -> Dictionary:
		return _entries.get(id, {})

	func try_get_signature(id: String) -> Dictionary:
		if not _entries.has(id):
			return {"ok": false, "has_arg": false, "arg_type": 0, "result_type": 0}
		var e: Dictionary = _entries[id]
		return {
			"ok": true,
			"has_arg": bool(e["has_arg"]),
			"arg_type": int(e["arg_type"]),
			"result_type": int(e["result_type"]),
		}

	func register_condition(
		id: String,
		has_arg: bool,
		arg_type: int,
		result_type: int,
		evaluate_cb: Callable,
		display_name: String = "",
		category: String = "引导"
	) -> void:
		if id.strip_edges().is_empty():
			return
		if _entries.has(id):
			var err := "条件重复登记：" + id
			registration_errors.append(err)
			if log_registration_errors:
				GDGameLogger.log_error_p("[Guide] " + err)
			return
		_entries[id] = {
			"has_arg": has_arg,
			"arg_type": arg_type,
			"result_type": result_type,
			"display": display_name if not display_name.is_empty() else id,
			"category": category,
			"evaluate": evaluate_cb,
		}

	func try_evaluate(id: String, arg: GDGuideData.GuideValue, ctx_dict: Dictionary) -> Dictionary:
		if not _entries.has(id):
			return {"ok": false, "result": null, "error": "条件未登记：" + str(id)}
		var e: Dictionary = _entries[id]
		if bool(e["has_arg"]) and (arg == null or arg.type != int(e["arg_type"])):
			return {"ok": false, "result": null, "error": "条件参数类型不符：" + id}
		var cb: Callable = e["evaluate"]
		var res_val: GDGuideData.GuideValue = cb.call(ctx_dict, arg)
		if res_val == null or res_val.type != int(e["result_type"]):
			return {"ok": false, "result": null, "error": "条件结果类型不符：" + id}
		return {"ok": true, "result": res_val, "error": ""}

	func evaluate_rows(
		rows: Array,
		ctx_dict: Dictionary,
		out_results: Array[GDGuideData.GuideConditionResult] = []
	) -> GDGuideData.GuideConditionResult:
		out_results.clear()
		var all_ok := true
		var first_err := ""
		for i in range(rows.size()):
			var row_res := evaluate_expr(rows[i], ctx_dict)
			out_results.append(row_res)
			all_ok = all_ok and row_res.satisfied and row_res.success
			if not row_res.success and first_err.is_empty():
				first_err = "条件第 %d 行：%s" % [i + 1, row_res.error]
		return GDGuideData.GuideConditionResult.new(all_ok, first_err)

	func evaluate_expr(expr: GDGuideData.GuideConditionExpr, ctx_dict: Dictionary) -> GDGuideData.GuideConditionResult:
		if expr == null or expr.left == null:
			return GDGuideData.GuideConditionResult.new(false, "条件表达式为空")
		var left_eval := try_evaluate(expr.left.condition_id, expr.left.arg, ctx_dict)
		if not bool(left_eval.get("ok", false)):
			return GDGuideData.GuideConditionResult.new(false, str(left_eval.get("error", "")))
		var left_val: GDGuideData.GuideValue = left_eval["result"]
		var right_val: GDGuideData.GuideValue = expr.right.value if expr.right != null else GDGuideData.GuideValue.new()
		if expr.right != null and expr.right.kind == GDGuideData.GuideOperandKind.CONDITION:
			var right_eval := try_evaluate(expr.right.condition.condition_id, expr.right.condition.arg, ctx_dict)
			if not bool(right_eval.get("ok", false)):
				return GDGuideData.GuideConditionResult.new(false, str(right_eval.get("error", "")))
			right_val = right_eval["result"]
		elif expr.right == null or expr.right.kind != GDGuideData.GuideOperandKind.VALUE:
			return GDGuideData.GuideConditionResult.new(false, "未知右参数类型")

		var cmp := GDGuideData.GuideConditionEvaluator.compare_values(left_val, expr.op, right_val)
		return GDGuideData.GuideConditionResult.new(cmp.satisfied, cmp.error, left_val, right_val, true)

	func validate_expr(expr: GDGuideData.GuideConditionExpr) -> String:
		if expr == null or expr.left == null:
			return "条件表达式为空"
		var l_err := _validate_call(expr.left)
		if not str(l_err.get("error", "")).is_empty():
			return str(l_err["error"])
		var l_type := int(l_err["result_type"])
		var r_val := expr.right.value if expr.right != null else GDGuideData.GuideValue.new()
		if expr.right != null and expr.right.kind == GDGuideData.GuideOperandKind.CONDITION:
			var r_err := _validate_call(expr.right.condition)
			if not str(r_err.get("error", "")).is_empty():
				return str(r_err["error"])
			r_val = GDGuideData.GuideValue.new()
			r_val.type = int(r_err["result_type"])
		elif expr.right == null or expr.right.kind != GDGuideData.GuideOperandKind.VALUE:
			return "未知右参数类型"

		var dummy_left := GDGuideData.GuideValue.new()
		dummy_left.type = l_type
		return GDGuideData.GuideConditionEvaluator.compare_values(dummy_left, expr.op, r_val).error

	func _validate_call(call_obj: GDGuideData.GuideConditionCall) -> Dictionary:
		if call_obj == null:
			return {"error": "条件调用为空", "result_type": 0}
		var sig := try_get_signature(call_obj.condition_id)
		if not bool(sig.get("ok", false)):
			return {"error": "条件未登记：" + str(call_obj.condition_id), "result_type": 0}
		if bool(sig["has_arg"]) and (call_obj.arg == null or call_obj.arg.type != int(sig["arg_type"])):
			return {"error": "条件参数类型不符：" + call_obj.condition_id, "result_type": 0}
		if bool(sig["has_arg"]) and int(sig["arg_type"]) == GDGuideData.GuideValueType.FLOAT:
			if is_nan(call_obj.arg.float_value) or is_inf(call_obj.arg.float_value):
				return {"error": "条件参数必须是有限数：" + call_obj.condition_id, "result_type": 0}
		return {"error": "", "result_type": int(sig["result_type"])}

	func _register_builtins() -> void:
		register_condition(
			"io.guide.blackboard_has_key",
			true,
			GDGuideData.GuideValueType.STRING,
			GDGuideData.GuideValueType.BOOL,
			func(ctx: Dictionary, arg: GDGuideData.GuideValue) -> GDGuideData.GuideValue:
				var bb: GDGuideData.GuideBlackboard = ctx.get("blackboard", null)
				var has_k := bb != null and bool(bb.try_get(arg.string_value).get("ok", false))
				return GDGuideData.GuideValue.from_bool(has_k),
			"黑板存在键{0}（兼容）"
		)
		register_condition(
			"io.guide.has_checkpoint",
			true,
			GDGuideData.GuideValueType.STRING,
			GDGuideData.GuideValueType.BOOL,
			func(ctx: Dictionary, arg: GDGuideData.GuideValue) -> GDGuideData.GuideValue:
				var host: GuideHost = ctx.get("host", null)
				var gid := int(ctx.get("graph_id", 0))
				var ok := host != null and host.progress != null and host.progress.has_checkpoint(gid, arg.string_value)
				return GDGuideData.GuideValue.from_bool(ok),
			"有检查点{0}"
		)
		register_condition(
			"io.guide.blackboard",
			true,
			GDGuideData.GuideValueType.STRING,
			GDGuideData.GuideValueType.STRING,
			func(ctx: Dictionary, arg: GDGuideData.GuideValue) -> GDGuideData.GuideValue:
				var bb: GDGuideData.GuideBlackboard = ctx.get("blackboard", null)
				var res := bb.try_get(arg.string_value) if bb != null else {"ok": false, "value": ""}
				return GDGuideData.GuideValue.from_string(str(res.get("value", "")) if bool(res.get("ok", false)) else ""),
			"黑板值{0}"
		)
		register_condition(
			"io.guide.graph_done",
			true,
			GDGuideData.GuideValueType.INT,
			GDGuideData.GuideValueType.BOOL,
			func(ctx: Dictionary, arg: GDGuideData.GuideValue) -> GDGuideData.GuideValue:
				var host: GuideHost = ctx.get("host", null)
				var p := host.progress if host != null else null
				var done := p != null and (p.is_graph_completed(arg.int_value) or p.is_graph_skipped(arg.int_value))
				return GDGuideData.GuideValue.from_bool(done),
			"前置图{0}已结束"
		)
		register_condition(
			"io.guide.host_predicate",
			true,
			GDGuideData.GuideValueType.STRING,
			GDGuideData.GuideValueType.BOOL,
			func(ctx: Dictionary, arg: GDGuideData.GuideValue) -> GDGuideData.GuideValue:
				var host: GuideHost = ctx.get("host", null)
				var parts := GDGuideData.GuideEventRef.parse(arg.string_value)
				if host == null:
					return GDGuideData.GuideValue.from_bool(false)
				var pred := host.try_evaluate_predicate(parts.event_name, parts.arg)
				return GDGuideData.GuideValue.from_bool(bool(pred.get("result", false))),
			"宿主谓词{0}（兼容）"
		)
		register_condition(
			"io.guide.is_new_player",
			false,
			0,
			GDGuideData.GuideValueType.BOOL,
			func(ctx: Dictionary, _arg: GDGuideData.GuideValue) -> GDGuideData.GuideValue:
				var host: GuideHost = ctx.get("host", null)
				return GDGuideData.GuideValue.from_bool(host != null and host.is_new_player()),
			"是新玩家（兼容）"
		)
		register_condition(
			"io.guide.player_level",
			false,
			0,
			GDGuideData.GuideValueType.INT,
			func(ctx: Dictionary, _arg: GDGuideData.GuideValue) -> GDGuideData.GuideValue:
				var host: GuideHost = ctx.get("host", null)
				return GDGuideData.GuideValue.from_int(host.get_player_level() if host != null else 0),
			"玩家等级（兼容）"
		)
		register_condition(
			"io.guide.sample_has_coin",
			false,
			0,
			GDGuideData.GuideValueType.BOOL,
			func(ctx: Dictionary, _arg: GDGuideData.GuideValue) -> GDGuideData.GuideValue:
				var host: GuideHost = ctx.get("host", null)
				var pred := host.try_evaluate_predicate("sample_has_coin", "") if host != null else {"ok": false, "result": false}
				return GDGuideData.GuideValue.from_bool(bool(pred.get("result", false))),
			"示例：持有金币"
		)


# ─────────────────────── GuideHost (IGuideHost 默认可扩展实现) ───────────────────────

class GuideHost extends RefCounted:
	var progress: GuideMemoryProgressStore = GuideMemoryProgressStore.new()
	var signals: GuideMemorySignalBus = GuideMemorySignalBus.new()
	var conditions: GuideConditionRegistry = GuideConditionRegistry.new(true)
	var player_level: int = 1
	var new_player: bool = true
	var predicates: Dictionary = {} # key -> bool or Callable
	var ready_panels: Dictionary = {} # panel_name -> bool
	var target_hits: Dictionary = {} # target_str -> int (hit count)

	var _on_target_click: Callable = Callable()
	var _on_skip: Callable = Callable()

	func is_new_player() -> bool:
		return new_player

	func get_player_level() -> int:
		return player_level

	func set_predicate(key: String, val: Variant) -> void:
		predicates[key] = val

	func try_evaluate_predicate(key: String, arg: String = "") -> Dictionary:
		var full := GDGuideData.GuideSignalKeys.compose(key, arg)
		if predicates.has(full):
			var v = predicates[full]
			return {"ok": true, "result": bool(v.call(arg)) if v is Callable else bool(v)}
		if predicates.has(key):
			var v = predicates[key]
			return {"ok": true, "result": bool(v.call(arg)) if v is Callable else bool(v)}
		return {"ok": false, "result": false}

	func is_panel_ready(panel_key: String) -> bool:
		if panel_key.is_empty():
			return true
		if not ready_panels.has(panel_key):
			return true
		return bool(ready_panels[panel_key])

	func locate_targets(target: GDGuideData.GuideTargetRef) -> int:
		if target == null or target.is_none:
			return 0
		var key := target.format_target()
		if target_hits.has(key):
			return int(target_hits[key])
		return 1

	func bind_target_click(cb: Callable) -> void:
		_on_target_click = cb

	func bind_skip(cb: Callable) -> void:
		_on_skip = cb

	func simulate_click() -> void:
		if _on_target_click.is_valid():
			_on_target_click.call()

	func simulate_skip() -> void:
		if _on_skip.is_valid():
			_on_skip.call()

	func dispose() -> void:
		_on_target_click = Callable()
		_on_skip = Callable()
		if conditions != null:
			conditions._entries.clear()
		predicates.clear()
