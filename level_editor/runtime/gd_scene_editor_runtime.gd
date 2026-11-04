@tool
class_name GDSceneEditorRuntime
extends RefCounted

## SceneEditor 运行时一行装配入口、PlacementSession、PlacementInstanceRegistry 与 5 个标准化 EventBus 事件
## 对应 SceneEditorRuntime / PlacementSession / PlacementInstanceRegistry / PlacementEvents / PlacementInstanceMarker / PreviewFlyCamera

const EVENT_PLACEMENT_SPAWNED := "PlacementSpawnedEvent"
const EVENT_PLACEMENT_DESPAWNED := "PlacementDespawnedEvent"
const EVENT_PLACEMENT_LEVEL_CHANGED := "PlacementLevelChangedEvent"
const EVENT_PLACEMENT_CLICKED := "PlacementClickedEvent"
const EVENT_PLACEMENT_LONG_PRESSED := "PlacementLongPressedEvent"


class PlacementInstanceMarker extends Node:
	@export var instance_id: int = 0
	@export var archetype_stable_id: int = 0
	@export var archetype_type_stable_id: int = 0

	func bind(p_instance_id: int, p_arch_id: int, p_type_id: int = 0) -> void:
		instance_id = p_instance_id
		archetype_stable_id = p_arch_id
		archetype_type_stable_id = p_type_id


class PathInstanceMarker extends Node:
	@export var path_id: int = 0
	@export var path_type_keyword: int = 0

	func editor_bind(p_path_id: int, p_type_keyword: int) -> void:
		path_id = p_path_id
		path_type_keyword = p_type_keyword


class PlacementInstanceRegistry extends RefCounted:
	signal spawned(placement_id: int, node: Node)
	signal despawned(placement_id: int, node: Node)

	var _id_to_node: Dictionary = {} # int -> Node
	var _id_to_arch: Dictionary = {} # int -> int
	var _ordered_ids: Array[int] = []

	var all_placement_ids: Array[int]:
		get:
			return _ordered_ids

	func add(placement_id: int, node: Node, arch_stable_id: int) -> void:
		if placement_id <= 0:
			return
		_id_to_node[placement_id] = node
		_id_to_arch[placement_id] = arch_stable_id
		if not _ordered_ids.has(placement_id):
			_ordered_ids.append(placement_id)
		spawned.emit(placement_id, node)

	func remove(placement_id: int) -> bool:
		if not _id_to_node.has(placement_id):
			return false
		var n: Node = _id_to_node[placement_id]
		_id_to_node.erase(placement_id)
		_id_to_arch.erase(placement_id)
		_ordered_ids.erase(placement_id)
		despawned.emit(placement_id, n)
		return true

	func try_get_node(placement_id: int) -> Dictionary:
		if _id_to_node.has(placement_id):
			return {"ok": true, "node": _id_to_node[placement_id]}
		return {"ok": false, "node": null}

	func try_get_archetype_stable_id(placement_id: int) -> Dictionary:
		if _id_to_arch.has(placement_id):
			return {"ok": true, "archetype_stable_id": _id_to_arch[placement_id]}
		return {"ok": false, "archetype_stable_id": 0}

	func clear_all() -> void:
		var ids_copy := _ordered_ids.duplicate()
		for pid in ids_copy:
			remove(pid)


class SceneEditorBootstrapOptions extends RefCounted:
	var layout: GDLevelSceneRes = null
	var parent: Node = null
	var logical_scene_position_offset: Vector3 = Vector3.ZERO
	var on_instance_placed: Callable = Callable()
	var register_to_global_locator: bool = true
	var publish_events_to_bus: bool = true
	var auto_attach_click_handler: bool = true


