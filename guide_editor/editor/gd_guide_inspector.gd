@tool
class_name GDGuideInspector
extends RefCounted

## 引导图右侧属性：图头、节点表单、条件列表。字段直接写模型，提交由表单的 committed 信号转给页面；
## 增删条件行这类结构改动调 ctx.commit，表单随结构指纹变化重建。

const LABELS := {
	"display_name": "节点名", "exit_on_timeout": "超时后结束", "exit_on_condition_fail": "否口未连记暂缓",
	"reason": "结束原因", "text": "文案", "speaker": "说话人", "text_anchor": "文案位置",
	"backdrop_alpha": "遮罩浓度", "auto_advance_sec": "自动继续", "condition": "等待什么",
	"delay_sec": "延迟", "show_skip": "显示跳过", "raw_timeout_sec": "超时",
	"interval_sec": "检查间隔", "show_text": "显示文案", "finger_anchor": "手指位置",
	"finger_anchor_offset": "手指偏移", "complete_mode": "完成方式", "click_mode": "点击方式",
	"highlight_scale": "高亮缩放", "show_arrow": "显示箭头", "checkpoint": "检查点",
	"kind": "目标类型", "panel": "面板", "widget": "控件", "world_key": "世界键",
	"rule": "动态规则", "wait_panel": "等待面板",
}

const ANCHORS := [["自动", 0], ["上", 1], ["下", 2], ["左", 3], ["右", 4], ["居中", 5], ["不显示", 6]]
const ENUMS := {
	"reason": [["完成", 0], ["跳过", 1], ["暂缓", 2], ["失败", 3]],
	"text_anchor": ANCHORS,
	"finger_anchor": ANCHORS,
	## 谓词是 v1 写法，迁移后统一变成“条件”，所以不再提供。
	"condition": [["事件", 0], ["延迟", 1], ["条件", 3]],
	"complete_mode": [["点中目标", 0], ["收到事件", 1]],
	"click_mode": [["不可点", 0], ["转发到真目标", 1], ["吞掉点击", 2]],
	"kind": [["无", 0], ["UI 控件", 1], ["世界物体", 2], ["屏幕锚点", 3]],
}
const BRANCH_SOURCES := [["黑板等于", 0], ["检查点", 1], ["宿主谓词", 2], ["新玩家", 3], ["等级至少", 4]]
const OPS := [["等于", 0], ["不等于", 1], ["大于", 2], ["大于等于", 3], ["小于", 4], ["小于等于", 5]]

const NUMBERS := {
	"backdrop_alpha": {"min": 0.0, "max": 1.0, "step": 0.05},
	"highlight_scale": {"min": 0.1, "max": 5.0, "step": 0.05},
	"delay_sec": {"min": 0.0, "step": 0.1, "suffix": " 秒"},
	"auto_advance_sec": {"min": 0.0, "step": 0.1, "suffix": " 秒", "tip": "0 表示等玩家点击"},
	"raw_timeout_sec": {"min": 0.0, "step": 0.5, "suffix": " 秒", "tip": "0 表示不超时"},
	"interval_sec": {"min": 0.0, "step": 0.05, "suffix": " 秒"},
}

## 每种节点的字段顺序。"#名字" 开一个分组；"@xxx" 是专用编辑器（事件键、条件、目标、子图…）。
const LAYOUT := {
	"io.guide.entry": ["@trigger", "@conditions"],
	"io.guide.exit": ["reason"],
	"io.guide.branch": ["@conditions", "@branch_source"],
	"io.guide.subgraph": ["@subgraph"],
	"io.guide.narration": ["text", "speaker", "auto_advance_sec", "text_anchor", "backdrop_alpha"],
	"io.guide.lockwait": ["condition", "@event", "delay_sec", "raw_timeout_sec", "text", "show_skip", "backdrop_alpha", "@conditions"],
	"io.guide.wait_event": ["@event", "raw_timeout_sec"],
	"io.guide.wait_condition": ["interval_sec", "raw_timeout_sec", "@conditions"],
	"io.guide.delay": ["delay_sec"],
	"io.guide.strong": ["@target", "#完成", "complete_mode", "@event", "click_mode", "raw_timeout_sec",
		"#文案", "show_text", "text", "speaker", "text_anchor",
		"#表现", "finger_anchor", "finger_anchor_offset", "backdrop_alpha", "highlight_scale"],
	"io.guide.weak": ["@target", "#完成", "complete_mode", "@event", "raw_timeout_sec",
		"#文案", "show_text", "text", "speaker", "text_anchor",
		"#表现", "finger_anchor", "finger_anchor_offset", "show_arrow", "highlight_scale"],
	"io.guide.dialogue": ["text", "speaker", "backdrop_alpha", "@target"],
	"io.guide.list_focus": ["raw_timeout_sec", "@target"],
	"io.guide.checkpoint": ["checkpoint"],
	"io.guide.complete": [],
}


