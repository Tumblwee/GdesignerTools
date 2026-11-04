@tool
class_name GDEntityAtomSystem
extends RefCounted

## Entity / Atom 四层模型中的实例与原子实现（对应 Entity / AtomBase / AtomTemplateSO / InteractableAtom / VisualAtom / UIAnchor3DAtom / PreviewMarker / AtomVarTagRegistry / EntityCatalogSO）

## EntityCatalogSO 对应：收集同目录及子目录下的 Entity 预制体 address 清单
class EntityCatalogRes extends Resource:
	@export var entity_addresses: PackedStringArray = PackedStringArray()

	var count: int:
		get:
			return entity_addresses.size()

	func get_address(index: int) -> String:
		if index < 0 or index >= entity_addresses.size():
			return ""
		return entity_addresses[index]

	func replace_addresses(addresses: PackedStringArray) -> void:
		entity_addresses = addresses
		emit_changed()

	func collect_from_directory(root_dir: String = "") -> int:
		var dir_to_scan := root_dir
		if dir_to_scan.is_empty() and not resource_path.is_empty():
			dir_to_scan = resource_path.get_base_dir()
		if dir_to_scan.is_empty():
			return 0
		var collected: PackedStringArray = PackedStringArray()
		_scan_entity_scenes_recursive(dir_to_scan, collected)
		entity_addresses = collected
		emit_changed()
		return collected.size()

	static func _scan_entity_scenes_recursive(dir_path: String, out_list: PackedStringArray) -> void:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			return
		dir.list_dir_begin()
		var fname := dir.get_next()
		while not fname.is_empty():
			if fname != "." and fname != ".." and not fname.begins_with("."):
				var full := dir_path.path_join(fname)
				if dir.current_is_dir():
					_scan_entity_scenes_recursive(full, out_list)
				elif fname.ends_with(".tscn"):
					var stem := fname.get_basename()
					if not out_list.has(stem):
						out_list.append(stem)
			fname = dir.get_next()
		dir.list_dir_end()


## AtomTemplateSO 对应：每原子脚本类型一份模板（显示名 / 介绍 / Icon / AtomType / 脚本路径与类名）
class AtomTemplateRes extends Resource:
	@export var atom_type: int = GDCoreTypes.AtomType.LOGIC
	@export var display_name: String = ""
	@export_multiline var description: String = ""
	@export var icon: Texture2D = null
	@export var atom_script: Script = null
	@export var atom_script_type_name: String = ""

	func write_metadata(
		p_display_name: String,
		p_description: String,
		p_atom_type: int,
		p_icon: Texture2D,
		p_script: Script,
		p_type_name: String
	) -> void:
		display_name = p_display_name
		description = p_description
		atom_type = p_atom_type
		icon = p_icon
		atom_script = p_script
		if not p_type_name.is_empty():
			atom_script_type_name = p_type_name
		emit_changed()


## AtomBase 对应：挂在 Entity 根节点或原子子节点上的逻辑驱动器基类
class AtomBase extends Node:
	## 子类可重写此方法返回映射标签字典：tag -> {"property": prop_name, "value_type": KeywordValueType}
	func get_atom_var_tags() -> Dictionary:
		if has_meta("atom_var_tags"):
			var meta_tags = get_meta("atom_var_tags")
			if meta_tags is Dictionary:
				return meta_tags
		return {}


## PreviewMarker 对应：编辑器临时预览实例标记，运行时进场若扫到残留则报错并销毁
class PreviewMarker extends Node:
	func _ready() -> void:
		if not Engine.is_editor_hint():
			GDGameLogger.log_error_d("[PreviewMarker] 检测到未清理的编辑器预览实例 '%s'，已自动销毁。" % name)
			if get_parent() != null:
				get_parent().queue_free()
			else:
				queue_free()