class PlacementSession extends RefCounted:
	var layout: GDLevelSceneRes = null
	var instance_registry: PlacementInstanceRegistry = null
	var archetype_registry: GDArchetypeRes.ArchetypeRegistry = null
	var path_registry: GDPathSystem.PathRuntimeRegistry = null
	var is_disposed: bool = false

	var _options: SceneEditorBootstrapOptions = null
	var _spawned_nodes: Array[Node] = []

	func _init(
		p_options: SceneEditorBootstrapOptions,
		p_inst_reg: PlacementInstanceRegistry,
		p_arch_reg: GDArchetypeRes.ArchetypeRegistry
	) -> void:
		_options = p_options
		layout = p_options.layout
		instance_registry = p_inst_reg
		archetype_registry = p_arch_reg

		if _options.register_to_global_locator:
			var loc := GDCoreServices.get_locator()
			loc.register_service("IPlacementInstanceRegistry", instance_registry)
			loc.register_service("IArchetypeRegistry", archetype_registry)

		instance_registry.spawned.connect(_on_spawned)
		instance_registry.despawned.connect(_on_despawned)

	func track_spawned(node: Node) -> void:
		if node != null:
			_spawned_nodes.append(node)

	func attach_path_registry(p_path_reg: GDPathSystem.PathRuntimeRegistry) -> void:
		path_registry = p_path_reg
		if path_registry != null and _options.register_to_global_locator:
			GDCoreServices.get_locator().register_service("IPathRegistry", path_registry)

	func dispose() -> void:
		if is_disposed:
			return
		is_disposed = true
		if instance_registry.spawned.is_connected(_on_spawned):
			instance_registry.spawned.disconnect(_on_spawned)
		instance_registry.clear_all()
		if instance_registry.despawned.is_connected(_on_despawned):
			instance_registry.despawned.disconnect(_on_despawned)

		if path_registry != null:
			path_registry.clear_all()

		for n in _spawned_nodes:
			if n != null and is_instance_valid(n):
				if n.get_parent() != null:
					n.get_parent().remove_child(n)
				n.free()
		_spawned_nodes.clear()

		if _options.register_to_global_locator:
			var loc := GDCoreServices.get_locator()
			loc.unregister_service("IPlacementInstanceRegistry")
			loc.unregister_service("IArchetypeRegistry")
			if path_registry != null:
				loc.unregister_service("IPathRegistry")

	func _on_spawned(placement_id: int, node: Node) -> void:
		if not _options.publish_events_to_bus:
			return
		var arch_res := instance_registry.try_get_archetype_stable_id(placement_id)
		GDCoreServices.get_event_bus().publish(EVENT_PLACEMENT_SPAWNED, {
			"placement_id": placement_id,
			"archetype_stable_id": int(arch_res.get("archetype_stable_id", 0)),
			"node": node,
		})

	func _on_despawned(placement_id: int, _node: Node) -> void:
		if not _options.publish_events_to_bus:
			return
		GDCoreServices.get_event_bus().publish(EVENT_PLACEMENT_DESPAWNED, {
			"placement_id": placement_id,
		})


static func find_placement_root(parent: Node, instance_id: int) -> Node:
	if parent == null or instance_id <= 0:
		return null
	return _find_placement_root(parent, instance_id)


static func _find_placement_root(node: Node, instance_id: int) -> Node:
	if int(node.get_meta("gdesigner_placement_id", 0)) == instance_id:
		return node
	for child in node.get_children():
		var found := _find_placement_root(child, instance_id)
		if found != null:
			return found
	return null


