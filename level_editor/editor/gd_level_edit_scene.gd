@tool
class_name GDLevelEditScene
extends RefCounted

## 关卡的场景工作区。scene_path 是编辑场景，art / logic 场景只供运行时装配。
const SCENE_DIR := "res://game_res/level/editing"
const META_EDIT_LAYOUT := "gdesigner_edit_layout_id"


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
