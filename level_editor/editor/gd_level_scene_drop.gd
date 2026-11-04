@tool
class_name GDLevelSceneDrop
extends RefCounted

## 把建筑原型拖进 Godot 正在编辑的场景。
##
## Unity 侧是 EditorWindow + DragAndDrop + SceneView.duringSceneGui：拖拽是编辑器全局状态，
## Scene 视图每帧收 DragUpdated / DragPerform，吸附到名为 "[SceneEditor Ground]" 的逻辑地面后写入 LevelSceneSO 并生成实例。
##
## Godot 没有全局 DragAndDrop。Control._get_drag_data 是进程内拖拽（Godot 4 可跨同一进程的 Window）。
## 3D/2D 主视口只接受 files / nodes / resource，不认识策划原型的 StableId。
## 因此这里做两件事，都合编辑器插件规范：
##   1. 卡片 _get_drag_data 发起拖拽（窗口内的「替换原型」区可以直接接住）。
##   2. EditorPlugin.set_force_draw_over_forwarding_enabled() 在视口上放一个只在拖拽期间拦截的 Control，
##      同时用 DisplayServer 鼠标位置做射线吸附。不实现 _handles()，避免抢走当前选中节点的 Inspector。
## 落下的节点写进当前场景的 Placements 容器（owner = 场景根，会随场景保存），并写入关卡资源。
## 运行时 load_session 若发现同 instance_id 的节点就直接采纳，不会再生成一份。

const DRAG_TYPE := "gdesigner_archetype"
const GHOST_NAME := "[Archetype Drag Ghost]"
const GROUND_NAME := "[SceneEditor Ground]"
const PLACEMENTS_ROOT := "Placements"
const META_ID := "gdesigner_placement_id"
const RAY_LENGTH := 4000.0

static var active: Dictionary = {}
static var _spawned: Dictionary = {} # int -> Node
static var _plugin: EditorPlugin = null
static var _host: Node = null
static var _status_cb: Callable = Callable()
static var _last_status: String = ""


class Host extends Node:
	func erase_placed(layout: GDLevelSceneRes, inst_id: int) -> void:
		var api := load("res://addons/gdesigner_tools/level_editor/editor/gd_level_scene_drop.gd")
		api.erase_placed(layout, inst_id)
		api.notify_ui("已撤销摆放")

	func restore_placed(layout: GDLevelSceneRes, snapshot: GDPlacementData.PlacementInstance) -> void:
		var api := load("res://addons/gdesigner_tools/level_editor/editor/gd_level_scene_drop.gd")
		api.restore_placed(layout, snapshot)
		api.notify_ui("已恢复摆放")


class DragSource extends Control:
	var archetype: GDArchetypeRes = null
	var layout_getter: Callable = Callable()
	var on_click: Callable = Callable()
	var selected: bool = false
	var title_text: String = ""
	var _dragged: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(148, 58)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tooltip_text = "按住拖到 3D 或 2D 视口后松开落点。单击只查看属性。"
		resized.connect(queue_redraw)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if _dragged or get_viewport().gui_is_dragging():
				_dragged = false
				accept_event()
				return
			if on_click.is_valid():
				on_click.call()
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		_dragged = true
		var layout: GDLevelSceneRes = null
		if layout_getter.is_valid():
			layout = layout_getter.call()
		var payload: Dictionary = load("res://addons/gdesigner_tools/level_editor/editor/gd_level_scene_drop.gd").begin(archetype, layout)
		var preview := Label.new()
		preview.text = title_text if not title_text.is_empty() else "原型"
		preview.add_theme_color_override("font_color", Color(0.85, 1.0, 0.9))
		set_drag_preview(preview)
		return payload

	func _draw() -> void:
		var bg := Color(0.16, 0.36, 0.58, 1.0) if selected else Color(0.13, 0.15, 0.19, 1.0)
		var border := Color(0.55, 0.82, 1.0) if selected else Color(1, 1, 1, 0.1)
		GDEditorUi.paint_round_rect(self, Rect2(Vector2.ZERO, size), bg, border, 6, 2 if selected else 1)
		draw_rect(Rect2(Vector2(0, 8), Vector2(3, maxf(10.0, size.y - 16.0))), Color(0.55, 0.86, 1.0) if selected else Color(0.45, 0.78, 0.62))
		var font := get_theme_default_font()
		if font == null:
			return
		var font_size := get_theme_default_font_size()
		font.draw_string(get_canvas_item(), Vector2(12, font_size + 4), title_text, HORIZONTAL_ALIGNMENT_LEFT, maxf(8.0, size.x - 20.0), font_size, Color(0.97, 0.98, 1.0))
		font.draw_string(get_canvas_item(), Vector2(12, font_size * 2 + 8), "按住拖到视口", HORIZONTAL_ALIGNMENT_LEFT, maxf(8.0, size.x - 20.0), maxi(11, font_size - 2), Color(0.72, 0.9, 0.78))


