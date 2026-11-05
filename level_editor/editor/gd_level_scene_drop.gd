@tool
class_name GDLevelSceneDrop
extends RefCounted

## 把关卡原型拖进 Godot 正在编辑的场景。
##
## Control 拖拽只在进程内有效，而 3D/2D 主视口只接受 files / nodes / resource，不认识原型。
## 因此分两步：
##   1. 原型列表用 begin() 生成拖拽数据（关卡页里的平面图和属性栏可以直接接住）。
##   2. EditorPlugin.set_force_draw_over_forwarding_enabled() 在视口上放一个只在拖拽期间拦截的 Control，
##      同时用 DisplayServer 鼠标位置做射线吸附。不实现 _handles()，避免抢走当前选中节点的 Inspector。
## 落下的节点写进当前场景的 Placements 容器（owner = 场景根，会随场景保存），并写入关卡资源。
## 运行时 load_session 若发现同 instance_id 的节点就直接采纳，不会再生成一份。

const DRAG_TYPE := "gdesigner_archetype"
const GHOST_NAME := "[Archetype Drag Ghost]"
const GROUND_NAME := "[SceneEditor Ground]"
const PLACEMENTS_ROOT := "Placements"
const META_ID := GDSceneEditorRuntime.PLACEMENT_ID_META
const META_LAYOUT := GDSceneEditorRuntime.PLACEMENT_LAYOUT_META
const RAY_LENGTH := 4000.0

## 当前进行中的拖拽；没有拖拽时为 null。
static var session: DragSession = null
static var _spawned: Dictionary = {} # layout identity + instance_id -> Node
static var _explicit_parents: Dictionary = {} # resource instance ID -> WeakRef, explicit headless hosts
static var _layout_owners: Dictionary = {} # layout identity -> WeakRef
static var _plugin: EditorPlugin = null
static var _host: Node = null
static var _status_cb: Callable = Callable()
static var _binding_cb: Callable = Callable()
static var _last_status: String = ""


## 一次原型拖拽的状态：拖的是谁、落点吸附结果、是否已提交，以及视口里的预览幽灵节点。
class DragSession extends RefCounted:
	var archetype: GDArchetypeRes = null
	var layout: GDLevelSceneRes = null
	var title: String = ""
	var hovering: bool = false
	var snap_valid: bool = false
	var snap_point: Vector3 = Vector3.ZERO
	var ground: bool = false
	var use_2d: bool = false
	var committed: bool = false
	var suppress: bool = false
	var button_was_down: bool = true
	var ghost: Node = null

	func _init(p_archetype: GDArchetypeRes, p_layout: GDLevelSceneRes) -> void:
		archetype = p_archetype
		layout = p_layout
		title = archetype.display_name if not archetype.display_name.is_empty() else ("Archetype#%d" % archetype.stable_id)

	var can_place: bool:
		get:
			return hovering and snap_valid and not committed and not suppress


## 撤销 / 重做的回调宿主（UndoRedo 需要 Object 方法）。
class Host extends Node:
	func erase_placed(layout: GDLevelSceneRes, inst_id: int) -> void:
		GDLevelSceneDrop.erase_placed(layout, inst_id)
		GDLevelSceneDrop.notify_ui("已撤销摆放")

	func restore_placed(layout: GDLevelSceneRes, snapshot: GDPlacementData.PlacementInstance) -> void:
		GDLevelSceneDrop.restore_placed(layout, snapshot)
		GDLevelSceneDrop.notify_ui("已恢复摆放")


class DropCatcher extends Control:
	func _ready() -> void:
		name = "GdesignerDropCatcher"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		set_process(true)

	func _process(_delta: float) -> void:
		var dragging: bool = GDLevelSceneDrop.is_active()
		mouse_filter = Control.MOUSE_FILTER_STOP if dragging else Control.MOUSE_FILTER_IGNORE

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return GDLevelSceneDrop.is_payload(data)

	func _drop_data(_at: Vector2, _data: Variant) -> void:
		GDLevelSceneDrop.commit_hover()


static func bind_plugin(plugin: EditorPlugin, host: Node) -> void:
	_plugin = plugin
	_host = host


static func bind_status(callback: Callable, on_bound: Callable = Callable()) -> void:
	_status_cb = callback
	_binding_cb = on_bound