## 页面提供给表单的上下文。
class Context extends RefCounted:
	var graph: GDGuideGraphRes = null
	var conditions: GDGuideServices.GuideConditionRegistry = null
	var read_only: bool = false
	## func(label)：结构改动后提交。
	var commit: Callable = Callable()
	## func(node_id)：强弱引导互转。
	var convert: Callable = Callable()
	## func(new_id)：改图 ID（要查重）。
	var set_graph_id: Callable = Callable()


## 表单结构的指纹：模式、条件行、目标类型、可选的连线目标变了才重建。
static func node_key(graph: GDGuideGraphRes, atom: GDGuideAtoms.GuideAtom, read_only: bool) -> Array:
	var key: Array = [atom, read_only]
	for field in ["condition", "complete_mode", "show_text", "source"]:
		if field in atom:
			key.append(atom.get(field))
	var target: Variant = atom.get("target")
	if target is GDGuideData.GuideTargetRef:
		key.append(target.kind)
	var rows: Variant = atom.get("conditions")
	if rows is Array:
		for row in rows:
			key.append_array([row.left.condition_id, row.right.kind, row.right.condition.condition_id])
	## 自己的名字不算：改名后重建会让 Tab 丢焦点。
	for other in graph.atoms:
		key.append(other.id)
		if other != atom:
			key.append(other.title)
	if atom is GDGuideAtoms.SubgraphAtom:
		key.append_array(GDGuideEditing.find_all_graphs())
	return key


# ── 图头 ──

static func build_graph(form: GDForm, graph: GDGuideGraphRes, ctx: Context) -> void:
	form.live_note(func() -> String: return graph.display_name, &"text")
	form.note("引导图 · %s" % ("示例，只在内存里" if GDGuideSamples.is_sample(graph) else (graph.resource_path if not graph.resource_path.is_empty() else "尚未保存")))
	form.text("名称", func() -> String: return graph.raw_display_name, func(v: String) -> void: graph.set_display_name(v))
	form.integer("图 ID", func() -> int: return graph.graph_id, func(v: int) -> void: ctx.set_graph_id.call(v), {"min": 0})
	form.toggle("启用", func() -> bool: return graph.enabled, func(v: bool) -> void: graph.set_enabled(v))
	form.integer("优先级", func() -> int: return graph.priority, func(v: int) -> void: graph.set_priority(v), {"tip": "同一事件触发多张图时，先跑优先级高的"})
	form.toggle("允许跳过", func() -> bool: return graph.allow_skip, func(v: bool) -> void: graph.set_allow_skip(v))
	form.toggle("从入口恢复", func() -> bool: return graph.resume_from_entry, func(v: bool) -> void: graph.set_resume_from_entry(v),
		"恢复时从入口分支判断：中断后再次触发，从入口重新走分支，而不是从上次停下的节点续跑")
	form.live_note(func() -> String:
		return "%d 个节点 · %d 条连线 · 数据版本 v%d" % [graph.atoms.size(), graph.edges.size(), graph.schema_version]
	, &"muted")
	finish(form, ctx)


# ── 节点 ──

