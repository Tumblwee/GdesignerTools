extends SceneTree

## Run in an isolated project: this suite also exercises default editor scene creation.
var _passed := 0
var _failed := 0
var _fixture_root := "user://gdesigner_level_workflow_%d" % Time.get_ticks_usec()
var _files: Array[String] = []
var _directories: Array[String] = []


func _initialize() -> void:
	GDLevelLibraries.storage_root = "user://test_level_workflow_libraries_%d" % Time.get_ticks_usec()
	_run.call_deferred()


func _run() -> void:
	_make_directory(_fixture_root)
	_test_edit_scene()
	_test_asset_picker()
	_test_page_requires_actual_scene()
	GDLevelSceneDrop.shutdown()
	for path in _files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_directories.reverse()
	for path in _directories:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("TOTAL PASSED: %d  FAILED: %d" % [_passed, _failed])
	quit(_failed)


func _test_edit_scene() -> void:
	_check(not GDLevelEditScene.ensure_scene(null).ok, "missing level cannot create an edit scene")
	var layout := GDLevelSceneRes.new()
	layout.resource_name = "WorkflowLevel"
	layout.scene_path = _fixture_root.path_join("Editor_Workflow.tscn")
	layout.logic_scene_path = _fixture_root.path_join("RuntimeLogic.tscn")
	layout.art_scene_path = _fixture_root.path_join("RuntimeArt.tscn")
	_save_scene(Node3D.new(), layout.logic_scene_path)
	_save_scene(Node3D.new(), layout.art_scene_path)
	var runtime_before := FileAccess.get_file_as_string(layout.logic_scene_path)
	var art_before := FileAccess.get_file_as_string(layout.art_scene_path)
	var result := GDLevelEditScene.ensure_scene(layout)
	_check(result.ok and result.created and result.path == layout.scene_path, "level gets its own editor scene")
	if not result.ok:
		return
	_files.append(layout.scene_path)
	var editor_scene := (ResourceLoader.load(layout.scene_path) as PackedScene).instantiate()
	_check(editor_scene is Node3D and editor_scene.has_node("Placements"), "editor scene contains a 3D placements container")
	_check(str(editor_scene.get_meta(GDLevelEditScene.META_EDIT_LAYOUT, "")) == GDSceneEditorRuntime.layout_identity(layout), "editor scene is marked with the level identity")
	_check(GDLevelSceneDrop.is_bound_to_scene(layout, editor_scene), "new editor scene authorizes its own level")
	var runtime_scene := (ResourceLoader.load(layout.logic_scene_path) as PackedScene).instantiate()
	_check(not GDLevelSceneDrop.is_bound_to_scene(layout, runtime_scene), "runtime scene never grants edit access")
	result = GDLevelEditScene.ensure_scene(layout)
	_check(result.ok and not result.created and not result.binding_changed, "reopening a level reuses its editor scene")
	_check(FileAccess.get_file_as_string(layout.logic_scene_path) == runtime_before and FileAccess.get_file_as_string(layout.art_scene_path) == art_before, "creating and reopening an editor scene preserves both runtime files")
	var other := GDLevelSceneRes.new()
	other.scene_path = layout.scene_path
	_check(not GDLevelEditScene.ensure_scene(other).ok and not GDLevelSceneDrop.is_bound_to_scene(other, editor_scene), "a scene marked for another level is rejected")
	for runtime_path in [layout.logic_scene_path, layout.art_scene_path]:
		layout.scene_path = runtime_path
		_check(not GDLevelEditScene.ensure_scene(layout).ok and not GDLevelEditScene.is_edit_scene(layout, runtime_scene), "an explicit runtime path cannot become the edit scene")
	layout.scene_path = _fixture_root.path_join("wrong_extension.tres")
	_check(not GDLevelEditScene.ensure_scene(layout).ok, "invalid editor scene extensions are rejected")
	editor_scene.free()
	runtime_scene.free()

	var legacy := GDLevelSceneRes.new()
	legacy.scene_path = _fixture_root.path_join("Editor_Legacy.tscn")
	_save_scene(Node3D.new(), legacy.scene_path)
	var existing := FileAccess.get_file_as_string(legacy.scene_path)
	result = GDLevelEditScene.ensure_scene(legacy)
	_check(result.ok and not result.created and FileAccess.get_file_as_string(legacy.scene_path) == existing, "existing explicit CLI editor scenes are reused without rewriting")

	var flat := GDLevelSceneRes.new()
	flat.scene_path = _fixture_root.path_join("Editor_2D.tscn")
	flat.art_scene_path = _fixture_root.path_join("Runtime_2D.tscn")
	_save_scene(Node2D.new(), flat.art_scene_path)
	result = GDLevelEditScene.ensure_scene(flat)
	_check(result.ok, "2D edit scene creation succeeds")
	if result.ok:
		_files.append(flat.scene_path)
		var flat_scene := (ResourceLoader.load(flat.scene_path) as PackedScene).instantiate()
		_check(flat_scene is Node2D and flat_scene.get_node("Placements") is Node2D, "2D runtime context creates a separate 2D editor workspace")
		flat_scene.free()

	var unbound := GDLevelSceneRes.new()
	result = GDLevelEditScene.ensure_scene(unbound)
	_check(result.ok and result.created and result.binding_changed and not unbound.scene_path.is_empty(), "an unbound level receives a new dedicated scene automatically")
	if result.ok:
		_files.append(unbound.scene_path)
		var auto_scene := (ResourceLoader.load(unbound.scene_path) as PackedScene).instantiate()
		_check(GDLevelSceneDrop.is_bound_to_scene(unbound, auto_scene), "automatically created scene is bound only to its own level")
		auto_scene.free()
	var collision := GDLevelSceneRes.new()
	var collision_path := "%s/Editor_%s.tscn" % [GDLevelEditScene.SCENE_DIR, collision.layout_id.validate_filename()]
	_save_scene(Node3D.new(), collision_path)
	var collision_before := FileAccess.get_file_as_string(collision_path)
	_check(not GDLevelEditScene.ensure_scene(collision).ok and collision.scene_path.is_empty() and FileAccess.get_file_as_string(collision_path) == collision_before, "automatic scene creation never claims or overwrites an unrelated existing file")