static func is_payload(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == DRAG_TYPE


static func is_active() -> bool:
	return session != null


static func is_logical_ground(node: Node) -> bool:
	var current := node
	var guard := 0
	while current != null and guard < 12:
		if String(current.name) == GROUND_NAME:
			return true
		current = current.get_parent()
		guard += 1
	return false


static func ray_intersect_plane(origin: Vector3, dir: Vector3, plane_normal: Vector3, plane_point: Vector3) -> Dictionary:
	var denom := plane_normal.dot(dir)
	if absf(denom) < 0.000001:
		return {"ok": false, "point": plane_point, "ground": false}
	var t := (plane_point - origin).dot(plane_normal) / denom
	if t < 0.0:
		return {"ok": false, "point": origin, "ground": false}
	return {"ok": true, "point": origin + dir * t, "ground": false, "t": t}


static func pick_ground_point(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3) -> Dictionary:
	if space == null or dir.length_squared() < 0.000001:
		return ray_intersect_plane(origin, dir, Vector3.UP, Vector3.ZERO)
	var from := origin
	var end := origin + dir * RAY_LENGTH
	for _i in range(8):
		var query := PhysicsRayQueryParameters3D.create(from, end)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider := hit.get("collider") as Node
		if is_logical_ground(collider):
			return {"ok": true, "point": hit.get("position", from), "ground": true}
		var hit_pos: Vector3 = hit.get("position", from)
		from = hit_pos + dir * 0.05
		if from.distance_squared_to(end) < 0.01:
			break
	return ray_intersect_plane(origin, dir, Vector3.UP, Vector3.ZERO)


static func begin(archetype: GDArchetypeRes, layout: GDLevelSceneRes) -> Dictionary:
	cancel()
	if archetype == null:
		return {}
	session = DragSession.new(archetype, layout)
	_set_status("拖拽中：%s。移到 3D 或 2D 视口后松开。" % session.title, false)
	return {"type": DRAG_TYPE, "stable_id": archetype.stable_id, "display_name": session.title}


static func poll() -> void:
	if session == null:
		return
	var down := _pointer_down()
	_update_hover()
	if session.button_was_down and not down:
		if session.can_place:
			_place_active()
			return
		if not session.committed and not session.suppress:
			_set_status("已取消。按住原型卡片拖到 3D 或 2D 视口再松开。", false)
		cancel()
		return
	session.button_was_down = down


static func commit_hover() -> void:
	if session == null or session.committed or session.suppress:
		return
	_update_hover()
	if session.can_place:
		_place_active()


static func finish_without_placing() -> void:
	if session == null:
		return
	session.suppress = true
	session.committed = true
	_clear_ghost()


static func cancel() -> void:
	_clear_ghost()
	session = null


static func shutdown() -> void:
	cancel()
	_spawned.clear()
	_explicit_parents.clear()
	_layout_owners.clear()
	_plugin = null
	_host = null
	_status_cb = Callable()
	_binding_cb = Callable()


static func scene_changed() -> void:
	cancel()
	_spawned.clear()


## A saved scene and a layout must be explicitly bound before editor nodes are touched.
static func is_bound_to_scene(layout: GDLevelSceneRes, scene_root: Node) -> bool:
	if layout == null or scene_root == null or layout.scene_path.is_empty():
		return false
	if scene_root.scene_file_path.is_empty() or layout.scene_path != scene_root.scene_file_path:
		return false
	if not register_layout(layout):
		return false
	var parent := scene_root.get_node_or_null(PLACEMENTS_ROOT)
	return parent == null or _owns_parent(layout, parent)


static func bind_layout_to_scene(layout: GDLevelSceneRes, scene_root: Node) -> bool:
	if layout == null or scene_root == null or scene_root.scene_file_path.is_empty():
		return false
	if not register_layout(layout):
		return false
	if not layout.scene_path.is_empty() and layout.scene_path != scene_root.scene_file_path:
		return false
	var parent := scene_root.get_node_or_null(PLACEMENTS_ROOT)
	if parent != null and not _owns_parent(layout, parent):
		return false
	var binding_changed := layout.layout_id.is_empty() or layout.scene_path != scene_root.scene_file_path
	var previous_identity := GDSceneEditorRuntime.layout_identity(layout)
	ensure_layout_identity(layout)
	layout.scene_path = scene_root.scene_file_path
	if parent != null:
		parent.set_meta(META_LAYOUT, GDSceneEditorRuntime.layout_identity(layout))
		for child in parent.get_children():
			if child.has_meta(META_ID) and str(child.get_meta(META_LAYOUT, "")) in ["", previous_identity]:
				child.set_meta(META_LAYOUT, GDSceneEditorRuntime.layout_identity(layout))
	if binding_changed and _binding_cb.is_valid():
		_binding_cb.call(layout)
	return true


static func ensure_layout_identity(layout: GDLevelSceneRes) -> void:
	if layout != null and layout.layout_id.is_empty():
		layout.editor_ensure_layout_id()


static func register_layout(layout: GDLevelSceneRes) -> bool:
	if layout == null:
		return false
	for key: String in _layout_owners.keys():
		var stale: WeakRef = _layout_owners[key]
		if stale.get_ref() == null:
			_layout_owners.erase(key)
	var identity := GDSceneEditorRuntime.layout_identity(layout)
	var ref: WeakRef = _layout_owners.get(identity)
	var previous: GDLevelSceneRes = ref.get_ref() as GDLevelSceneRes if ref != null else null
	if previous != null and previous != layout:
		var same_asset := not layout.resource_path.is_empty() and not previous.resource_path.is_empty() \
			and GDDocument.path_key(layout.resource_path) == GDDocument.path_key(previous.resource_path)
		if not same_asset:
			_set_status("关卡标识重复，已阻止场景同步。请为副本重设 layout_id 后重新绑定场景。", false)
			return false
	_layout_owners[identity] = weakref(layout)
	return true


static func request_scene_binding(layout: GDLevelSceneRes, on_bound: Callable) -> void:
	var scene_root := edited_root()
	if is_bound_to_scene(layout, scene_root):
		if layout.layout_id.is_empty():
			bind_layout_to_scene(layout, scene_root)
		on_bound.call()
		return
	if layout == null or scene_root == null or scene_root.scene_file_path.is_empty():
		_set_status("请先保存当前场景，再绑定关卡。", false)
		return
	if not layout.scene_path.is_empty():
		_set_status("当前场景与关卡绑定不一致，请打开 %s。" % layout.scene_path, false)
		return
	if _host == null:
		return
	GDDialogs.confirm(_host, "绑定关卡场景", "将当前关卡绑定到 %s？" % scene_root.scene_file_path, "绑定并继续", func() -> void:
		if not is_instance_valid(scene_root) or edited_root() != scene_root or not bind_layout_to_scene(layout, scene_root):
			_set_status("场景已改变或已有其他关卡占用，绑定已取消。", false)
			return
		on_bound.call()
	)


static func _owns_parent(layout: GDLevelSceneRes, parent: Node) -> bool:
	return register_layout(layout) and str(parent.get_meta(META_LAYOUT, "")) in ["", GDSceneEditorRuntime.layout_identity(layout)]


static func _scene_parent(layout: GDLevelSceneRes, create: bool = false, scene_root: Node = null) -> Node:
	if layout == null:
		return null
	if scene_root == null and not Engine.is_editor_hint():
		var ref: WeakRef = _explicit_parents.get(layout.get_instance_id())
		return ref.get_ref() as Node if ref != null else null
	if scene_root == null:
		scene_root = edited_root()
	if not is_bound_to_scene(layout, scene_root):
		return null
	if layout.layout_id.is_empty():
		bind_layout_to_scene(layout, scene_root)
	return placement_parent(scene_root) if create else scene_root.get_node_or_null(PLACEMENTS_ROOT)


static func _cache_key(layout: GDLevelSceneRes, inst_id: int) -> String:
	return "%s:%d" % [GDSceneEditorRuntime.layout_identity(layout), inst_id]


static func ensure_catcher(overlay: Control) -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	if overlay.get_node_or_null("GdesignerDropCatcher") != null:
		return
	var catcher := DropCatcher.new()
	catcher.name = "GdesignerDropCatcher"
	overlay.add_child(catcher)


static func suggest_drop_point() -> Vector3:
	if not Engine.is_editor_hint():
		return Vector3.ZERO
	for i in range(4):
		var svp: SubViewport = EditorInterface.get_editor_viewport_3d(i)
		if svp == null:
			continue
		var container := svp.get_parent() as Control
		if container == null or not container.is_visible_in_tree():
			continue
		var camera := svp.get_camera_3d()
		if camera == null:
			continue
		var center := Vector2(svp.size) * 0.5
		var origin := camera.project_ray_origin(center)
		var dir := camera.project_ray_normal(center)
		var picked := _pick_in_edited_scene(origin, dir)
		if bool(picked.get("ok", false)):
			return picked.get("point", Vector3.ZERO)
	return Vector3.ZERO


static func place_archetype(layout: GDLevelSceneRes, archetype: GDArchetypeRes, point: Vector3, scene_parent: Node = null) -> Dictionary:
	if layout == null or archetype == null:
		return {"ok": false, "instance_id": 0, "error": "无关卡或原型。"}
	var host := scene_parent
	if host == null:
		host = _scene_parent(layout, true)
	if host == null or not _owns_parent(layout, host):
		return {"ok": false, "instance_id": 0, "error": "请先将关卡绑定到当前已保存的场景。"}
	if Engine.is_editor_hint() and host != _scene_parent(layout, true):
		return {"ok": false, "instance_id": 0, "error": "当前场景与关卡绑定不一致。"}
	var added := layout.editor_try_add_placement(archetype.stable_id, point, Vector3.ZERO, Vector3.ONE, 1)
	if not bool(added.get("ok", false)):
		var err := str(added.get("error", "添加失败"))
		_set_status(err, false)
		return {"ok": false, "instance_id": 0, "error": err}
	var inst_id := int(added.get("instance_id", 0))
	var node := spawn_into(layout, inst_id, host)
	var found := layout.editor_try_get_placement(inst_id)
	if bool(found.get("ok", false)):
		_register_history(layout, found["inst"], true)
	focus_instance(inst_id, layout)
	var title := archetype.display_name if not archetype.display_name.is_empty() else str(archetype.stable_id)
	var where := "场景" if node != null else "关卡数据（当前没有可写入的父节点）"
	_set_status("已摆放 %s 到%s，位置 %s" % [title, where, _fmt_vec(point)], true)
	return {"ok": true, "instance_id": inst_id, "error": "", "node": node}


static func delete_placement(layout: GDLevelSceneRes, inst_id: int) -> void:
	if layout == null or inst_id <= 0:
		return
	var found := layout.editor_try_get_placement(inst_id)
	var snapshot: GDPlacementData.PlacementInstance = found.get("inst") if bool(found.get("ok", false)) else null
	erase_placed(layout, inst_id)
	if snapshot != null:
		_register_history(layout, snapshot, false)


static func sync_layout_to_scene(layout: GDLevelSceneRes) -> Dictionary:
	if layout == null:
		return {"ok": false, "spawned": 0, "message": "无关卡。"}
	var host := _scene_parent(layout, true)
	if host == null:
		return {"ok": false, "spawned": 0, "message": "请先将关卡绑定到当前已保存的场景。"}
	var spawned := 0
	for inst in layout.placements:
		if inst == null:
			continue
		if find_placed_node(inst.instance_id, layout) != null:
			continue
		spawn_into(layout, inst.instance_id, host)
		_register_history(layout, inst, true)
		spawned += 1
	var message := "已把 %d 个实例同步到当前场景的 Placements 下。" % spawned if spawned > 0 else "场景里已经有全部实例。"
	_set_status(message, true)
	return {"ok": true, "spawned": spawned, "message": message}


## 把场景里实例节点的位姿写回关卡。返回是否有改动。
static func pull_transforms_from_scene(layout: GDLevelSceneRes, scene_root: Node = null) -> bool:
	if layout == null or _scene_parent(layout, false, scene_root) == null:
		return false
	var changed := false
	for inst in layout.placements.duplicate():
		if inst == null:
			continue
		var node := find_placed_node(inst.instance_id, layout, scene_root)
		var pos: Vector3 = inst.position
		var euler: Vector3 = inst.euler_angles
		var scl: Vector3 = inst.scale
		if node is Node3D:
			var n3 := node as Node3D
			pos = n3.position
			euler = n3.rotation_degrees
			scl = n3.scale
		elif node is Node2D:
			var n2 := node as Node2D
			pos = Vector3(n2.position.x, n2.position.y, pos.z)
			euler = Vector3(euler.x, euler.y, n2.rotation_degrees)
			scl = Vector3(n2.scale.x, n2.scale.y, scl.z)
		else:
			continue
		if not (pos.is_equal_approx(inst.position) and euler.is_equal_approx(inst.euler_angles) and scl.is_equal_approx(inst.scale)):
			layout.editor_replace_placement(inst.instance_id, inst.with_transform(pos, euler, scl))
			changed = true
	return changed


## 让场景与关卡数据一致：补生成缺失的实例、删掉关卡里已不存在的实例节点（Placements 下带 META_ID 的节点）、同步变换。
## scene_parent 为空时作用于当前编辑场景的 Placements；没有编辑场景则什么都不做。撤销 / 重做后调用。
static func reconcile_scene(layout: GDLevelSceneRes, scene_parent: Node = null) -> void:
	if layout == null:
		return
	var host := scene_parent
	if host == null:
		if not Engine.is_editor_hint():
			return
		host = _scene_parent(layout, not layout.placements.is_empty())
	if host == null or not _owns_parent(layout, host):
		return
	host.set_meta(META_LAYOUT, GDSceneEditorRuntime.layout_identity(layout))
	var by_id := {}
	for inst in layout.placements:
		if inst != null:
			by_id[inst.instance_id] = inst
	var placed := {}
	for child in host.get_children():
		if not child.has_meta(META_ID) or not _node_matches_layout(child, layout):
			continue
		var id := int(child.get_meta(META_ID))
		if by_id.has(id) and not placed.has(id):
			placed[id] = child
		else:
			_spawned.erase(_cache_key(layout, id))
			child.free()
	for id in by_id:
		var inst: GDPlacementData.PlacementInstance = by_id[id]
		var node: Node = placed.get(id)
		var marker: GDSceneEditorRuntime.PlacementInstanceMarker = null
		if node != null:
			marker = node.get_node_or_null("PlacementInstanceMarker") as GDSceneEditorRuntime.PlacementInstanceMarker
		if marker != null and marker.archetype_stable_id != inst.archetype_stable_id:
			# 原型换了（例如撤销了“替换原型”）：外观也要跟着换。
			_spawned.erase(_cache_key(layout, id))
			node.free()
			node = null
		if node != null:
			_apply_pose(node, inst.position, inst.euler_angles, inst.scale)
		else:
			spawn_into(layout, id, host)


static func apply_transform(inst_id: int, pos: Vector3, euler: Vector3, scl: Vector3, layout: GDLevelSceneRes = null) -> void:
	var node := find_placed_node(inst_id, layout)
	if node is Node3D:
		var n3 := node as Node3D
		n3.position = pos
		n3.rotation_degrees = euler
		n3.scale = scl
	elif node is Node2D:
		var n2 := node as Node2D
		n2.position = Vector2(pos.x, pos.y)
		n2.rotation_degrees = euler.z
		n2.scale = Vector2(scl.x, scl.y)


static func respawn(layout: GDLevelSceneRes, inst_id: int) -> void:
	if layout == null:
		return
	var existing := find_placed_node(inst_id, layout)
	var parent: Node = existing.get_parent() if existing != null else null
	if existing != null and is_instance_valid(existing):
		_spawned.erase(_cache_key(layout, inst_id))
		existing.free()
	if parent == null:
		parent = _scene_parent(layout, true)
	if parent == null:
		return
	spawn_into(layout, inst_id, parent)


static func focus_instance(inst_id: int, layout: GDLevelSceneRes = null) -> void:
	if not Engine.is_editor_hint():
		return
	var node := find_placed_node(inst_id, layout)
	if node == null:
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)
	EditorInterface.edit_node(node)