static func build_node(form: GDForm, atom: GDGuideAtoms.GuideAtom, ctx: Context) -> void:
	form.live_note(func() -> String: return atom.title, &"text")
	form.note("%s · #%d" % [atom.get_atom_display_name(), atom.id])
	if atom is GDGuideAtoms.MissingAtom:
		form.note("节点类型缺失：%s。恢复这个类，或清理缺失节点。" % (atom as GDGuideAtoms.MissingAtom).type_name, &"warn")
		finish(form, ctx)
		return
	if atom is GDGuideAtoms.GuideTargetAtom and not (atom as GDGuideAtoms.GuideTargetAtom).alternate_type_id.is_empty():
		var to_weak := atom is GDGuideAtoms.StrongGuideAtom
		form.button("转为弱引导" if to_weak else "转为强引导", func() -> void: ctx.convert.call(atom.id))
	_auto(form, atom, ["display_name"])
	var hidden := _hidden_fields(atom)
	for item: String in LAYOUT.get(atom.get_atom_id(), []):
		if item in hidden:
			continue
		if item.begins_with("#"):
			form.group(item.substr(1))
		elif item.begins_with("@"):
			_special(form, atom, item, ctx)
		else:
			_auto(form, atom, [item])
	_connections(form, atom, ctx)
	form.group("高级", true)
	_auto(form, atom, ["exit_on_timeout", "exit_on_condition_fail"])
	form.end_group()
	finish(form, ctx)


static func _auto(form: GDForm, target: Object, only: Array) -> void:
	form.auto(target, {"labels": LABELS, "enums": ENUMS, "numbers": NUMBERS, "setters": _setters(), "only": only})


## 有校验或联动的 setter 优先于直接赋值。
static func _setters() -> Dictionary:
	return {
		"display_name": func(a: Object, v: String) -> void: a.set_display_name(v),
		"reason": func(a: Object, v: int) -> void: a.set_reason(v),
		"delay_sec": func(a: Object, v: float) -> void: a.set_delay(v),
		"auto_advance_sec": func(a: Object, v: float) -> void: a.set_auto_advance(v),
		"show_text": func(a: Object, v: bool) -> void: a.set_show_text(v),
		"click_mode": func(a: Object, v: int) -> void: a.set_click_mode(v),
		"complete_mode": func(a: Object, v: int) -> void: a.set_completion(v, a.event_key),
		"raw_timeout_sec": _set_timeout,
	}


static func _set_timeout(atom: Object, seconds: float) -> void:
	if atom.has_method("set_timeout"):
		atom.call("set_timeout", seconds)
	else:
		atom.set("raw_timeout_sec", seconds)


static func _hidden_fields(atom: GDGuideAtoms.GuideAtom) -> Array:
	if atom is GDGuideAtoms.LockWaitAtom:
		match (atom as GDGuideAtoms.LockWaitAtom).condition:
			GDGuideData.GuideWaitCondition.DELAY:
				return ["@event", "@conditions"]
			GDGuideData.GuideWaitCondition.CONDITIONS:
				return ["@event", "delay_sec"]
		return ["delay_sec", "@conditions"]
	if atom is GDGuideAtoms.GuideTargetAtom:
		var target_atom := atom as GDGuideAtoms.GuideTargetAtom
		var hidden: Array = []
		if target_atom.complete_mode != GDGuideData.GuideCompleteMode.EVENT_KEY:
			hidden.append("@event")
		if not target_atom.show_text:
			hidden.append_array(["text", "speaker", "text_anchor"])
		return hidden
	return []