## InteractableAtom 对应：点击 / 长按手势状态机 + 碰撞盒自动拟合 AABB
class InteractableAtom extends AtomBase:
	enum ColliderFitSource {
		SELF_RENDERERS = 0,
		CHILDREN_RENDERERS = 1,
	}

	signal on_clicked()
	signal on_long_pressed()

	@export var enable_click: bool = true
	@export var enable_long_press: bool = false
	@export var long_press_seconds: float = 0.6
	@export var tap_max_travel_px: float = 25.0
	@export var filter_ui_hit: bool = true
	@export var fit_source: int = ColliderFitSource.CHILDREN_RENDERERS
	@export var collider_padding: Vector3 = Vector3.ZERO
	@export var box_center: Vector3 = Vector3.ZERO
	@export var box_size: Vector3 = Vector3.ONE

	var _pressed: bool = false
	var _latched_as_drag: bool = false
	var _long_press_fired: bool = false
	var _press_screen_pos: Vector2 = Vector2.ZERO
	var _max_travel_sqr: float = 0.0
	var _press_start_time_sec: float = 0.0

	func editor_set_interactable_data(
		p_enable_click: bool,
		p_enable_long_press: bool,
		p_long_press_seconds: float,
		p_tap_max_travel_px: float,
		p_filter_ui_hit: bool,
		p_fit_source: int,
		p_collider_padding: Vector3
	) -> void:
		enable_click = p_enable_click
		enable_long_press = p_enable_long_press
		long_press_seconds = maxf(0.1, p_long_press_seconds)
		tap_max_travel_px = maxf(1.0, p_tap_max_travel_px)
		filter_ui_hit = p_filter_ui_hit
		fit_source = p_fit_source
		collider_padding = p_collider_padding

	func simulate_pointer_down(screen_pos: Vector2, now_sec: float, over_ui: bool = false) -> void:
		reset_gesture()
		if not enable_click and not enable_long_press:
			return
		if filter_ui_hit and over_ui:
			return
		_pressed = true
		_latched_as_drag = false
		_long_press_fired = false
		_press_screen_pos = screen_pos
		_max_travel_sqr = 0.0
		_press_start_time_sec = now_sec

	func simulate_pointer_hold(screen_pos: Vector2, now_sec: float) -> void:
		if not _pressed:
			return
		var travel_sqr := (screen_pos - _press_screen_pos).length_squared()
		if travel_sqr > _max_travel_sqr:
			_max_travel_sqr = travel_sqr
		var thr := maxf(1.0, tap_max_travel_px)
		if _max_travel_sqr >= thr * thr:
			_latched_as_drag = true
		if enable_long_press and not _long_press_fired and not _latched_as_drag:
			if now_sec - _press_start_time_sec >= maxf(0.1, long_press_seconds):
				_long_press_fired = true
				on_long_pressed.emit()

	func simulate_pointer_up(screen_pos: Vector2, still_hitting_self: bool = true, over_ui: bool = false) -> void:
		if _pressed and not _latched_as_drag and not _long_press_fired and enable_click:
			if not (filter_ui_hit and over_ui) and still_hitting_self:
				on_clicked.emit()
		reset_gesture()

	func reset_gesture() -> void:
		_pressed = false
		_latched_as_drag = false
		_long_press_fired = false
		_max_travel_sqr = 0.0

	func fit_collider(host_root: Node = null) -> bool:
		var root_node: Node = host_root if host_root != null else get_parent()
		if root_node == null:
			root_node = self
		var aabbs: Array[AABB] = []
		_collect_visual_aabbs(root_node, fit_source == ColliderFitSource.CHILDREN_RENDERERS, aabbs)
		if aabbs.is_empty():
			return false
		var merged: AABB = aabbs[0]
		for i in range(1, aabbs.size()):
			merged = merged.merge(aabbs[i])
		box_center = merged.get_center()
		box_size = merged.size + collider_padding
		return true

	static func _collect_visual_aabbs(node: Node, recursive: bool, out_aabbs: Array[AABB]) -> void:
		if node is VisualInstance3D:
			var vi := node as VisualInstance3D
			if vi.visible:
				out_aabbs.append(vi.get_aabb())
		if not recursive:
			return
		for child in node.get_children():
			_collect_visual_aabbs(child, true, out_aabbs)


