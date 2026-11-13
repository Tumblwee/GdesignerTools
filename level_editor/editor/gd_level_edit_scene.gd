@tool
class_name GDLevelEditScene
extends RefCounted

## 编辑工作区保留可编辑实例，临时预览复用美术场景或游戏提供的运行时构建器。
const SCENE_DIR := "res://game_res/level/editing"
const META_EDIT_LAYOUT := "gdesigner_edit_layout_id"
const PREVIEW_ROOT := "RuntimePreview"
const PREVIEW_DRIVER := "GDesignerPreview"
const META_PREVIEW_SIGNATURE := "gdesigner_preview_signature"
const DRIVER_SCRIPT := "res://addons/gdesigner_tools/level_editor/editor/gd_level_preview.gd"


static func is_runtime_path(layout: GDLevelSceneRes, path: String) -> bool:
	if layout == null or path.is_empty():
		return false
	var key := GDDocument.path_key(path)
	return (not layout.art_scene_path.is_empty() and key == GDDocument.path_key(layout.art_scene_path)) \
		or (not layout.logic_scene_path.is_empty() and key == GDDocument.path_key(layout.logic_scene_path))


static func is_edit_scene(layout: GDLevelSceneRes, scene_root: Node) -> bool:
	if layout == null or scene_root == null or layout.scene_path.is_empty() or scene_root.scene_file_path.is_empty():
		return false
	if GDDocument.path_key(layout.scene_path) != GDDocument.path_key(scene_root.scene_file_path) or is_runtime_path(layout, layout.scene_path):
		return false
	# CLI 已有的独立编辑场景没有标记；新工作区额外核验持有者。
	return not scene_root.has_meta(META_EDIT_LAYOUT) \
		or str(scene_root.get_meta(META_EDIT_LAYOUT)) == GDSceneEditorRuntime.layout_identity(layout)


static func ensure_scene(layout: GDLevelSceneRes) -> Dictionary:
	if layout == null:
		return _error("没有打开关卡。")
	GDLevelSceneDrop.ensure_layout_identity(layout)
	if not GDLevelSceneDrop.register_layout(layout):
		return _error("关卡标识重复，无法打开编辑场景。")
	var binding_changed := layout.scene_path.is_empty()
	var path := layout.scene_path
	if path.is_empty():
		path = "%s/Editor_%s.tscn" % [SCENE_DIR, layout.layout_id.validate_filename()]
	path = GDDocument.normalized_path(path)
	if not (path.begins_with("res://") or (not Engine.is_editor_hint() and path.begins_with("user://"))) or path.get_extension().to_lower() != "tscn":
		return _error("编辑场景必须是项目内的 .tscn 文件：%s" % path)
	if is_runtime_path(layout, path):
		return _error("编辑场景不能与运行时美术或逻辑场景共用：%s" % path)
	var created := false
	if FileAccess.file_exists(path):
		var packed := ResourceLoader.load(path) as PackedScene
		if packed == null:
			return _error("无法读取关卡编辑场景：%s" % path)
		var state := packed.get_state()
		if state.get_node_count() == 0:
			return _error("关卡编辑场景没有根节点：%s" % path)
		var owner_id := _root_meta(state, META_EDIT_LAYOUT)
		if not owner_id.is_empty() and owner_id != GDSceneEditorRuntime.layout_identity(layout):
			return _error("编辑场景属于另一关卡：%s" % path)
		# 自动生成路径发生碰撞时不能认领未标记的已有文件。
		if binding_changed and owner_id.is_empty():
			return _error("编辑场景路径已被其他文件占用：%s" % path)
	else:
		var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		if dir_error != OK:
			return _error("无法创建编辑场景目录：%s" % error_string(dir_error))
		var use_2d := _uses_2d(layout)
		var scene_root: Node = Node2D.new() if use_2d else Node3D.new()
		scene_root.name = "Editor_%s" % (layout.resource_name if not layout.resource_name.is_empty() else "Level")
		scene_root.set_meta(META_EDIT_LAYOUT, GDSceneEditorRuntime.layout_identity(layout))
		var placements: Node = Node2D.new() if use_2d else Node3D.new()
		placements.name = GDLevelSceneDrop.PLACEMENTS_ROOT
		placements.set_meta(GDLevelSceneDrop.META_LAYOUT, GDSceneEditorRuntime.layout_identity(layout))
		scene_root.add_child(placements)
		placements.owner = scene_root
		ensure_preview_driver(layout, scene_root)
		var packed := PackedScene.new()
		var saved := packed.pack(scene_root)
		scene_root.free()
		if saved == OK:
			saved = ResourceSaver.save(packed, path)
		if saved != OK:
			return _error("创建编辑场景失败：%s（%s）" % [path, error_string(saved)])
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(path)
		created = true
	if binding_changed:
		layout.scene_path = path
		layout.emit_changed()
	return {"ok": true, "path": path, "error": "", "binding_changed": binding_changed, "created": created}