static func erase_placed(layout: GDLevelSceneRes, inst_id: int) -> void:
	if layout == null:
		return
	var node := find_placed_node(inst_id, layout)
	if node != null and is_instance_valid(node):
		_spawned.erase(_cache_key(layout, inst_id))
		node.free()
	layout.editor_remove_placement(inst_id)


static func restore_placed(layout: GDLevelSceneRes, snapshot: GDPlacementData.PlacementInstance) -> void:
	if layout == null or snapshot == null:
		return
	if not bool(layout.editor_try_get_placement(snapshot.instance_id).get("ok", false)):
		layout.placements.append(snapshot)
		layout.emit_changed()
	var parent := _scene_parent(layout, true)
	if parent != null and find_placed_node(snapshot.instance_id, layout) == null:
		spawn_into(layout, snapshot.instance_id, parent)


static func find_placed_node(inst_id: int, layout: GDLevelSceneRes = null, scene_root: Node = null) -> Node:
	if layout == null:
		# Retain the low-level headless API only when the ID is unambiguous.
		if Engine.is_editor_hint():
			return null
		var matches: Array[Node] = []
		for cached: Variant in _spawned.values():
			if is_instance_valid(cached) and int(cached.get_meta(META_ID, 0)) == inst_id:
				matches.append(cached)
		return matches[0] if matches.size() == 1 else null
	var parent := _scene_parent(layout, false, scene_root)
	if parent == null or not _owns_parent(layout, parent):
		return null
	for child in parent.get_children():
		if int(child.get_meta(META_ID, 0)) == inst_id and _node_matches_layout(child, layout, scene_root):
			parent.set_meta(META_LAYOUT, GDSceneEditorRuntime.layout_identity(layout))
			child.set_meta(META_LAYOUT, GDSceneEditorRuntime.layout_identity(layout))
			return child
	return null


