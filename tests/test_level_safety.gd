extends SceneTree

const SAVE_PATH := "user://gdesigner_level_safety.tres"
const PREFAB_PATH := "user://gdesigner_level_safety_2d.tscn"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	GDLevelLibraries.storage_root = "user://test_level_safety_libraries_%d" % Time.get_ticks_usec()
	_run.call_deferred()


func _run() -> void:
	_test_scene_binding()
	_test_binding_undo()
	_test_layout_isolation()
	_test_duplicate_identity()
	_test_scene_capture()
	_test_save_all()
	_test_runtime_2d()
	_test_legacy_adoption()
	GDLevelSceneDrop.shutdown()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFAB_PATH))
	print("TOTAL PASSED: %d  FAILED: %d" % [_passed, _failed])
	quit(_failed)


func _layout_at(position: Vector3) -> GDLevelSceneRes:
	var layout := GDLevelSceneRes.new()
	var arch := GDLevelArchetypeRes.new()
	arch.editor_init_with_addresses(1000, "Block", "", "")
	layout.editor_add_archetype(arch)
	layout.editor_add_placement(arch.stable_id, position, Vector3.ZERO, Vector3.ONE, 1)
	return layout


func _test_scene_binding() -> void:
	var layout := _layout_at(Vector3.ZERO)
	var scene_a := Node3D.new()
	var scene_b := Node3D.new()
	scene_a.scene_file_path = "res://safety_a.tscn"
	scene_b.scene_file_path = "res://safety_b.tscn"
	_check(not GDLevelSceneDrop.is_bound_to_scene(layout, scene_a), "an unbound layout cannot access a saved scene")
	_check(GDLevelSceneDrop.bind_layout_to_scene(layout, scene_a), "explicit binding records a saved scene")
	_check(not layout.layout_id.is_empty() and layout.scene_path == scene_a.scene_file_path, "binding assigns persistent layout identity")
	_check(GDLevelSceneDrop.is_bound_to_scene(layout, scene_a) and not GDLevelSceneDrop.is_bound_to_scene(layout, scene_b), "binding authorizes only its own scene")
	_check(not GDLevelSceneDrop.bind_layout_to_scene(layout, scene_b), "opening another scene does not rebind the layout")
	scene_a.free()
	scene_b.free()


func _test_layout_isolation() -> void:
	var layout_a := _layout_at(Vector3(1, 0, 1))
	var layout_b := _layout_at(Vector3(5, 0, 5))
	var host_a := Node3D.new()
	var host_b := Node3D.new()
	root.add_child(host_a)
	root.add_child(host_b)
	var id: int = layout_a.placements[0].instance_id
	var node_a := GDLevelSceneDrop.spawn_into(layout_a, id, host_a) as Node3D
	GDLevelSceneDrop.erase_placed(null, id)
	GDLevelSceneDrop.respawn(null, id)
	GDLevelSceneDrop.reconcile_scene(null, host_a)
	_check(is_instance_valid(node_a) and layout_a.placements.size() == 1, "null-layout mutations leave nodes and models untouched")
	_check(not GDLevelSceneDrop.pull_transforms_from_scene(layout_b) and layout_b.placements[0].position == Vector3(5, 0, 5), "layout B cannot pull A's identically numbered placement")
	var node_b := GDLevelSceneDrop.spawn_into(layout_b, id, host_b) as Node3D
	_check(GDLevelSceneDrop.find_placed_node(id) == null, "unscoped lookup rejects ambiguous instance IDs")
	GDLevelSceneDrop.apply_transform(id, Vector3(8, 0, 8), Vector3.ZERO, Vector3.ONE, layout_b)
	_check(node_a.position == Vector3(1, 0, 1) and node_b.position == Vector3(8, 0, 8), "layout-scoped transforms affect the correct scene node")
	GDLevelSceneDrop.reconcile_scene(layout_b, host_a)
	_check(is_instance_valid(node_a) and node_a.position == Vector3(1, 0, 1), "reconcile refuses a parent owned by another layout")
	GDLevelSceneDrop.erase_placed(layout_b, id)
	_check(is_instance_valid(node_a) and host_b.get_child_count() == 0, "deleting B preserves A's identically numbered node")
	GDLevelSceneDrop.scene_changed()
	_check(GDLevelSceneDrop.find_placed_node(id, layout_a) == node_a, "clearing drag caches retains explicit layout ownership")
	host_a.free()
	host_b.free()


func _test_binding_undo() -> void:
	var scene := Node3D.new()
	scene.scene_file_path = "res://binding_undo_safety.tscn"
	root.add_child(scene)
	GDLevelSceneDrop.placement_parent(scene)
	var layout := _layout_at(Vector3.ZERO)
	var page := GDLevelPage.new()
	root.add_child(page)
	page.set_layout(layout)
	var identity := layout.layout_id
	_check(not identity.is_empty() and page.doc._cursor == 0, "a page initializes stable identity before taking its initial history snapshot")
	GDLevelSceneDrop.bind_layout_to_scene(layout, scene)
	page.doc.undo()
	_check(layout.scene_path.is_empty() and layout.layout_id == identity, "undoing binding preserves layout identity")
	_check(GDLevelSceneDrop.bind_layout_to_scene(layout, scene), "an undone binding can be confirmed again")
	scene.free()
	page.free()