class ReplaceDrop extends PanelContainer:
	var instance_id: int = 0
	var layout_getter: Callable = Callable()
	var on_replaced: Callable = Callable()

	func _init() -> void:
		custom_minimum_size.y = 56
		mouse_filter = Control.MOUSE_FILTER_STOP
		GDEditorUi.style_card(self, false)
		var label := Label.new()
		label.text = "把左侧原型拖到这里\n只换原型，位置和旋转会保留"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 1
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.8))
		add_child(label)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return load("res://addons/gdesigner_tools/level_editor/editor/gd_level_scene_drop.gd").is_payload(data)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		load("res://addons/gdesigner_tools/level_editor/editor/gd_level_scene_drop.gd").finish_without_placing()
		if not layout_getter.is_valid():
			return
		var layout: GDLevelSceneRes = layout_getter.call()
		if layout == null:
			return
		var stable_id := int(data.get("stable_id", 0))
		if layout.editor_replace_placement_archetype(instance_id, stable_id):
			load("res://addons/gdesigner_tools/level_editor/editor/gd_level_scene_drop.gd").respawn(layout, instance_id)
			if on_replaced.is_valid():
				on_replaced.call()


class DropCatcher extends Control:
	func _ready() -> void:
		name = "GdesignerDropCatcher"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		set_process(true)

	func _process(_delta: float) -> void:
		var dragging: bool = load("res://addons/gdesigner_tools/level_editor/editor/gd_level_scene_drop.gd").is_active()
		mouse_filter = Control.MOUSE_FILTER_STOP if dragging else Control.MOUSE_FILTER_IGNORE

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return load("res://addons/gdesigner_tools/level_editor/editor/gd_level_scene_drop.gd").is_payload(data)

	func _drop_data(_at: Vector2, _data: Variant) -> void:
		load("res://addons/gdesigner_tools/level_editor/editor/gd_level_scene_drop.gd").commit_hover()


static func bind_plugin(plugin: EditorPlugin, host: Node) -> void:
	_plugin = plugin
	_host = host


static func bind_status(callback: Callable) -> void:
	_status_cb = callback