static func _node_matches_layout(node: Node, layout: GDLevelSceneRes, scene_root: Node = null) -> bool:
	var identity := str(node.get_meta(META_LAYOUT, ""))
	if scene_root == null:
		scene_root = edited_root()
	return identity == GDSceneEditorRuntime.layout_identity(layout) or (identity.is_empty() and is_bound_to_scene(layout, scene_root))


static func spawn_into(layout: GDLevelSceneRes, inst_id: int, parent: Node) -> Node:
	if layout == null or parent == null or inst_id <= 0:
		return null
	if not _owns_parent(layout, parent):
		return null
	if Engine.is_editor_hint() and parent != _scene_parent(layout, true):
		return null
	var found := layout.editor_try_get_placement(inst_id)
	if not bool(found.get("ok", false)):
		return null
	var inst: GDPlacementData.PlacementInstance = found["inst"]
	var arch := layout.find_archetype_by_stable_id(inst.archetype_stable_id)
	var node := _build_visual(arch, parent is Node2D)
	node.name = _safe_name(GDPlacementData.PlacementInstanceIdRangeLogic.resolve_display_name(inst, arch), inst_id)
	node.set_meta(META_ID, inst_id)
	node.set_meta(META_LAYOUT, GDSceneEditorRuntime.layout_identity(layout))
	parent.set_meta(META_LAYOUT, GDSceneEditorRuntime.layout_identity(layout))
	_apply_pose(node, inst.position, inst.euler_angles, inst.scale)
	parent.add_child(node)
	var scene_root := _owner_root(parent)
	if scene_root != null:
		_own(node, scene_root)
	var marker := GDSceneEditorRuntime.PlacementInstanceMarker.new()
	marker.name = "PlacementInstanceMarker"
	var type_id := arch.archetype_type_stable_id if arch != null else 0
	marker.bind(inst.instance_id, inst.archetype_stable_id, type_id)
	node.add_child(marker)
	if scene_root != null:
		marker.owner = scene_root
	if not inst.attribute_overrides.is_empty():
		GDEntityAtomSystem.AtomVarTagRegistry.apply_overrides_to_node(node, inst.attribute_overrides)
	var key := _cache_key(layout, inst_id)
	_spawned[key] = node
	if not Engine.is_editor_hint():
		_explicit_parents[layout.get_instance_id()] = weakref(parent)
	node.tree_exiting.connect(func() -> void:
		if _spawned.get(key) == node:
			_spawned.erase(key)
	)
	return node