## VisualAtom 对应：拥有 VisualRoot 子节点，按 index 在多套外观间切换显示（Populate / ShowIndex / HideAll / ClearPopulated）
class VisualAtom extends AtomBase:
	const VISUAL_ROOT_NAME := "VisualRoot"

	@export var visual_root_path: NodePath = NodePath("VisualRoot")
	@export var prefab_ref: PackedScene = null

	var _entries: Array[Dictionary] = [] # {"index": int, "root": Node}
	var _current_index: int = -1

	var current_index: int:
		get:
			return _current_index

	var is_populated: bool:
		get:
			return not _entries.is_empty()

	func ensure_visual_root() -> Node:
		var host := get_parent() if get_parent() != null else self
		var existing := host.get_node_or_null(VISUAL_ROOT_NAME)
		if existing != null:
			return existing
		var root := Node3D.new()
		root.name = VISUAL_ROOT_NAME
		host.add_child(root)
		return root

	func populate(prefabs: Array, start_index: int = 0) -> void:
		var parent := ensure_visual_root()
		if parent == null:
			return
		for i in range(prefabs.size()):
			var idx := start_index + i
			var ps: PackedScene = prefabs[i] as PackedScene
			if ps == null:
				continue
			if get_root(idx) != null:
				continue
			var inst := ps.instantiate()
			inst.name = "Idx%d_%s" % [idx, ps.resource_path.get_file().get_basename()]
			if inst is Node3D:
				(inst as Node3D).visible = false
			elif inst is CanvasItem:
				(inst as CanvasItem).visible = false
			parent.add_child(inst)
			_entries.append({"index": idx, "root": inst})

	func clear_populated() -> void:
		for entry in _entries:
			var r: Node = entry.get("root", null)
			if r != null and is_instance_valid(r):
				r.free()
		_entries.clear()
		_current_index = -1
		var host := get_parent() if get_parent() != null else self
		var vroot := host.get_node_or_null(VISUAL_ROOT_NAME)
		if vroot != null:
			for i in range(vroot.get_child_count() - 1, -1, -1):
				var ch := vroot.get_child(i)
				if is_populate_or_preview_child_name(ch.name):
					ch.free()

	static func is_populate_or_preview_child_name(node_name: String) -> bool:
		if node_name.is_empty():
			return false
		if node_name.begins_with("[Preview]"):
			return true
		if not node_name.begins_with("Idx") or node_name.length() < 5:
			return false
		var underscore := node_name.find("_", 3)
		if underscore <= 3:
			return false
		var digits := node_name.substr(3, underscore - 3)
		return digits.is_valid_int()

	func show_index(index: int) -> void:
		for entry in _entries:
			var r: Node = entry.get("root", null)
			if r == null or not is_instance_valid(r):
				continue
			var matched: bool = int(entry.get("index", -1)) == index
			if r is Node3D:
				(r as Node3D).visible = matched
			elif r is CanvasItem:
				(r as CanvasItem).visible = matched
		_current_index = index

	func hide_all() -> void:
		for entry in _entries:
			var r: Node = entry.get("root", null)
			if r == null or not is_instance_valid(r):
				continue
			if r is Node3D:
				(r as Node3D).visible = false
			elif r is CanvasItem:
				(r as CanvasItem).visible = false
		_current_index = -1

	func get_root(index: int) -> Node:
		for entry in _entries:
			if int(entry.get("index", -1)) == index:
				return entry.get("root", null)
		return null


## UIAnchor3DAtom 对应：3DUIRoot 挂点字典查询（Get / Has / CollectAnchors）
class UIAnchor3DAtom extends AtomBase:
	const ANCHOR_ROOT_NAME := "3DUIRoot"

	@export var anchors: Dictionary = {} # key (String) -> NodePath

	func ensure_anchor_root() -> Node3D:
		var host := get_parent() if get_parent() != null else self
		var existing := host.get_node_or_null(ANCHOR_ROOT_NAME)
		if existing is Node3D:
			return existing
		var root := Node3D.new()
		root.name = ANCHOR_ROOT_NAME
		host.add_child(root)
		return root

	func collect_anchors_from_root() -> int:
		anchors.clear()
		var root := ensure_anchor_root()
		for child in root.get_children():
			anchors[child.name] = get_path_to(child)
		return anchors.size()

	func register_anchor(key: String, target: Node) -> void:
		if key.is_empty() or target == null:
			return
		anchors[key] = target.get_path() if target.is_inside_tree() else NodePath(target.name)

	func has_anchor(key: String) -> bool:
		return not key.is_empty() and anchors.has(key)

	func get_anchor(key: String) -> Node:
		if not has_anchor(key):
			return null
		var np: NodePath = anchors[key]
		return get_node_or_null(np)


