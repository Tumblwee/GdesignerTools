@tool
class_name GDActorSpawnRuntime
extends RefCounted

## 1..999 为插件保留 ID；项目原型从 1000 起分配。内置原型不写入用户库。
const ARCHETYPE_ID := 1
const ARCHETYPE_PATH := "res://addons/gdesigner_tools/actor_editor/builtin/ActorSpawnPoint.tres"
const SCENE_3D := "res://addons/gdesigner_tools/actor_editor/builtin/ActorSpawnPoint3D.tscn"
const SCENE_2D := "res://addons/gdesigner_tools/actor_editor/builtin/ActorSpawnPoint2D.tscn"

static func archetype() -> GDArchetypeRes:
	return load(ARCHETYPE_PATH) as GDArchetypeRes

static func is_spawn(inst: GDPlacementData.PlacementInstance) -> bool:
	return inst != null and inst.archetype_stable_id == ARCHETYPE_ID

static func create_point(inst: GDPlacementData.PlacementInstance, as_2d: bool, preview: bool) -> Node:
	var packed := load(SCENE_2D if as_2d else SCENE_3D) as PackedScene
	var point := packed.instantiate()
	point.actor_reference = inst.actor_reference.duplicate() if inst.actor_reference != null else null
	point.initial_level = inst.initial_level
	point.spawn_on_ready = inst.actor_spawn_on_ready
	point.preview_only = preview
	return point

static func is_point(node: Node) -> bool:
	return node is GDActorSpawnPoint3D or node is GDActorSpawnPoint2D

static func validate_dimension(actor: GDArchetypeRes, as_2d: bool) -> String:
	if actor == null:
		return "请选择演员。"
	var packed := actor.editor_resolve_manufactured_prefab()
	if packed == null:
		return "演员的实例 Prefab 不存在，请先在演员页配置。"
	var instance := packed.instantiate()
	var compatible := instance is Node2D if as_2d else instance is Node3D
	instance.free()
	return "" if compatible else "演员 Prefab 与当前场景维度不匹配，请使用 %s 演员。" % ("2D" if as_2d else "3D")

static func refresh(point: Node) -> void:
	clear(point)
	if Engine.is_editor_hint() or point.preview_only:
		_add_marker(point)
		spawn(point, true)
	elif point.spawn_on_ready:
		spawn(point, false)

static func clear(point: Node) -> void:
	for child in point.get_children():
		if child.get_meta(&"gd_spawn_visual", false):
			point.remove_child(child)
			child.queue_free()
	point.spawned_actor = null

static func spawn(point: Node, preview: bool = false) -> Node:
	if is_instance_valid(point.spawned_actor):
		return point.spawned_actor
	var actor: GDArchetypeRes = point.actor_reference.resolve() if point.actor_reference != null else null
	if actor == null:
		return null
	var packed := actor.editor_get_catalog_thumbnail_prefab() if preview else actor.editor_resolve_manufactured_prefab()
	if packed == null:
		return null
	var instance := packed.instantiate()
	if (point is Node2D and not instance is Node2D) or (point is Node3D and not instance is Node3D):
		instance.free()
		return null
	instance.name = "Actor"
	instance.set_meta(&"gd_spawn_visual", true)
	instance.set_meta(&"gdesigner_actor_archetype", actor)
	instance.set_meta(&"gdesigner_actor_level", point.initial_level)
	if preview:
		GDPreviewScene.prepare(instance)
	point.add_child(instance)
	if preview:
		GDPreviewScene.freeze(instance)
	var overrides := GDPlacementData.PlacementInstanceIdRangeLogic.create_default_overrides(actor)
	GDEntityAtomSystem.AtomVarTagRegistry.apply_overrides_to_node(instance, overrides)
	point.spawned_actor = instance
	return instance

static func _add_marker(point: Node) -> void:
	var marker: Node
	if point is Node2D:
		var ring := Line2D.new()
		ring.width = 2.0
		ring.default_color = Color(0.2, 0.85, 1.0)
		ring.closed = true
		for i in range(32):
			ring.add_point(Vector2.from_angle(TAU * i / 32.0) * 28.0)
		marker = ring
	else:
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.48
		mesh.outer_radius = 0.52
		ring.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.2, 0.85, 1.0)
		ring.material_override = material
		ring.position.y = 0.025
		marker = ring
	marker.name = "SpawnPointMarker"
	marker.set_meta(&"gd_spawn_visual", true)
	point.add_child(marker)