static func load_session(options: SceneEditorBootstrapOptions) -> PlacementSession:
	if options == null or options.layout == null or options.parent == null:
		GDGameLogger.log_error_p("[SceneEditorRuntime] LoadSession 参数缺失：Layout 与 Parent 必填。")
		return null

	var arch_reg := GDArchetypeRes.ArchetypeRegistry.new(options.layout.archetypes)
	var inst_reg := PlacementInstanceRegistry.new()
	var session := PlacementSession.new(options, inst_reg, arch_reg)

	for inst in options.layout.placements:
		if inst == null:
			continue
		var arch := arch_reg.find_by_stable_id(inst.archetype_stable_id)
		# 编辑器拖进场景的节点已经在树里。这里采纳它们，避免运行时再生成一份。
		var spawned: Node = find_placement_root(options.parent, inst.instance_id)
		var created := spawned == null
		if created:
			var spawned_3d: Node3D = null
			if arch != null:
				var ps := arch.editor_resolve_manufactured_prefab()
				if ps != null:
					var raw := ps.instantiate()
					if raw is Node3D:
						spawned_3d = raw
					else:
						spawned_3d = Node3D.new()
						spawned_3d.add_child(raw)
			if spawned_3d == null:
				spawned_3d = GDEntityNode.new()
			spawned = spawned_3d
			spawned.name = GDPlacementData.PlacementInstanceIdRangeLogic.resolve_display_name(inst, arch)
			options.parent.add_child(spawned)

		if spawned is Node3D:
			var body := spawned as Node3D
			body.position = inst.position + options.logical_scene_position_offset
			body.rotation_degrees = inst.euler_angles
			body.scale = inst.scale
		elif spawned is Node2D:
			var flat := spawned as Node2D
			var placed: Vector3 = inst.position + options.logical_scene_position_offset
			flat.position = Vector2(placed.x, placed.y)
			flat.rotation_degrees = inst.euler_angles.z
			flat.scale = Vector2(inst.scale.x, inst.scale.y)

		var marker: PlacementInstanceMarker = null
		for child in spawned.get_children():
			if child is PlacementInstanceMarker:
				marker = child
				break
		if marker == null:
			marker = PlacementInstanceMarker.new()
			marker.name = "PlacementInstanceMarker"
			var type_id := arch.archetype_type_stable_id if arch != null else 0
			marker.bind(inst.instance_id, inst.archetype_stable_id, type_id)
			spawned.add_child(marker)

		# 应用自定义属性覆盖到 AtomVarTag
		GDEntityAtomSystem.AtomVarTagRegistry.apply_overrides_to_node(spawned, inst.attribute_overrides)

		# 绑定 InteractableAtom 点击/长按事件到 EventBus
		if options.auto_attach_click_handler and not bool(spawned.get_meta("gdesigner_click_wired", false)):
			_wire_click_handler(spawned, marker, options.publish_events_to_bus)
			spawned.set_meta("gdesigner_click_wired", true)

		inst_reg.add(inst.instance_id, spawned, inst.archetype_stable_id)
		if created:
			session.track_spawned(spawned)

		if options.on_instance_placed.is_valid():
			options.on_instance_placed.call({
				"instance_id": inst.instance_id,
				"archetype_stable_id": inst.archetype_stable_id,
				"node": spawned,
				"source": inst,
				"session": session,
			})

	# 加载路径注册表
	var path_reg := GDPathSystem.PathRuntimeRegistry.new()
	for p in options.layout.paths:
		if p != null:
			path_reg.add(GDPathSystem.RuntimePath.new(p))
	session.attach_path_registry(path_reg)

	return session

static func _wire_click_handler(root: Node, marker: PlacementInstanceMarker, publish: bool) -> void:
	for ch in root.get_children():
		if ch is GDEntityAtomSystem.InteractableAtom:
			var ia := ch as GDEntityAtomSystem.InteractableAtom
			ia.on_clicked.connect(func() -> void:
				if publish:
					GDCoreServices.get_event_bus().publish(EVENT_PLACEMENT_CLICKED, {
						"placement_id": marker.instance_id,
						"archetype_stable_id": marker.archetype_stable_id,
						"archetype_type_stable_id": marker.archetype_type_stable_id,
						"node": root,
					})
			)
			ia.on_long_pressed.connect(func() -> void:
				if publish:
					GDCoreServices.get_event_bus().publish(EVENT_PLACEMENT_LONG_PRESSED, {
						"placement_id": marker.instance_id,
						"node": root,
					})
			)
