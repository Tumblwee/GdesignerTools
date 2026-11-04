@tool
class_name GDGuideGraphRes
extends Resource

## 新手引导图资产（对应 GuideGraphSO）。
## trigger / atoms / edges 由 GDGuideAtoms / GDGuideData 的内部类组成，Godot 无法直接落盘内部类，统一经 codec_data 存取。
## 加载时遇到未知原子类型，会还原成 MissingAtom，并在再次保存时原样写回原始数据。

const CURRENT_SCHEMA_VERSION := 2

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var graph_id: int = 0
@export var raw_display_name: String = ""
@export var enabled: bool = true
@export var priority: int = 0
@export var allow_skip: bool = false
@export var resume_from_entry: bool = false
@export var next_node_id: int = 1

var trigger: GDGuideData.GuideTrigger = GDGuideData.GuideTrigger.new()
var atoms: Array = [] # Array[GDGuideAtoms.GuideAtom]
var edges: Array = [] # Array[GDGuideData.GuideEdge]

## 唯一的落盘入口：trigger / atoms / edges 的编码形式。保存、加载、duplicate 均自动经过这里。
@export_storage var codec_data: Dictionary:
	get:
		return {"trigger": codec().encode(trigger), "atoms": atoms.map(_encode_atom), "edges": codec().encode(edges)}
	set(value):
		var data: Dictionary = codec().decode(value)
		trigger = data.get("trigger") if data.get("trigger") is GDGuideData.GuideTrigger else GDGuideData.GuideTrigger.new()
		atoms = data.get("atoms", []).filter(func(a: Variant) -> bool: return a is GDGuideAtoms.GuideAtom)
		edges = data.get("edges", []).filter(func(e: Variant) -> bool: return e is GDGuideData.GuideEdge)
		for atom in atoms:
			if atom is GDGuideAtoms.MissingAtom:
				atom.set_out_ports(edges.filter(func(e: GDGuideData.GuideEdge) -> bool: return e.from_id == atom.id).map(func(e: GDGuideData.GuideEdge) -> int: return e.port))

static var _codec: GDDataCodec = null

var display_name: String:
	get:
		if not raw_display_name.is_empty():
			return raw_display_name
		return resource_name if not resource_name.is_empty() else "Guide_%d" % graph_id

var missing_atom_count: int:
	get:
		return atoms.filter(func(a: Variant) -> bool: return a == null or a is GDGuideAtoms.MissingAtom).size()

## 引导图数据（GDGuideAtoms 全部原子 + GDGuideData 数据类型）的编解码器；未知原子类型还原为 MissingAtom。
static func codec() -> GDDataCodec:
	if _codec == null:
		_codec = GDDataCodec.new([GDGuideAtoms, GDGuideData])
		_codec.on_unknown = _decode_missing_atom
	return _codec

static func _decode_missing_atom(type_name: String, data: Dictionary) -> GDGuideAtoms.MissingAtom:
	var atom := GDGuideAtoms.MissingAtom.create_placeholder(
		int(data.get("id", 0)), data.get("editor_position", Vector2.ZERO), str(data.get("display_name", "")), type_name, 0, []
	)
	atom.raw_data = data
	return atom

static func _encode_atom(atom: Variant) -> Variant:
	if atom is GDGuideAtoms.MissingAtom and not atom.raw_data.is_empty():
		var raw: Dictionary = atom.raw_data.duplicate()
		raw.merge({"id": atom.id, "editor_position": atom.editor_position, "display_name": atom.display_name}, true)
		return raw
	return codec().encode(atom)

func get_graph_display_name() -> String:
	return display_name

func find_atom(node_id: int) -> GDGuideAtoms.GuideAtom:
	if node_id <= 0:
		return null
	for a in atoms:
		if a != null and a.id == node_id:
			return a
	return null

func try_get_edge(from_id: int, port: int) -> Dictionary:
	for e in edges:
		if e != null and e.from_id == from_id and e.port == port:
			return {"ok": true, "edge": e}
	return {"ok": false, "edge": null}

func find_entry_id() -> int:
	for a in atoms:
		if a is GDGuideAtoms.EntryAtom:
			return a.id
	return 0

func is_reachable_from_entry(node_id: int) -> bool:
	var entry_id := find_entry_id()
	if entry_id <= 0 or node_id <= 0:
		return false
	if node_id == entry_id:
		return true
	var visited: Dictionary = {entry_id: true}
	var queue: Array[int] = [entry_id]
	while not queue.is_empty():
		var cur := queue.pop_front()
		for e in edges:
			if e == null or e.from_id != cur or visited.has(e.to_id):
				continue
			visited[e.to_id] = true
			if e.to_id == node_id:
				return true
			queue.append(e.to_id)
	return false

# ── Authoring ──

func set_graph_id(p_id: int) -> void:
	graph_id = p_id
	emit_changed()

func set_display_name(p_name: String) -> void:
	raw_display_name = p_name
	emit_changed()

func set_enabled(p_enabled: bool) -> void:
	enabled = p_enabled
	emit_changed()

func set_priority(p_priority: int) -> void:
	priority = p_priority
	emit_changed()