static func _special(form: GDForm, atom: GDGuideAtoms.GuideAtom, item: String, ctx: Context) -> void:
	match item:
		"@trigger":
			var entry := atom as GDGuideAtoms.EntryAtom
			form.text("触发事件",
				func() -> String: return entry.trigger_event.key if entry.trigger_event != null else "",
				func(v: String) -> void: entry.set_trigger_event(GDGuideData.GuideEventRef.parse(v)),
				{"placeholder": "留空表示手动启动", "tip": "事件名，或 事件名:参数"})
		"@event":
			form.text("完成事件" if atom is GDGuideAtoms.GuideTargetAtom else "事件",
				func() -> String: return atom.get("event_key"),
				func(v: String) -> void:
					if atom is GDGuideAtoms.GuideTargetAtom:
						(atom as GDGuideAtoms.GuideTargetAtom).set_completion(atom.get("complete_mode"), v)
					else:
						atom.call("set_event_key", v),
				{"placeholder": "例如 PanelReady", "tip": "事件名，或 事件名:参数"})
		"@conditions":
			form.group("前置条件" if atom is GDGuideAtoms.EntryAtom else "条件")
			conditions(form, atom.get("conditions"), ctx)
			form.end_group()
		"@target":
			form.group("目标")
			_target(form, atom)
			form.end_group()
		"@subgraph":
			_subgraph(form, atom as GDGuideAtoms.SubgraphAtom, ctx)
		"@branch_source":
			form.group("按来源生成条件", true)
			_branch_source(form, atom as GDGuideAtoms.BranchAtom)
			form.end_group()


static func _target(form: GDForm, atom: GDGuideAtoms.GuideAtom) -> void:
	if atom.get("target") == null:
		atom.set("target", GDGuideData.GuideTargetRef.new())
	var target: GDGuideData.GuideTargetRef = atom.get("target")
	var fields: Array = ["kind"]
	var labels := LABELS.duplicate()
	match target.kind:
		GDGuideData.GuideTargetKind.UI_WIDGET:
			fields.append_array(["panel", "widget", "rule", "wait_panel"])
		GDGuideData.GuideTargetKind.WORLD_ID:
			fields.append_array(["world_key", "rule", "wait_panel"])
		GDGuideData.GuideTargetKind.SCREEN_ANCHOR:
			fields.append_array(["widget", "wait_panel"])
			labels["widget"] = "锚点名"
	form.auto(target, {"labels": labels, "enums": ENUMS, "only": fields})


static func _subgraph(form: GDForm, atom: GDGuideAtoms.SubgraphAtom, ctx: Context) -> void:
	var candidates: Array[GDGuideGraphRes] = []
	for g in GDGuideEditing.find_all_graphs():
		if g != ctx.graph:
			candidates.append(g)
	if atom.graph is GDGuideGraphRes and not candidates.has(atom.graph):
		candidates.append(atom.graph)
	var items: Array = [["（未选择）", 0]]
	for i in range(candidates.size()):
		items.append(["%s  #%d" % [candidates[i].display_name, candidates[i].graph_id], i + 1])
	form.choice("子图", items,
		func() -> int: return candidates.find(atom.graph) + 1,
		func(v: int) -> void: atom.set_graph(candidates[v - 1] if v > 0 else null))


static func _branch_source(form: GDForm, atom: GDGuideAtoms.BranchAtom) -> void:
	var regenerate := func() -> void:
		match atom.source:
			GDGuideData.GuideBranchSource.BLACKBOARD_EQUALS:
				atom.set_blackboard_equals(atom.key, atom.value)
			GDGuideData.GuideBranchSource.CHECKPOINT:
				atom.set_checkpoint(atom.key)
			GDGuideData.GuideBranchSource.PREDICATE:
				atom.set_predicate(atom.key, atom.value)
			GDGuideData.GuideBranchSource.NEW_PLAYER:
				atom.set_new_player()
			GDGuideData.GuideBranchSource.LEVEL_AT_LEAST:
				atom.set_level_at_least(atom.level)
	form.note("改这里会重写上面的条件")
	form.choice("来源", BRANCH_SOURCES, func() -> int: return atom.source, func(v: int) -> void:
		atom.source = v
		regenerate.call()
	)
	if atom.source in [GDGuideData.GuideBranchSource.BLACKBOARD_EQUALS, GDGuideData.GuideBranchSource.CHECKPOINT, GDGuideData.GuideBranchSource.PREDICATE]:
		form.text("键", func() -> String: return atom.key, func(v: String) -> void:
			atom.key = v
			regenerate.call()
		)
	if atom.source in [GDGuideData.GuideBranchSource.BLACKBOARD_EQUALS, GDGuideData.GuideBranchSource.PREDICATE]:
		form.text("值", func() -> String: return atom.value, func(v: String) -> void:
			atom.value = v
			regenerate.call()
		)
	if atom.source == GDGuideData.GuideBranchSource.LEVEL_AT_LEAST:
		form.integer("等级", func() -> int: return atom.level, func(v: int) -> void:
			atom.level = v
			regenerate.call()
		, {"min": 0})