static func placement_parent(scene_root: Node) -> Node:
	if scene_root == null:
		return null
	var existing := scene_root.get_node_or_null(PLACEMENTS_ROOT)
	if existing != null:
		return existing
	var holder: Node = Node2D.new() if scene_root is Node2D else Node3D.new()
	holder.name = PLACEMENTS_ROOT
	scene_root.add_child(holder)
	holder.owner = scene_root if scene_root.owner == null else scene_root.owner
	return holder


static func _pointer_down() -> bool:
	# headless 的 DisplayServer 没有鼠标；编辑器里才读按键状态。
	if DisplayServer.get_name() == "headless":
		return false
	return (DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) != 0


static func edited_root() -> Node:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_edited_scene_root()


static func notify_ui(text: String) -> void:
	_set_status(text, true)


static func _place_active() -> void:
	var placing := session
	cancel()
	request_scene_binding(placing.layout, func() -> void:
		var result := place_archetype(placing.layout, placing.archetype, placing.snap_point)
		if not bool(result.get("ok", false)):
			_set_status(str(result.get("error", "落点失败")), false)
	)


static func _register_history(layout: GDLevelSceneRes, snapshot: GDPlacementData.PlacementInstance, undo_erases: bool) -> void:
	if _plugin == null or _host == null or layout == null or snapshot == null:
		return
	if not Engine.is_editor_hint():
		return
	var undo := _plugin.get_undo_redo()
	undo.create_action("摆放原型", UndoRedo.MERGE_DISABLE, edited_root())
	if undo_erases:
		undo.add_undo_method(_host, "erase_placed", layout, snapshot.instance_id)
		undo.add_do_method(_host, "restore_placed", layout, snapshot)
	else:
		undo.add_undo_method(_host, "restore_placed", layout, snapshot)
		undo.add_do_method(_host, "erase_placed", layout, snapshot.instance_id)
	undo.commit_action(false)