func set_allow_skip(p_allow_skip: bool) -> void:
	allow_skip = p_allow_skip
	emit_changed()

func set_resume_from_entry(p_resume: bool) -> void:
	resume_from_entry = p_resume
	emit_changed()

func set_schema_version(p_ver: int) -> void:
	schema_version = p_ver
	emit_changed()

func set_trigger(p_trigger: GDGuideData.GuideTrigger) -> void:
	trigger = p_trigger if p_trigger != null else GDGuideData.GuideTrigger.new()
	emit_changed()

func add_atom(atom: GDGuideAtoms.GuideAtom, pos: Vector2 = Vector2.ZERO) -> GDGuideAtoms.GuideAtom:
	if atom == null or atoms.has(atom):
		return atom
	var id := maxi(next_node_id, _max_atom_id() + 1)
	next_node_id = id + 1
	atom.assign_id(id)
	atom.assign_editor_position(pos)
	atoms.append(atom)
	emit_changed()
	return atom

func import_atom(atom: GDGuideAtoms.GuideAtom, node_id: int, pos: Vector2) -> void:
	if atom == null or node_id <= 0 or find_atom(node_id) != null or atoms.has(atom):
		return
	atom.assign_id(node_id)
	atom.assign_editor_position(pos)
	atoms.append(atom)
	next_node_id = maxi(next_node_id, node_id + 1)
	emit_changed()

func remove_atom(node_id: int) -> bool:
	var atom := find_atom(node_id)
	if atom == null:
		return false
	atoms.erase(atom)
	_remove_edges_touching(node_id)
	emit_changed()
	return true

func set_atom_position(node_id: int, pos: Vector2) -> bool:
	var a := find_atom(node_id)
	if a == null:
		return false
	a.assign_editor_position(pos)
	emit_changed()
	return true

func can_connect(from_id: int, port: int, to_id: int) -> Dictionary:
	if from_id == to_id:
		return {"ok": false, "reason": "不能连到自己"}
	var from_a := find_atom(from_id)
	var to_a := find_atom(to_id)
	if from_a == null or to_a == null:
		return {"ok": false, "reason": "节点不存在"}
	if not GDGuideData.GuidePorts.is_output(port) or not from_a.has_port(port):
		return {"ok": false, "reason": "「%s」没有「%s」口" % [from_a.title, GDGuideData.GuidePorts.label(port)]}
	if not to_a.has_port(GDGuideData.GuidePortKind.EXEC_IN):
		return {"ok": false, "reason": "「%s」不能被连入" % to_a.title}
	return {"ok": true, "reason": ""}

func connect_nodes(from_id: int, port: int, to_id: int) -> Dictionary:
	var check := can_connect(from_id, port, to_id)
	if not bool(check.get("ok", false)):
		return {"ok": false, "replaced": false, "reason": str(check.get("reason", ""))}
	var replaced := false
	for i in range(edges.size() - 1, -1, -1):
		var e = edges[i]
		if e != null and e.from_id == from_id and e.port == port:
			if e.to_id == to_id:
				return {"ok": true, "replaced": false, "reason": ""}
			edges.remove_at(i)
			replaced = true
	edges.append(GDGuideData.GuideEdge.new(from_id, port, to_id))
	edges.sort_custom(GDGuideData.GuideEdge.compare)
	emit_changed()
	return {"ok": true, "replaced": replaced, "reason": ""}

func disconnect_port(from_id: int, port: int) -> bool:
	var before := edges.size()
	edges.assign(edges.filter(func(e: Variant) -> bool: return e == null or e.from_id != from_id or e.port != port))
	if edges.size() == before:
		return false
	emit_changed()
	return true

func add_default_skeleton() -> bool:
	if not atoms.is_empty():
		return false
	var entry := GDGuideAtoms.EntryAtom.new()
	add_atom(entry, Vector2(0.0, 0.0))
	var exit_a := GDGuideAtoms.ExitAtom.new()
	exit_a.set_display_name("完成")
	add_atom(exit_a, Vector2(320.0, 0.0))
	connect_nodes(entry.id, GDGuideData.GuidePortKind.EXEC_OUT, exit_a.id)
	return true

func remove_dangling_edges() -> int:
	var before := edges.size()
	edges.assign(edges.filter(func(e: Variant) -> bool: return e != null and find_atom(e.from_id) != null and find_atom(e.to_id) != null))
	return before - edges.size()

func remove_missing_atom_slots() -> int:
	var removed := 0
	for i in range(atoms.size() - 1, -1, -1):
		var a = atoms[i]
		if a == null or a is GDGuideAtoms.MissingAtom:
			if a != null:
				_remove_edges_touching(a.id)
			atoms.remove_at(i)
			removed += 1
	if removed > 0:
		emit_changed()
	return removed

func clear_for_rebuild() -> void:
	atoms.clear()
	edges.clear()
	next_node_id = 1
	emit_changed()

func _remove_edges_touching(node_id: int) -> void:
	edges.assign(edges.filter(func(e: Variant) -> bool: return e == null or (e.from_id != node_id and e.to_id != node_id)))

func _max_atom_id() -> int:
	var mx := 0
	for a in atoms:
		if a != null and a.id > mx:
			mx = a.id
	return mx
