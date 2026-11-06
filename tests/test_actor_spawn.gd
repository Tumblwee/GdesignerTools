extends SceneTree

var passed := 0
var failed := 0
var fixture := "user://actor_spawn_%d" % Time.get_ticks_usec()
var capture := false

class LevelPage extends GDLevelPage:
	func can_edit_scene() -> bool:
		return layout != null

func _initialize() -> void:
	GDLevelLibraries.storage_root = fixture.path_join("libraries")
	capture = OS.get_cmdline_user_args().has("--capture")
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func frames(count := 2) -> void:
	for i in range(count):
		await process_frame

func _run() -> void:
	root.size = Vector2i(1000, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(fixture)
	var fox := _make_tool_actor()
	var actor_2d := _make_2d()
	var runtime_actor := _make_runtime_actor()
	var library := GDActorLibraryRes.new()
	library.display_name = "3D 演员库"
	library.editor_add_archetype(fox)
	library.editor_add_archetype(runtime_actor)
	var flat_library := GDActorLibraryRes.new()
	flat_library.editor_add_archetype(actor_2d)
	check(GDDocument.new(library).save(fixture.path_join("Actors3D.tres")) == OK and GDDocument.new(flat_library).save(fixture.path_join("Actors2D.tres")) == OK, "actor libraries save")
	var actor_page := GDActorPage.new()
	root.add_child(actor_page)
	actor_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	actor_page.set_library(library)
	actor_page.select_archetype(fox)
	await frames(3)
	var preview := actor_page._preview
	check(not preview._is_2d and GDArchetypePreviewPanel._bounds_of(preview._stage, Transform3D.IDENTITY).size.length() > 1.0, "tool-generated meshes appear in the central 3D preview")
	check(preview._stage.get_child(0).get_node_or_null("Visual") != null, "preview retains tool initialization")
	check(preview._stage.get_child(0).process_mode == Node.PROCESS_MODE_DISABLED, "preview disables ongoing gameplay processing")
	await _capture(preview, "actor-preview-3d.png")
	actor_page.set_library(flat_library)
	actor_page.select_archetype(actor_2d)
	await frames(3)
	check(preview._is_2d and preview._stage_2d.get_child_count() == 1 and preview._stage.get_child_count() == 0, "selecting a 2D actor switches rendering modes and clears the 3D stage")
	var bounds := GDPreviewScene.bounds_2d(preview._stage_2d)
	check((preview._viewport.canvas_transform * bounds.get_center()).distance_to(Vector2(preview._viewport.size) * 0.5) < 1.0, "2D preview centers transformed sprite bounds")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var zoom := preview._zoom_2d
	preview._gui_input(wheel)
	check(preview._zoom_2d > zoom, "2D preview supports wheel zoom")
	await _capture(preview, "actor-preview-2d.png")
	actor_page.set_library(library)
	actor_page.select_archetype(runtime_actor)
	await frames()
	check(not preview._stage.get_child(0).has_meta("runtime_ready"), "ordinary game scripts do not execute in previews")
	var missing := GDActorArchetypeRes.new()
	preview.show_archetype(missing)
	check(preview._message.visible, "missing prefab gives a visible explanation")
	fox.preview_prefab_address = "missing-preview-address"
	preview.show_archetype(fox)
	check(preview._stage.get_child_count() == 1, "invalid preview prefab falls back to the actor's instance prefab")
	fox.preview_prefab_address = ""
	actor_page.hide()

	var page := LevelPage.new()
	root.add_child(page)
	var layout := GDLevelSceneRes.new()
	page.set_layout(layout)
	actor_page.level_provider = page.get_current_layout
	var original_size := layout.archetypes.size()
	var library_steps := page.library_doc._cursor
	var payload: Variant = actor_page._list.drag_provider.call(fox)
	check(GDLevelSceneDrop.is_actor_payload(payload) and payload.actor_reference.resolve() == fox, "actor-list drag creates a spawn-point payload with the chosen actor")
	GDLevelSceneDrop.cancel()
	check(layout.placements.is_empty() and layout.archetypes.size() == original_size, "canceling actor drag leaves the level and prototype library untouched")
	var host := Node3D.new()
	host.name = "SpawnScene"
	root.add_child(host)
	var result := GDLevelSceneDrop.place_archetype(layout, GDActorSpawnRuntime.archetype(), Vector3(4, 0, 7), host, payload.actor_reference)
	check(result.ok and result.node is GDActorSpawnPoint3D and result.node.position == Vector3(4, 0, 7), "3D drop creates a spawn point at the target position")
	var instance: GDPlacementData.PlacementInstance = page.find_placement(result.instance_id)
	check(instance.archetype_stable_id == GDActorSpawnRuntime.ARCHETYPE_ID and instance.actor_reference.library == library, "placement stores plugin prototype ID and actor-library reference")
	check(layout.archetypes.size() == original_size and page.library_doc._cursor == library_steps, "built-in spawn prototype does not change the user library or its history")
	check(page.doc.undo_label == "摆放原型", "actor placement participates in the level undo history")
	var editor_point: GDActorSpawnPoint3D = result.node
	check(editor_point.spawned_actor != null and editor_point.spawned_actor.owner == null and editor_point.has_node("SpawnPointMarker"), "editor spawn point shows actor and marker without baking preview children into the scene")
	page.doc.undo()
	GDLevelSceneDrop.reconcile_scene(layout, host)
	check(layout.placements.is_empty() and host.get_child_count() == 0, "undo removes both spawn data and scene node")
	page.doc.redo()
	GDLevelSceneDrop.reconcile_scene(layout, host)
	check(layout.placements.size() == 1 and host.get_child_count() == 1, "redo restores the spawn point")
	page.select_placement(result.instance_id)
	page.commands.duplicate_item(GDLevelPage.Kind.PLACEMENT, result.instance_id)
	var copy: GDPlacementData.PlacementInstance = layout.placements[-1]
	check(copy.actor_reference.resolve() == fox and copy.instance_id != result.instance_id, "duplicating a spawn point preserves its actor reference")
	check(copy.actor_reference != instance.actor_reference, "duplicated spawn points own independent actor selections")
	fox.display_name = "共享演员的新名称"
	page.doc.undo()
	check(fox.display_name == "共享演员的新名称", "level undo never reverts shared actor-library edits")
	var before := layout.placements.size()
	var mismatch := GDLevelSceneDrop.place_archetype(layout, GDActorSpawnRuntime.archetype(), Vector3.ZERO, host, GDActorReferenceRes.from_actor(actor_2d, flat_library))
	check(not mismatch.ok and layout.placements.size() == before, "2D actor dropped in a 3D scene is rejected without partial data")
	var current_point: GDActorSpawnPoint3D = GDLevelSceneDrop.find_placed_node(result.instance_id, layout)
	current_point.actor_reference.stable_id = runtime_actor.stable_id
	current_point.initial_level = 5
	check(GDLevelSceneDrop.pull_transforms_from_scene(layout), "scene inspector actor and level changes can be pulled into the layout")
	check(page.find_placement(result.instance_id).actor_reference.resolve() == runtime_actor and page.find_placement(result.instance_id).initial_level == 5, "pulled spawn settings preserve the selected actor")
	page.doc.commit("修改生成点演员")
	page.doc.undo()
	GDLevelSceneDrop.reconcile_scene(layout, host)
	check(page.find_placement(result.instance_id).actor_reference.resolve() == fox, "undo restores the previous spawn actor")
	check(page._save_as(page.doc, fixture.path_join("Level.tres")) == OK, "saving a level saves its referenced actor library")
	var reloaded := ResourceLoader.load(fixture.path_join("Level.tres"), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as GDLevelSceneRes
	check(reloaded.placements[0].actor_reference.resolve().display_name == fox.display_name and reloaded.placements[0].actor_reference.library.resource_path == library.resource_path, "actor-library reference and latest edits survive disk reload")
	var packed := PackedScene.new()
	check(packed.pack(host) == OK and ResourceSaver.save(packed, fixture.path_join("SpawnScene.tscn")) == OK, "spawn-point scene saves")
	var stored := FileAccess.get_file_as_string(fixture.path_join("SpawnScene.tscn"))
	check(not stored.contains('name="Visual"') and not stored.contains('name="SpawnPointMarker"'), "saved scene contains no transient actor meshes or preview marker")
	var saved_scene := (load(fixture.path_join("SpawnScene.tscn")) as PackedScene).instantiate()
	root.add_child(saved_scene)
	check(saved_scene.get_child(0) is GDActorSpawnPoint3D and saved_scene.get_child(0).spawned_actor != null and not saved_scene.get_child(0).has_node("SpawnPointMarker"), "saved editor scene produces a real actor when run")
	saved_scene.free()
	host.free()
	page.free()
	actor_page.free()
	var flat_layout := GDLevelSceneRes.new()
	var flat_host := Node2D.new()
	root.add_child(flat_host)
	var flat_result := GDLevelSceneDrop.place_archetype(flat_layout, GDActorSpawnRuntime.archetype(), Vector3(80, 120, 0), flat_host, GDActorReferenceRes.from_actor(actor_2d, flat_library))
	check(flat_result.ok and flat_result.node is GDActorSpawnPoint2D and flat_result.node.position == Vector2(80, 120), "2D actor drop creates a 2D spawn point at the cursor")
	check(flat_result.node.spawned_actor is Node2D and flat_result.node.actor_reference.resolve() == actor_2d, "same actor IDs from different libraries resolve to their own actor")
	flat_host.free()
	_test_runtime(runtime_actor, library, actor_2d, flat_library)
	GDLevelSceneDrop.shutdown()
	GDCoreServices.shutdown_for_tests()
	await frames()
	print("TOTAL PASSED: %d  FAILED: %d" % [passed, failed])
	quit(failed)

func _make_tool_actor() -> GDActorArchetypeRes:
	var script_path := fixture.path_join("tool_actor.gd")
	FileAccess.open(script_path, FileAccess.WRITE).store_string('@tool\nextends Node3D\nfunc _ready() -> void:\n\tvar visual := MeshInstance3D.new()\n\tvisual.name = "Visual"\n\tvisual.mesh = BoxMesh.new()\n\tadd_child(visual)\n')
	var node := Node3D.new()
	node.set_script(load(script_path))
	var packed := PackedScene.new()
	packed.pack(node)
	var scene_path := fixture.path_join("ToolActor.tscn")
	ResourceSaver.save(packed, scene_path)
	node.free()
	GDArchetypeRes.register_prefab_address("SpawnTestTool3D", scene_path)
	var actor := GDActorArchetypeRes.new()
	actor.editor_init_with_addresses(1000, "工具脚本演员", "SpawnTestTool3D", "")
	return actor

func _make_2d() -> GDActorArchetypeRes:
	var node := Node2D.new()
	var sprite := Sprite2D.new()
	var texture := GradientTexture2D.new()
	texture.width = 64
	texture.height = 96
	texture.gradient = Gradient.new()
	texture.gradient.colors = PackedColorArray([Color.CORNFLOWER_BLUE, Color.MEDIUM_PURPLE])
	sprite.texture = texture
	sprite.position = Vector2(140, -90)
	sprite.scale = Vector2(1.5, 0.8)
	node.add_child(sprite)
	sprite.owner = node
	var packed := PackedScene.new()
	packed.pack(node)
	ResourceSaver.save(packed, fixture.path_join("Actor2D.tscn"))
	node.free()
	GDArchetypeRes.register_prefab_address("SpawnTest2D", fixture.path_join("Actor2D.tscn"))
	var actor := GDActorArchetypeRes.new()
	actor.editor_init_with_addresses(1000, "2D 演员", "SpawnTest2D", "")
	return actor

func _make_runtime_actor() -> GDActorArchetypeRes:
	var script_path := fixture.path_join("runtime_actor.gd")
	FileAccess.open(script_path, FileAccess.WRITE).store_string('extends Node3D\nfunc _ready() -> void:\n\tset_meta("runtime_ready", true)\n\tset_meta("ready_position", global_position)\n')
	var node := Node3D.new()
	node.set_script(load(script_path))
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	node.add_child(mesh)
	mesh.owner = node
	var packed := PackedScene.new()
	packed.pack(node)
	ResourceSaver.save(packed, fixture.path_join("RuntimeActor.tscn"))
	node.free()
	GDArchetypeRes.register_prefab_address("SpawnTestRuntime3D", fixture.path_join("RuntimeActor.tscn"))
	var actor := GDActorArchetypeRes.new()
	actor.editor_init_with_addresses(1001, "运行时演员", "SpawnTestRuntime3D", "")
	return actor

func _test_runtime(actor: GDArchetypeRes, library: GDActorLibraryRes, flat_actor: GDArchetypeRes, flat_library: GDActorLibraryRes) -> void:
	for flat in [false, true]:
		var parent: Node = Node2D.new() if flat else Node3D.new()
		root.add_child(parent)
		var layout := GDLevelSceneRes.new()
		var id := layout.editor_add_placement(GDActorSpawnRuntime.ARCHETYPE_ID, Vector3(20, 30, 0), Vector3.ZERO, Vector3.ONE, 3)
		var inst: GDPlacementData.PlacementInstance = layout.placements[0]
		inst.actor_reference = GDActorReferenceRes.from_actor(flat_actor if flat else actor, flat_library if flat else library)
		var options := GDSceneEditorRuntime.SceneEditorBootstrapOptions.new()
		options.layout = layout
		options.parent = parent
		options.register_to_global_locator = false
		options.publish_events_to_bus = false
		var session := GDSceneEditorRuntime.load_session(options)
		var point: Node = session.instance_registry.try_get_node(id).node
		check((point is GDActorSpawnPoint2D if flat else point is GDActorSpawnPoint3D) and point.spawned_actor != null, "runtime loads the appropriate %s spawn point and actor" % ("2D" if flat else "3D"))
		if not flat:
			check(point.spawned_actor.get_meta("runtime_ready", false) and point.spawned_actor.get_meta("ready_position") == Vector3(20, 30, 0), "runtime gameplay script starts at the placement position")
		var spawned: Node = point.spawned_actor
		point.spawn_actor()
		check(point.spawned_actor == spawned, "repeated spawn calls do not duplicate the actor")
		var adopted := GDSceneEditorRuntime.load_session(options)
		check(adopted.instance_registry.try_get_node(id).node == point and point.spawned_actor == spawned, "runtime adopts existing spawn points without generating duplicate actors")
		adopted.dispose()
		session.dispose()
		check(parent.get_child_count() == 0, "disposing the runtime session removes the spawn point and its actor")
		inst.actor_spawn_on_ready = false
		session = GDSceneEditorRuntime.load_session(options)
		point = session.instance_registry.try_get_node(id).node
		check(point.spawned_actor == null and point.spawn_actor() != null, "manual spawn mode waits for an explicit spawn_actor call")
		session.dispose()
		parent.free()

func _capture(preview: GDArchetypePreviewPanel, filename: String) -> void:
	if not capture:
		return
	preview._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := preview._viewport.get_texture().get_image()
	check(image != null and not image.is_empty(), "preview renders pixels")
	if image != null:
		image.save_png("res://.runtime/" + filename)