static func _update_hover() -> void:
	if session == null:
		return
	if not Engine.is_editor_hint():
		session.hovering = false
		session.snap_valid = false
		return
	var hit3 := _hover_3d()
	if bool(hit3.get("hit", false)):
		_store_hover(hit3, false)
		return
	var hit2 := _hover_2d()
	if bool(hit2.get("hit", false)):
		_store_hover(hit2, true)
		return
	session.hovering = false
	session.snap_valid = false
	_clear_ghost()
	_set_status("拖拽中：%s。当前鼠标不在 3D / 2D 视口里。" % session.title, false)


static func _store_hover(hit: Dictionary, use_2d: bool) -> void:
	session.hovering = true
	session.use_2d = use_2d
	session.snap_valid = bool(hit.get("ok", false))
	session.snap_point = hit.get("point", Vector3.ZERO)
	session.ground = bool(hit.get("ground", false))
	if session.snap_valid:
		var ground_note := "逻辑地面" if session.ground else ("2D 平面" if use_2d else "Y=0 平面")
		_set_status("松开把 %s 放到%s %s" % [session.title, ground_note, _fmt_vec(session.snap_point)], false)
		_update_ghost(session.snap_point, use_2d, true)
	else:
		_set_status("视口里没有可落点（请打开场景）。", false)
		_update_ghost(Vector3.ZERO, use_2d, false)