## 每个输出口选一个目标节点，和在画布上拖线是一回事。
static func _connections(form: GDForm, atom: GDGuideAtoms.GuideAtom, ctx: Context) -> void:
	var outs: Array[int] = []
	for p in atom.get_ports():
		if not p.is_input:
			outs.append(p.kind)
	if outs.is_empty():
		return
	form.group("连线")
	var items: Array = [["（未连）", 0]]
	for other in ctx.graph.atoms:
		if other != atom and other.has_port(GDGuideData.GuidePortKind.EXEC_IN):
			items.append(["%s  #%d" % [other.title, other.id], other.id])
	for port in outs:
		form.choice(GDGuideData.GuidePorts.label(port), items,
			func() -> int:
				var found := ctx.graph.try_get_edge(atom.id, port)
				return (found["edge"] as GDGuideData.GuideEdge).to_id if bool(found["ok"]) else 0,
			func(to_id: int) -> void:
				if to_id > 0:
					ctx.graph.connect_nodes(atom.id, port, to_id)
				else:
					ctx.graph.disconnect_port(atom.id, port))
	form.end_group()


# ── 条件列表 ──

## 可复用的条件列表：每行“条件(参数) 比较 值/条件”，下面一行显示这行的问题。
static func conditions(form: GDForm, rows: Array, ctx: Context) -> void:
	var registry := ctx.conditions
	for index in range(rows.size()):
		var row: GDGuideData.GuideConditionExpr = rows[index]
		var sub := form.nested()
		_call_fields(sub, "条件", row.left, registry, row)
		var left_type := _result_type(registry, row.left.condition_id)
		sub.choice("比较", OPS if left_type in [GDGuideData.GuideValueType.INT, GDGuideData.GuideValueType.FLOAT] else OPS.slice(0, 2),
			func() -> int: return row.op, func(v: int) -> void: row.op = v)
		sub.choice("右侧", [["值", GDGuideData.GuideOperandKind.VALUE], ["条件", GDGuideData.GuideOperandKind.CONDITION]],
			func() -> int: return row.right.kind, func(v: int) -> void: row.right.kind = v)
		if row.right.kind == GDGuideData.GuideOperandKind.CONDITION:
			_call_fields(sub, "右侧条件", row.right.condition, registry, null)
		else:
			_value_field(sub, "值", row.right.value, left_type)
		sub.live_note(func() -> String: return registry.validate_expr(row) if registry != null else "", &"danger")
		var remove := sub.button("删除这行", func() -> void:
			rows.remove_at(rows.find(row))
			ctx.commit.call("删除条件")
		, &"danger")
		remove.size_flags_horizontal = Control.SIZE_SHRINK_END
		form.custom(HSeparator.new())
	form.button("添加条件", func() -> void:
		rows.append(_default_row(registry))
		ctx.commit.call("添加条件")
	)


static func _call_fields(form: GDForm, label: String, invocation: GDGuideData.GuideConditionCall, registry: GDGuideServices.GuideConditionRegistry, owner: GDGuideData.GuideConditionExpr) -> void:
	var ids := _condition_ids(registry)
	var items: Array = []
	for i in range(ids.size()):
		items.append([_condition_name(registry, ids[i]), i])
	if not ids.has(invocation.condition_id):
		items.append(["未登记：%s" % invocation.condition_id, ids.size()])
	form.choice(label, items,
		func() -> int: return ids.find(invocation.condition_id) if ids.has(invocation.condition_id) else ids.size(),
		func(v: int) -> void:
			if v >= ids.size():
				return
			invocation.condition_id = ids[v]
			_fit_types(registry, invocation, owner))
	var signature := registry.try_get_signature(invocation.condition_id) if registry != null else {}
	if bool(signature.get("has_arg", false)):
		_value_field(form, "参数", invocation.arg, int(signature["arg_type"]))