## Entity 对应：制成品根节点宿主，管理 AtomBase 组件列表
class EntityNode extends Node3D:
	var _atoms: Array[AtomBase] = []

	var atoms: Array[AtomBase]:
		get:
			editor_prune_null_atoms()
			return _atoms

	func find_atom_by_class(atom_class_name: String) -> AtomBase:
		editor_prune_null_atoms()
		for a in _atoms:
			if a != null and (a.get_class() == atom_class_name or a.name == atom_class_name):
				return a
		return null

	func editor_register_atom(atom: AtomBase) -> void:
		if atom == null:
			return
		if not _atoms.has(atom):
			_atoms.append(atom)
		if atom.get_parent() == null:
			add_child(atom)
		if atom is VisualAtom:
			(atom as VisualAtom).ensure_visual_root()
		elif atom is UIAnchor3DAtom:
			(atom as UIAnchor3DAtom).ensure_anchor_root()

	func editor_remove_atom(atom: AtomBase) -> bool:
		if atom == null or not _atoms.has(atom):
			return false
		_atoms.erase(atom)
		if atom.get_parent() == self:
			remove_child(atom)
			atom.free()
		return true

	func editor_prune_null_atoms() -> void:
		for i in range(_atoms.size() - 1, -1, -1):
			if _atoms[i] == null or not is_instance_valid(_atoms[i]):
				_atoms.remove_at(i)


## AtomVarTagRegistry 对应：扫描 AtomBase 上的映射标签并反射写入成员
class AtomVarTagRegistry extends RefCounted:
	class Binding extends RefCounted:
		var tag: String = ""
		var atom_type_name: String = ""
		var member_name: String = ""
		var kind: int = GDCoreTypes.KeywordValueType.INT

		func _init(p_tag: String, p_atom_type: String, p_member: String, p_kind: int) -> void:
			tag = p_tag
			atom_type_name = p_atom_type
			member_name = p_member
			kind = p_kind

		var display_label: String:
			get:
				return "%s.%s : %s (%s)" % [
					atom_type_name,
					member_name,
					GDCoreTypes.keyword_value_type_name(kind),
					tag
				]

	static func collect_from_node(root: Node) -> Array[Binding]:
		var list: Array[Binding] = []
		if root == null:
			return list
		var seen: Dictionary = {}
		_collect_recursive(root, seen, list)
		return list

	static func _collect_recursive(node: Node, seen: Dictionary, out_list: Array[Binding]) -> void:
		if node is AtomBase:
			var atom := node as AtomBase
			var tags_dict := atom.get_atom_var_tags()
			for tag_key in tags_dict.keys():
				var info: Dictionary = tags_dict[tag_key]
				var prop_name := str(info.get("property", tag_key))
				var vt := int(info.get("value_type", GDCoreTypes.KeywordValueType.INT))
				var atom_name := str(info.get("atom_type", atom.name))
				var dedup_key := "%s::%s" % [atom_name, tag_key]
				if not seen.has(dedup_key):
					seen[dedup_key] = true
					out_list.append(Binding.new(str(tag_key), atom_name, prop_name, vt))
		for child in node.get_children():
			_collect_recursive(child, seen, out_list)

	static func try_set(atom: AtomBase, tag: String, value: Variant) -> Dictionary:
		if atom == null:
			return {"ok": false, "error": "atom 为空"}
		if tag.strip_edges().is_empty():
			return {"ok": false, "error": "标签为空"}
		var tags_dict := atom.get_atom_var_tags()
		if not tags_dict.has(tag):
			return {"ok": false, "error": ""} # 本原子无此标签，调用方继续试下一个原子
		var info: Dictionary = tags_dict[tag]
		var prop_name := str(info.get("property", tag))
		var vt := int(info.get("value_type", GDCoreTypes.KeywordValueType.INT))
		var converted := _try_convert(value, vt)
		if not bool(converted.get("ok", false)):
			return {"ok": false, "error": str(converted.get("error", "类型转换失败"))}
		atom.set(prop_name, converted.get("value"))
		atom.set_meta("var_tag_val_" + tag.replace(".", "_"), converted.get("value"))
		return {"ok": true, "error": ""}

	static func apply_overrides_to_node(root: Node, overrides: Array) -> int:
		if root == null:
			return 0
		var applied := 0
		var atoms: Array[AtomBase] = []
		_gather_atoms(root, atoms)
		for ov in overrides:
			var tag_str := ""
			var val: Variant = null
			if ov is Object and ov.has_method("get_boxed"):
				tag_str = str(ov.get("tag"))
				val = ov.call("get_boxed")
			elif ov is Dictionary:
				tag_str = str(ov.get("tag", ""))
				val = ov.get("value", null)
			if tag_str.is_empty():
				continue
			for atom in atoms:
				var res := try_set(atom, tag_str, val)
				if bool(res.get("ok", false)):
					applied += 1
		return applied

	static func _gather_atoms(node: Node, out_atoms: Array[AtomBase]) -> void:
		if node is AtomBase:
			out_atoms.append(node)
		for ch in node.get_children():
			_gather_atoms(ch, out_atoms)

	static func _try_convert(val: Variant, vt: int) -> Dictionary:
		match vt:
			GDCoreTypes.KeywordValueType.STRING:
				return {"ok": true, "value": str(val) if val != null else ""}
			GDCoreTypes.KeywordValueType.INT:
				if val is int:
					return {"ok": true, "value": val}
				return {"ok": false, "error": "类型不匹配：期望 Int"}
			GDCoreTypes.KeywordValueType.FLOAT:
				if val is float or val is int:
					return {"ok": true, "value": float(val)}
				return {"ok": false, "error": "类型不匹配：期望 Float"}
			GDCoreTypes.KeywordValueType.BOOL:
				if val is bool:
					return {"ok": true, "value": val}
				return {"ok": false, "error": "类型不匹配：期望 Bool"}
			_:
				return {"ok": false, "error": "不支持的类型"}