static func is_payload(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == DRAG_TYPE


static func is_active() -> bool:
	return not active.is_empty()


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
	var title := archetype.display_name if not archetype.display_name.is_empty() else ("Archetype#%d" % archetype.stable_id)
	active = {
		"archetype": archetype,
		"layout": layout,
		"stable_id": archetype.stable_id,
		"title": title,
		"snap_valid": false,
		"snap_point": Vector3.ZERO,
		"hovering": false,
		"committed": false,
		"suppress": false,
		"ground": false,
		"use_2d": false,
		"button_was_down": true,
		"ghost": null,
	}
	_set_status("拖拽中：%s。移到 3D 或 2D 视口后松开。" % title, false)
	return {"type": DRAG_TYPE, "stable_id": archetype.stable_id, "display_name": title}


static func poll() -> void:
	if active.is_empty():
		return
	var down := _pointer_down()
	_update_hover()
	var was_down := bool(active.get("button_was_down", true))
	if was_down and not down:
		if not bool(active.get("committed", false)) and not bool(active.get("suppress", false)):
			if bool(active.get("hovering", false)) and bool(active.get("snap_valid", false)):
				_place_active(active.get("snap_point", Vector3.ZERO))
				return
			_set_status("已取消。按住原型卡片拖到 3D 或 2D 视口再松开。", false)
		_clear_ghost()
		active.clear()
		return
	active["button_was_down"] = down


static func commit_hover() -> void:
	if active.is_empty() or bool(active.get("committed", false)) or bool(active.get("suppress", false)):
		return
	_update_hover()
	if bool(active.get("hovering", false)) and bool(active.get("snap_valid", false)):
		_place_active(active.get("snap_point", Vector3.ZERO))


static func finish_without_placing() -> void:
	if active.is_empty():
		return
	active["suppress"] = true
	active["committed"] = true
	_clear_ghost()


static func cancel() -> void:
	_clear_ghost()
	active.clear()


static func shutdown() -> void:
	cancel()
	_plugin = null
	_host = null
	_status_cb = Callable()


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
		var scene_root := edited_root()
		if scene_root == null:
			return {"ok": false, "instance_id": 0, "error": "请先打开一个场景，再把原型拖进 3D 或 2D 视口。"}
		host = placement_parent(scene_root)
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
	focus_instance(inst_id)
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
	var scene_root := edited_root()
	if scene_root == null:
		return {"ok": false, "spawned": 0, "message": "请先打开一个场景。"}
	var host := placement_parent(scene_root)
	var spawned := 0
	for inst in layout.placements:
		if inst == null:
			continue
		if find_placed_node(inst.instance_id) != null:
			continue
		spawn_into(layout, inst.instance_id, host)
		_register_history(layout, inst, true)
		spawned += 1
	var message := "已把 %d 个实例同步到当前场景的 Placements 下。" % spawned if spawned > 0 else "场景里已经有全部实例。"
	_set_status(message, true)
	return {"ok": true, "spawned": spawned, "message": message}


static func pull_transforms_from_scene(layout: GDLevelSceneRes) -> void:
	if layout == null:
		return
	for inst in layout.placements:
		if inst == null:
			continue
		var node := find_placed_node(inst.instance_id)
		if node is Node3D:
			var n3 := node as Node3D
			layout.editor_replace_placement(inst.instance_id, inst.with_transform(n3.position, n3.rotation_degrees, n3.scale))
		elif node is Node2D:
			var n2 := node as Node2D
			var pos := Vector3(n2.position.x, n2.position.y, inst.position.z)
			var euler := Vector3(inst.euler_angles.x, inst.euler_angles.y, n2.rotation_degrees)
			var scl := Vector3(n2.scale.x, n2.scale.y, inst.scale.z)
			layout.editor_replace_placement(inst.instance_id, inst.with_transform(pos, euler, scl))


static func apply_transform(inst_id: int, pos: Vector3, euler: Vector3, scl: Vector3) -> void:
	var node := find_placed_node(inst_id)
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
	var existing := find_placed_node(inst_id)
	var parent: Node = existing.get_parent() if existing != null else null
	if existing != null and is_instance_valid(existing):
		_spawned.erase(inst_id)
		existing.free()
	if parent == null:
		var scene_root := edited_root()
		if scene_root == null:
			return
		parent = placement_parent(scene_root)
	spawn_into(layout, inst_id, parent)


static func focus_instance(inst_id: int) -> void:
	if not Engine.is_editor_hint():
		return
	var node := find_placed_node(inst_id)
	if node == null:
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)
	EditorInterface.edit_node(node)


static func erase_placed(layout: GDLevelSceneRes, inst_id: int) -> void:
	var node := find_placed_node(inst_id)
	if node != null and is_instance_valid(node):
		_spawned.erase(inst_id)
		node.free()
	if layout != null:
		layout.editor_remove_placement(inst_id)


static func restore_placed(layout: GDLevelSceneRes, snapshot: GDPlacementData.PlacementInstance) -> void:
	if layout == null or snapshot == null:
		return
	if not bool(layout.editor_try_get_placement(snapshot.instance_id).get("ok", false)):
		layout.placements.append(snapshot)
		layout.emit_changed()
	var parent := _parent_for_restore()
	if parent != null and find_placed_node(snapshot.instance_id) == null:
		spawn_into(layout, snapshot.instance_id, parent)


static func find_placed_node(inst_id: int) -> Node:
	if _spawned.has(inst_id):
		var cached: Node = _spawned[inst_id]
		if is_instance_valid(cached):
			return cached
		_spawned.erase(inst_id)
	var scene_root := edited_root()
	if scene_root != null:
		return GDSceneEditorRuntime.find_placement_root(scene_root, inst_id)
	return null