static func _hover_3d() -> Dictionary:
	for i in range(4):
		var svp: SubViewport = EditorInterface.get_editor_viewport_3d(i)
		if svp == null:
			continue
		var container := svp.get_parent() as Control
		if not _mouse_over_control(container):
			continue
		var camera := svp.get_camera_3d()
		if camera == null or edited_root() == null:
			return {"hit": true, "ok": false}
		var local := _mouse_local(container)
		var vp_pos := local
		if container.size.x > 1.0 and container.size.y > 1.0:
			vp_pos = local * Vector2(svp.size) / container.size
		var origin := camera.project_ray_origin(vp_pos)
		var dir := camera.project_ray_normal(vp_pos)
		var picked := _pick_in_edited_scene(origin, dir)
		picked["hit"] = true
		return picked
	return {"hit": false}


static func _hover_2d() -> Dictionary:
	var svp: SubViewport = EditorInterface.get_editor_viewport_2d()
	if svp == null:
		return {"hit": false}
	var container := svp.get_parent() as Control
	if not _mouse_over_control(container):
		return {"hit": false}
	if edited_root() == null:
		return {"hit": true, "ok": false}
	var local := _mouse_local(container)
	var vp_pos := local
	if container.size.x > 1.0 and container.size.y > 1.0:
		vp_pos = local * Vector2(svp.size) / container.size
	var world_2d: Vector2 = svp.get_canvas_transform().affine_inverse() * vp_pos
	return {"hit": true, "ok": true, "point": Vector3(world_2d.x, world_2d.y, 0.0), "ground": false}


static func _pick_in_edited_scene(origin: Vector3, dir: Vector3) -> Dictionary:
	var root := edited_root()
	if root is Node3D:
		var world := (root as Node3D).get_world_3d()
		if world != null:
			return pick_ground_point(world.direct_space_state, origin, dir)
	return ray_intersect_plane(origin, dir, Vector3.UP, Vector3.ZERO)