func _test_duplicate_identity() -> void:
	var original := _layout_at(Vector3.ZERO)
	var parent := Node3D.new()
	root.add_child(parent)
	var id: int = original.placements[0].instance_id
	GDLevelSceneDrop.spawn_into(original, id, parent)
	var copy := original.duplicate(true) as GDLevelSceneRes
	var copy_parent := Node3D.new()
	root.add_child(copy_parent)
	_check(GDLevelSceneDrop.spawn_into(copy, id, copy_parent) == null and copy_parent.get_child_count() == 0, "copied resources with duplicate layout identity cannot claim scene nodes")
	GDLevelSceneDrop.scene_changed()
	_check(not GDLevelSceneDrop.register_layout(copy), "scene switches preserve duplicate-identity protection")
	parent.free()
	copy_parent.free()


func _test_scene_capture() -> void:
	var scene_a := Node3D.new()
	scene_a.scene_file_path = "res://capture_a.tscn"
	root.add_child(scene_a)
	var layout := _layout_at(Vector3.ZERO)
	var page := GDLevelPage.new()
	root.add_child(page)
	page.set_layout(layout)
	GDLevelSceneDrop.bind_layout_to_scene(layout, scene_a)
	_check(page.doc.dirty and page.doc.undo_label == "绑定关卡场景", "binding participates in document history")
	var host := GDLevelSceneDrop.placement_parent(scene_a)
	var node := GDLevelSceneDrop.spawn_into(layout, layout.placements[0].instance_id, host) as Node3D
	node.position = Vector3(13, 0, 17)
	page.capture_scene(scene_a)
	_check(layout.placements[0].position == Vector3(13, 0, 17) and page.doc.undo_label == "同步场景位姿", "scene switching can capture the previous bound scene")
	var foreign := Node3D.new()
	foreign.scene_file_path = "res://capture_b.tscn"
	_check(not GDLevelSceneDrop.pull_transforms_from_scene(layout, foreign), "an explicit mismatched scene is rejected")
	foreign.free()
	scene_a.free()
	page.free()


func _test_save_all() -> void:
	var layout := _layout_at(Vector3(2, 0, 2))
	layout.layout_id = "save_all_safety"
	var page := GDLevelPage.new()
	root.add_child(page)
	page.set_layout(layout)
	_check(page.doc.save(SAVE_PATH) == OK, "the initial layout saves")
	var host := Node3D.new()
	root.add_child(host)
	var node := GDLevelSceneDrop.spawn_into(layout, layout.placements[0].instance_id, host) as Node3D
	node.position = Vector3(9, 0, 9)
	_check(not page.doc.dirty, "viewport-only moves start with a clean document")
	page.save_all()
	var disk := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GDLevelSceneRes
	_check(disk != null and disk.placements[0].position == Vector3(9, 0, 9) and not page.doc.dirty, "Save All synchronizes viewport moves before filtering clean documents")
	_check(disk != null and GDLevelSceneDrop.register_layout(disk), "reloading the same saved asset keeps its layout identity usable")
	host.free()
	page.free()


func _test_runtime_2d() -> void:
	var prefab := Node2D.new()
	prefab.name = "Safety2D"
	var packed := PackedScene.new()
	packed.pack(prefab)
	_check(ResourceSaver.save(packed, PREFAB_PATH) == OK, "the 2D fixture saves")
	prefab.free()
	GDArchetypeRes.register_prefab_address("Entity_LevelSafety2D", PREFAB_PATH)
	var layout := _layout_at(Vector3(30, 40, 0))
	layout.archetypes[0].manufactured_prefab_address = "Entity_LevelSafety2D"
	var inst: GDPlacementData.PlacementInstance = layout.placements[0]
	layout.editor_replace_placement(inst.instance_id, inst.with_transform(inst.position, Vector3(0, 0, 45), Vector3(2, 3, 1)))
	var parent := Node2D.new()
	root.add_child(parent)
	var opts := GDSceneEditorRuntime.SceneEditorBootstrapOptions.new()
	opts.layout = layout
	opts.parent = parent
	opts.logical_scene_position_offset = Vector3(2, 3, 0)
	opts.register_to_global_locator = false
	opts.publish_events_to_bus = false
	opts.auto_attach_click_handler = false
	var session := GDSceneEditorRuntime.load_session(opts)
	var spawned := parent.get_child(0) as Node2D
	_check(spawned != null and spawned.position == Vector2(32, 43) and is_equal_approx(spawned.rotation_degrees, 45) and spawned.scale == Vector2(2, 3), "2D runtime assembly applies position, rotation, scale and offset to a Node2D root")
	_check(str(spawned.get_meta(GDSceneEditorRuntime.PLACEMENT_LAYOUT_META)) == GDSceneEditorRuntime.layout_identity(layout), "runtime nodes carry layout ownership")
	session.dispose()
	_check(parent.get_child_count() == 0, "disposing the session frees runtime-created 2D nodes")
	parent.free()


func _test_legacy_adoption() -> void:
	var parent := Node3D.new()
	parent.scene_file_path = "res://legacy_safety.tscn"
	var layout := _layout_at(Vector3.ZERO)
	var legacy := Node3D.new()
	legacy.set_meta(GDSceneEditorRuntime.PLACEMENT_ID_META, layout.placements[0].instance_id)
	parent.add_child(legacy)
	_check(GDSceneEditorRuntime.find_placement_root(parent, layout.placements[0].instance_id, layout) == null, "unbound layouts cannot adopt legacy ID-only nodes")
	layout.scene_path = parent.scene_file_path
	_check(GDSceneEditorRuntime.find_placement_root(parent, layout.placements[0].instance_id, layout) == legacy, "legacy nodes remain adoptable in the bound scene")
	legacy.set_meta(GDSceneEditorRuntime.PLACEMENT_LAYOUT_META, "another_layout")
	_check(GDSceneEditorRuntime.find_placement_root(parent, layout.placements[0].instance_id, layout) == null, "matching scene paths do not override explicit node ownership")
	parent.free()


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: %s" % label)