## 5. 场景家具生成点集合与等级外观切换行为（对应 FurnitureSlotGroupBehavior & LevelVisualSwitcherBehavior）
class FurnitureLevelEntry extends Resource:
	@export var level: int = 1
	@export var prefab: PackedScene = null

	func _init(p_level: int = 1, p_prefab: PackedScene = null) -> void:
		level = p_level
		prefab = p_prefab


class FurnitureSlot extends Resource:
	@export var slot_name: String = ""
	@export var spawn_point_path: NodePath = NodePath()
	@export var per_level: Array[FurnitureLevelEntry] = []


class FurnitureSlotGroupBehavior extends Node3D:
	@export var slots: Array[FurnitureSlot] = []
	@export var preview_level: int = 1

	var _runtime_spawned: Array[Node] = []

	var spawned_count: int:
		get:
			return _runtime_spawned.size()

	func _ready() -> void:
		if not Engine.is_editor_hint():
			auto_clean_editor_previews()

	func spawn_level(level: int) -> void:
		clear_spawned()
		for slot in slots:
			if slot == null:
				continue
			var sp := get_node_or_null(slot.spawn_point_path) if not slot.spawn_point_path.is_empty() else self
			if sp == null:
				continue
			var ps := _resolve_prefab(slot.per_level, level)
			if ps == null:
				continue
			var inst := ps.instantiate()
			sp.add_child(inst)
			_runtime_spawned.append(inst)

	func clear_spawned() -> void:
		for n in _runtime_spawned:
			if n != null and is_instance_valid(n):
				if n.get_parent() != null:
					n.get_parent().remove_child(n)
				n.free()
		_runtime_spawned.clear()

	func editor_preview_level() -> void:
		editor_clear_preview()
		for slot in slots:
			if slot == null:
				continue
			var sp := get_node_or_null(slot.spawn_point_path) if not slot.spawn_point_path.is_empty() else self
			if sp == null:
				continue
			var ps := _resolve_prefab(slot.per_level, preview_level)
			if ps == null:
				continue
			var inst := ps.instantiate()
			inst.name = "[Preview] %s" % inst.name
			var marker := PreviewMarker.new()
			marker.configure("FurnitureSlotGroupBehavior", preview_level)
			inst.add_child(marker)
			sp.add_child(inst)

	func editor_clear_preview() -> void:
		var to_kill: Array[Node] = []
		_find_preview_Marked(self, to_kill)
		for n in to_kill:
			if n != null and is_instance_valid(n):
				if n.get_parent() != null:
					n.get_parent().remove_child(n)
				n.free()

	func auto_clean_editor_previews() -> void:
		var to_kill: Array[Node] = []
		_find_preview_Marked(self, to_kill)
		if not to_kill.is_empty():
			GDGameLogger.log_error_p("[FurnitureSlotGroup] '%s' 检测到 %d 个未清理的编辑器预览实例，已自动销毁。" % [name, to_kill.size()])
			editor_clear_preview()

	static func _find_preview_Marked(node: Node, out_nodes: Array[Node]) -> void:
		for ch in node.get_children():
			if ch is PreviewMarker:
				out_nodes.append(node)
				return
			_find_preview_Marked(ch, out_nodes)

	static func _resolve_prefab(entries: Array[FurnitureLevelEntry], level: int) -> PackedScene:
		for e in entries:
			if e != null and e.level == level and e.prefab != null:
				return e.prefab
		return null


class LevelVisualSwitcherBehavior extends VisualAtom:
	pass