static func _mouse_over_control(control: Control) -> bool:
	if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
		return false
	return _mouse_inside_window(control)


static func _mouse_inside_window(control: Control) -> bool:
	var win := control.get_window()
	if win == null:
		return false
	var mouse := Vector2(DisplayServer.mouse_get_position())
	var origin := Vector2(DisplayServer.window_get_position(win.get_window_id()))
	var local := mouse - origin
	return control.get_global_rect().has_point(local)


static func _mouse_local(control: Control) -> Vector2:
	var win := control.get_window()
	var mouse := Vector2(DisplayServer.mouse_get_position())
	var origin := Vector2(DisplayServer.window_get_position(win.get_window_id()))
	return mouse - origin - control.get_global_rect().position


static func _update_ghost(point: Vector3, use_2d: bool, visible: bool) -> void:
	var root := edited_root()
	if root == null:
		_clear_ghost()
		return
	var ghost := session.ghost
	var want_2d := use_2d and root is Node2D
	if ghost == null or not is_instance_valid(ghost) or (want_2d and not (ghost is Node2D)) or (not want_2d and ghost is Node2D):
		_clear_ghost()
		ghost = _build_visual(session.archetype, want_2d)
		ghost.name = GHOST_NAME
		_strip_ghost(ghost)
		root.add_child(ghost)
		ghost.owner = null
		session.ghost = ghost
	_apply_pose(ghost, point, Vector3.ZERO, Vector3.ONE)
	ghost.visible = visible
	if ghost.owner != null:
		ghost.owner = null


static func _clear_ghost() -> void:
	if session == null:
		return
	var ghost := session.ghost
	session.ghost = null
	if ghost != null and is_instance_valid(ghost):
		ghost.free()


static func _build_visual(archetype: GDArchetypeRes, as_2d: bool) -> Node:
	var packed: PackedScene = null
	if archetype != null:
		packed = archetype.editor_resolve_manufactured_prefab()
		if packed == null:
			packed = archetype.editor_resolve_preview_prefab()
	if as_2d:
		if packed != null:
			var raw := packed.instantiate()
			if raw is Node2D:
				return raw
			var wrap := Node2D.new()
			wrap.add_child(raw)
			return wrap
		var flat := Node2D.new()
		var rect := ColorRect.new()
		rect.size = Vector2(48, 48)
		rect.position = Vector2(-24, -24)
		rect.color = Color(0.3, 0.85, 0.45, 0.85)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flat.add_child(rect)
		return flat
	if packed != null:
		var raw3 := packed.instantiate()
		if raw3 is Node3D:
			return raw3
		var wrap3 := Node3D.new()
		wrap3.add_child(raw3)
		return wrap3
	var body := Node3D.new()
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	mesh_node.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.85, 0.45, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_node.material_override = mat
	body.add_child(mesh_node)
	return body


static func _strip_ghost(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_strip_ghost(child)


static func _apply_pose(node: Node, pos: Vector3, euler: Vector3, scl: Vector3) -> void:
	if node is Node3D:
		var n3 := node as Node3D
		n3.position = pos
		n3.rotation_degrees = euler
		n3.scale = scl
	elif node is Node2D:
		var n2 := node as Node2D
		n2.position = Vector2(pos.x, pos.y)
		n2.rotation_degrees = euler.z
		n2.scale = Vector2(scl.x, scl.y)


static func _own(node: Node, scene_root: Node) -> void:
	if node != scene_root:
		node.owner = scene_root
	for child in node.get_children():
		_own(child, scene_root)


static func _owner_root(parent: Node) -> Node:
	var edited := edited_root()
	if edited != null:
		return edited
	if parent != null and parent.owner != null:
		return parent.owner
	return parent


static func _safe_name(text: String, inst_id: int) -> String:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		cleaned = "Placement_%d" % inst_id
	return cleaned.replace("/", "_").replace(":", "_").replace("@", "_")


static func _fmt_vec(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


static func _set_status(text: String, refresh_ui: bool) -> void:
	if text == _last_status and not refresh_ui:
		return
	_last_status = text
	if _status_cb.is_valid():
		_status_cb.call(text, refresh_ui)