func _test_asset_picker() -> void:
	var scan_root := _fixture_root.path_join("assets")
	_make_directory(scan_root)
	_make_directory(scan_root.path_join("nested"))
	_make_directory(scan_root.path_join(".hidden"))
	_make_directory(scan_root.path_join("ignored"))
	_make_directory(scan_root.path_join("separate_project"))
	_write_file(scan_root.path_join("ignored/.gdignore"), "")
	_write_file(scan_root.path_join("separate_project/project.godot"), "config_version=5\n")
	var alpha := _save_level(scan_root.path_join("nested/alpha.tres"), "Alpha Level")
	var beta := _save_level(scan_root.path_join("beta.res"), "Beta Level")
	_save_level(scan_root.path_join(".hidden/hidden.tres"), "Hidden")
	_save_level(scan_root.path_join("ignored/ignored.tres"), "Ignored")
	_save_level(scan_root.path_join("separate_project/foreign.tres"), "Other Project")
	var ordinary_path := scan_root.path_join("ordinary.tres")
	_check(ResourceSaver.save(Resource.new(), ordinary_path) == OK, "ordinary resource fixture saves")
	_files.append(ordinary_path)
	var levels := GDLevelAssetPicker.scan_levels(scan_root)
	_check(levels == [alpha, beta], "asset scan recurses, supports tres/res, sorts names, and excludes non-levels and ignored projects")
	_check(GDLevelAssetPicker.scan_levels(scan_root.path_join("missing")).is_empty(), "missing asset directories produce an empty list")
	var dialog := GDLevelAssetPicker.new()
	root.add_child(dialog)
	var opened: Array[GDLevelSceneRes] = []
	dialog._on_level = func(level: GDLevelSceneRes) -> void: opened.append(level)
	dialog._list.set_items([{"title": "", "items": [
		{"key": alpha, "text": alpha.display_name, "detail": alpha.resource_path},
		{"key": beta, "text": beta.display_name, "detail": beta.resource_path},
	]}])
	_check(dialog.get_ok_button().disabled and not (dialog as Node) is FileDialog, "open level uses an asset list and requires a selection")
	dialog._list._tree.get_root().get_first_child().select(0)
	_check(not dialog.get_ok_button().disabled and dialog._list.selected_level() == alpha, "selecting a level enables opening")
	dialog._list._search.text = "Beta"
	dialog._list._search.text_changed.emit("Beta")
	_check(dialog._list._tree.get_root().get_child_count() == 1 and dialog.get_ok_button().disabled, "filtering hides unmatched assets and invalidates a hidden selection")
	dialog._open_selected()
	_check(opened.is_empty(), "a filtered-out selection cannot open a level")
	dialog._list._tree.get_root().get_first_child().select(0)
	dialog.confirmed.emit()
	_check(opened == [beta], "confirm opens the selected level resource")
	dialog.free()


func _test_page_requires_actual_scene() -> void:
	var page := GDLevelPage.new()
	root.add_child(page)
	var layout := GDSampleFactory.build_level_scene()
	page.set_layout(layout)
	_check(not page.can_edit_scene(), "opening only the document does not grant instance editing")
	page.select_placement(layout.placements[0].instance_id)
	_check(page.selected_placement() == 0, "production page rejects instance selection without an active edit scene")
	page.commands.open_level()
	var dialogs := page.get_children().filter(func(node: Node) -> bool: return node is GDLevelAssetPicker)
	_check(dialogs.size() == 1, "open level command presents the asset picker")
	page.free()


func _save_level(path: String, name: String) -> GDLevelSceneRes:
	var layout := GDLevelSceneRes.new()
	layout.display_name = name
	_check(ResourceSaver.save(layout, path) == OK, "level asset fixture saves")
	layout.take_over_path(path)
	_files.append(path)
	return layout


func _save_scene(node: Node, path: String) -> void:
	node.name = path.get_file().get_basename()
	var packed := PackedScene.new()
	_check(packed.pack(node) == OK and ResourceSaver.save(packed, path) == OK, "scene fixture saves")
	node.free()
	_files.append(path)


func _make_directory(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	_directories.append(path)


func _write_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
	_files.append(path)


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: %s" % label)