## 换了条件以后，让参数和右侧值的类型跟着变，免得出现“类型不符”。
static func _fit_types(registry: GDGuideServices.GuideConditionRegistry, invocation: GDGuideData.GuideConditionCall, owner: GDGuideData.GuideConditionExpr) -> void:
	var signature := registry.try_get_signature(invocation.condition_id)
	if bool(signature.get("has_arg", false)) and (invocation.arg == null or invocation.arg.type != int(signature["arg_type"])):
		invocation.arg = GDGuideData.GuideValue.new()
		invocation.arg.type = int(signature["arg_type"])
	if owner != null and owner.right.kind == GDGuideData.GuideOperandKind.VALUE and owner.right.value.type != int(signature.get("result_type", 0)):
		owner.right.value = GDGuideData.GuideValue.new()
		owner.right.value.type = int(signature.get("result_type", 0))
		if owner.right.value.type == GDGuideData.GuideValueType.BOOL:
			owner.right.value.bool_value = true
		if owner.right.value.type not in [GDGuideData.GuideValueType.INT, GDGuideData.GuideValueType.FLOAT]:
			owner.op = mini(owner.op, GDGuideData.GuideCompareOp.NOT_EQUAL)


static func _value_field(form: GDForm, label: String, value: GDGuideData.GuideValue, type: int) -> void:
	match type:
		GDGuideData.GuideValueType.BOOL:
			form.toggle(label, func() -> bool: return value.bool_value, func(v: bool) -> void:
				value.type = type
				value.bool_value = v)
		GDGuideData.GuideValueType.INT:
			form.integer(label, func() -> int: return value.int_value, func(v: int) -> void:
				value.type = type
				value.int_value = v)
		GDGuideData.GuideValueType.FLOAT:
			form.number(label, func() -> float: return value.float_value, func(v: float) -> void:
				value.type = type
				value.float_value = v)
		_:
			form.text(label, func() -> String: return value.string_value, func(v: String) -> void:
				value.type = type
				value.string_value = v)


static func _default_row(registry: GDGuideServices.GuideConditionRegistry) -> GDGuideData.GuideConditionExpr:
	var ids := _condition_ids(registry)
	var condition_id: String = "io.guide.is_new_player" if ids.has("io.guide.is_new_player") or ids.is_empty() else ids[0]
	var row := GDGuideData.GuideConditionExpr.create_compare(condition_id, GDGuideData.GuideValue.new(), GDGuideData.GuideCompareOp.EQUAL, GDGuideData.GuideValue.from_bool(true))
	if registry != null:
		_fit_types(registry, row.left, row)
	return row


static func _condition_ids(registry: GDGuideServices.GuideConditionRegistry) -> Array:
	var ids: Array = registry.get_all_ids() if registry != null else []
	ids.sort()
	return ids


static func _condition_name(registry: GDGuideServices.GuideConditionRegistry, condition_id: String) -> String:
	var display := str(registry.get_entry_info(condition_id).get("display", condition_id))
	return display.replace("{0}", "")


static func _result_type(registry: GDGuideServices.GuideConditionRegistry, condition_id: String) -> int:
	return int(registry.try_get_signature(condition_id).get("result_type", GDGuideData.GuideValueType.BOOL)) if registry != null else GDGuideData.GuideValueType.BOOL


## 只读时（试跑中、图里有缺失节点）把表单里的控件全部锁住。
static func finish(form: GDForm, ctx: Context) -> void:
	form.end_group()
	if ctx.read_only:
		_lock(form)


static func _lock(node: Node) -> void:
	for child in node.get_children():
		if child is LineEdit or child is TextEdit or child is SpinBox:
			child.editable = false
		elif child is BaseButton:
			child.disabled = true
		_lock(child)