static func spawn_into(layout: GDLevelSceneRes, inst_id: int, parent: Node) -> Node:
	if layout == null or parent == null or inst_id <= 0:
		return null
	var found := layout.editor_try_get_placement(inst_id)
	if not bool(found.get("ok", false)):
		return null
	var inst: GDPlacementData.PlacementInstance = found["inst"]
	var arch := layout.find_archetype_by_stable_id(inst.archetype_stable_id)
	var node := _build_visual(arch, parent is Node2D)
	node.name = _safe_name(GDPlacementData.PlacementInstanceIdRangeLogic.resolve_display_name(inst, arch), inst_id)
	node.set_meta(META_ID, inst_id)
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
	if inst.attribute_overrides != null and not inst.attribute_overrides.is_empty():
		GDEntityAtomSystem.AtomVarTagRegistry.apply_overrides_to_node(node, inst.attribute_overrides)
	_spawned[inst_id] = node
	node.tree_exiting.connect(func() -> void:
		if _spawned.get(inst_id) == node:
			_spawned.erase(inst_id)
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


static func _place_active(point: Vector3) -> void:
	if active.is_empty():
		return
	active["committed"] = true
	var layout: GDLevelSceneRes = active.get("layout")
	var archetype: GDArchetypeRes = active.get("archetype")
	_clear_ghost()
	active.clear()
	var result := place_archetype(layout, archetype, point)
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("error", "落点失败")), false)


static func _register_history(layout: GDLevelSceneRes, snapshot: GDPlacementData.PlacementInstance, undo_erases: bool) -> void:
	if _plugin == null or _host == null or layout == null or snapshot == null:
		return
	if not Engine.is_editor_hint():
		return
	var undo := _plugin.get_undo_redo()
	undo.create_action("摆放原型")
	if undo_erases:
		undo.add_undo_method(_host, "erase_placed", layout, snapshot.instance_id)
		undo.add_do_method(_host, "restore_placed", layout, snapshot)
	else:
		undo.add_undo_method(_host, "restore_placed", layout, snapshot)
		undo.add_do_method(_host, "erase_placed", layout, snapshot.instance_id)
	undo.commit_action(false)


static func _update_hover() -> void:
	if active.is_empty():
		return
	if not Engine.is_editor_hint():
		active["hovering"] = false
		active["snap_valid"] = false
		return
	var hit3 := _hover_3d()
	if bool(hit3.get("hit", false)):
		_store_hover(hit3, false)
		return
	var hit2 := _hover_2d()
	if bool(hit2.get("hit", false)):
		_store_hover(hit2, true)
		return
	active["hovering"] = false
	active["snap_valid"] = false
	_clear_ghost()
	var title := str(active.get("title", "原型"))
	_set_status("拖拽中：%s。当前鼠标不在 3D / 2D 视口里。" % title, false)


static func _store_hover(hit: Dictionary, use_2d: bool) -> void:
	active["hovering"] = true
	active["use_2d"] = use_2d
	active["snap_valid"] = bool(hit.get("ok", false))
	active["snap_point"] = hit.get("point", Vector3.ZERO)
	active["ground"] = bool(hit.get("ground", false))
	var title := str(active.get("title", "原型"))
	if bool(active["snap_valid"]):
		var ground_note := "逻辑地面" if bool(active["ground"]) else ("2D 平面" if use_2d else "Y=0 平面")
		_set_status("松开把 %s 放到%s %s" % [title, ground_note, _fmt_vec(active["snap_point"])], false)
		_update_ghost(active["snap_point"], use_2d, true)
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
	var ghost: Node = active.get("ghost")
	var archetype: GDArchetypeRes = active.get("archetype")
	var want_2d := use_2d and root is Node2D
	if ghost == null or not is_instance_valid(ghost) or (want_2d and not (ghost is Node2D)) or (not want_2d and ghost is Node2D):
		_clear_ghost()
		ghost = _build_visual(archetype, want_2d)
		ghost.name = GHOST_NAME
		_strip_ghost(ghost)
		root.add_child(ghost)
		ghost.owner = null
		active["ghost"] = ghost
	_apply_pose(ghost, point, Vector3.ZERO, Vector3.ONE)
	ghost.visible = visible
	if ghost.owner != null:
		ghost.owner = null


static func _clear_ghost() -> void:
	if active.is_empty():
		return
	var ghost: Node = active.get("ghost")
	active["ghost"] = null
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


static func _parent_for_restore() -> Node:
	var scene_root := edited_root()
	if scene_root == null:
		return null
	return placement_parent(scene_root)


static func _safe_name(text: String, inst_id: int) -> String:
	var cleaned := text.strip_edges() if text != null else ""
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