static func open_scene(layout: GDLevelSceneRes) -> Dictionary:
	var result := ensure_scene(layout)
	if bool(result.get("ok", false)) and Engine.is_editor_hint():
		EditorInterface.open_scene_from_path(str(result["path"]))
	return result


static func ensure_preview_driver(layout: GDLevelSceneRes, scene_root: Node) -> void:
	if layout == null or scene_root == null or layout.resource_path.is_empty():
		return
	var driver := scene_root.get_node_or_null(PREVIEW_DRIVER)
	var changed := false
	if driver == null:
		driver = Node.new()
		driver.set_script(load(DRIVER_SCRIPT))
		driver.name = PREVIEW_DRIVER
		driver.set("layout_path", layout.resource_path)
		scene_root.add_child(driver)
		driver.owner = scene_root
		changed = true
	elif driver.get_script() == load(DRIVER_SCRIPT) and driver.get("layout_path") != layout.resource_path:
		driver.set("layout_path", layout.resource_path)
		changed = true
	if changed and Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == scene_root:
		EditorInterface.mark_scene_as_unsaved()


static func refresh_preview(layout: GDLevelSceneRes, scene_root: Node) -> void:
	if not is_edit_scene(layout, scene_root):
		return
	ensure_preview_driver(layout, scene_root)
	var signature := layout.editor_preview_signature()
	var previous := scene_root.get_node_or_null(PREVIEW_ROOT)
	if previous != null:
		# Never replace a user-authored node that happens to use this name.
		if not previous.has_meta(META_EDIT_LAYOUT) or previous.owner != null:
			return
		if previous.get_meta(META_PREVIEW_SIGNATURE, "") == signature:
			return
		scene_root.remove_child(previous)
		previous.queue_free()
	var preview := layout.editor_create_scene_preview()
	if preview != null:
		preview.name = PREVIEW_ROOT
		preview.set_meta(META_EDIT_LAYOUT, GDSceneEditorRuntime.layout_identity(layout))
		preview.set_meta(META_PREVIEW_SIGNATURE, signature)
		GDPreviewScene.prepare(preview)
		scene_root.add_child(preview)
		GDPreviewScene.freeze(preview)
		_clear_preview_owners(preview)


static func _clear_preview_owners(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_preview_owners(child)


static func _root_meta(state: SceneState, key: StringName) -> String:
	for index in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0, index) == "metadata/%s" % key:
			return str(state.get_node_property_value(0, index))
	return ""


static func _uses_2d(layout: GDLevelSceneRes) -> bool:
	for path: String in [layout.art_scene_path, layout.logic_scene_path]:
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var packed := ResourceLoader.load(path) as PackedScene
		if packed != null and _root_is_2d(packed):
			return true
	for archetype: GDArchetypeRes in layout.archetypes:
		if archetype == null:
			continue
		var packed := archetype.editor_resolve_manufactured_prefab()
		if packed == null:
			packed = archetype.editor_resolve_preview_prefab()
		if packed != null:
			return _root_is_2d(packed)
	return false


static func _root_is_2d(packed: PackedScene) -> bool:
	var state := packed.get_state()
	if state.get_node_count() == 0:
		return false
	var type := state.get_node_type(0)
	return type == &"Node2D" or ClassDB.is_parent_class(type, &"Node2D")


static func _error(message: String) -> Dictionary:
	return {"ok": false, "path": "", "error": message, "binding_changed": false, "created": false}
