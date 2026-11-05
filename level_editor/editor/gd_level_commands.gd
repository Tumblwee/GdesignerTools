@tool
class_name GDLevelCommands
extends RefCounted

## 关卡页的命令：右键菜单、增删改、文件工具。改完模型就提交，选中交回页面。

var _page: GDLevelPage = null


func _init(page: GDLevelPage) -> void:
	_page = page


var layout: GDLevelSceneRes:
	get:
		return _page.layout


func _commit(label: String) -> void:
	_page.doc.commit(label)


# ── 原型 ──

func archetype_menu(key: Variant) -> void:
	if layout == null:
		return
	if key == null:
		GDEditorUi.context_menu(_page, [{"text": "新建原型", "do": new_archetype}])
		return
	var archetype: GDArchetypeRes = key
	var items: Array = [
		{"text": "放到视口中心", "do": func() -> void: _page.place_at_view(archetype)},
		null,
		{"text": "重命名…", "do": func() -> void: rename_archetype(archetype), "shortcut": GDEditorUi.key(KEY_F2)},
		{"text": "复制", "do": func() -> void: duplicate_archetype(archetype), "shortcut": GDEditorUi.key(KEY_D, true)},
		{"text": "创建变体", "do": func() -> void: _add_copy(archetype, true)},
	]
	var target := _page.find_placement(_page.selected_placement())
	if target != null:
		items.append({"text": "替换选中实例为此原型", "do": func() -> void: replace_archetype(target.instance_id, archetype.stable_id),
			"disabled": target.archetype_stable_id == archetype.stable_id})
	items.append_array([null, {"text": "删除", "do": func() -> void: delete_archetype(archetype), "shortcut": GDEditorUi.key(KEY_DELETE)}])
	GDEditorUi.context_menu(_page, items)


func new_archetype() -> void:
	if layout == null:
		return
	var n := 1
	while layout.archetypes.any(func(a: GDArchetypeRes) -> bool: return a != null and a.display_name == "新原型_%d" % n):
		n += 1
	var archetype := GDLevelArchetypeRes.new()
	archetype.resource_name = _unique_asset_name("NewArchetype%d" % n)
	archetype.editor_init_with_addresses(layout.editor_allocate_next_archetype_stable_id(), "新原型_%d" % n, "", "")
	layout.editor_add_archetype(archetype)
	_commit("新建原型")
	_page.select_archetype(archetype)


func rename_archetype(archetype: GDArchetypeRes) -> void:
	GDDialogs.form(_page, "重命名原型", [
		{"key": "name", "label": "名称", "value": _asset_stem(archetype.resource_name)},
		{"key": "display", "label": "显示名", "value": archetype.display_name},
	], func(values: Dictionary) -> void:
		var result := layout.editor_rename_archetype(archetype, _asset_name(str(values["name"])), str(values["display"]))
		if bool(result.get("ok", false)):
			_commit("重命名原型")
		else:
			_page.say(str(result.get("error", "重命名失败")), &"danger")
	, func(values: Dictionary) -> String:
		var stem := str(values["name"])
		if not _is_identifier(stem):
			return "名称必须是合法标识符"
		if str(values["display"]).is_empty():
			return "显示名不能为空"
		var full := _asset_name(stem)
		return "已有同名原型" if layout.archetypes.any(func(a: GDArchetypeRes) -> bool: return a != archetype and a != null and a.resource_name == full) else ""
	)


func duplicate_archetype(archetype: GDArchetypeRes) -> void:
	_add_copy(archetype, false)


func _add_copy(archetype: GDArchetypeRes, as_variant: bool) -> void:
	var stem := "%s%s" % [_asset_stem(archetype.resource_name), "Variant" if as_variant else "Copy"]
	var display := "%s %s" % [archetype.display_name, "变体" if as_variant else "副本"]
	var copy := GDArchetypeOps.create_duplicate(archetype, layout.editor_allocate_next_archetype_stable_id(), _unique_asset_name(stem), display, as_variant)
	layout.editor_add_archetype(copy)
	_commit("创建变体" if as_variant else "复制原型")
	_page.select_archetype(copy)


## 删除原型会连带删掉用它的实例，所以这时才确认。
func delete_archetype(archetype: GDArchetypeRes) -> void:
	var uses := layout.editor_count_placements_by_archetype_stable_id(archetype.stable_id)
	if uses > 0 and not _page.require_edit_scene():
		return
	if uses == 0:
		_remove_archetype(archetype)
		return
	var target := layout
	GDDialogs.confirm(_page, "删除原型", "有 %d 个实例使用「%s」，会一起删除。" % [uses, archetype.display_name], "删除", func() -> void:
		if layout == target and _page.require_edit_scene():
			_remove_archetype(archetype)
	)


func _remove_archetype(archetype: GDArchetypeRes) -> void:
	if layout.editor_count_placements_by_archetype_stable_id(archetype.stable_id) > 0 and not _page.require_edit_scene():
		return
	layout.editor_remove_placements_by_archetype_stable_id(archetype.stable_id)
	layout.editor_remove_archetype(archetype)
	GDLevelSceneDrop.reconcile_scene(layout)
	_commit("删除原型")
	_page.say("已删除「%s」，可以撤销" % archetype.display_name)


func replace_archetype(id: int, stable_id: int) -> void:
	if not _page.require_edit_scene():
		return
	if GDLevelInspector.swap_archetype(layout, id, stable_id):
		_commit("替换原型")


## 关卡原型资产名：PlacementArchetype_<模块>_<名>。
func _asset_name(stem: String) -> String:
	return "%s%s_%s" % [GDLevelSceneRes.ARCHETYPE_ASSET_PREFIX, _module_name(), stem]


static func _asset_stem(asset_name: String) -> String:
	if not asset_name.begins_with(GDLevelSceneRes.ARCHETYPE_ASSET_PREFIX):
		return asset_name
	var rest := asset_name.trim_prefix(GDLevelSceneRes.ARCHETYPE_ASSET_PREFIX)
	return rest.substr(rest.find("_") + 1) if rest.find("_") > 0 else rest


func _unique_asset_name(stem: String) -> String:
	var candidate := _asset_name(stem)
	var n := 2
	while layout.archetypes.any(func(a: GDArchetypeRes) -> bool: return a != null and a.resource_name == candidate):
		candidate = _asset_name("%s%d" % [stem, n])
		n += 1
	return candidate


func _module_name() -> String:
	var stem := layout.resource_name.trim_prefix("LevelScene_").replace("_", "")
	return stem if _is_identifier(stem) else "Level"


static func _is_identifier(text: String) -> bool:
	return GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(text, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.TYPE_NAME)


# ── 实例 / 路径 / 相机：列表和平面图共用 ──

func item_menu(kind: GDLevelPage.Kind, key: int) -> void:
	if not _page.require_edit_scene():
		return
	var rename := {"text": "重命名…", "do": func() -> void: rename_item(kind, key), "shortcut": GDEditorUi.key(KEY_F2)}
	var duplicate := {"text": "复制", "do": func() -> void: duplicate_item(kind, key), "shortcut": GDEditorUi.key(KEY_D, true)}
	var remove := {"text": "删除", "do": func() -> void: delete_item(kind, key), "shortcut": GDEditorUi.key(KEY_DELETE)}
	match kind:
		GDLevelPage.Kind.PLACEMENT:
			var index := int(layout.editor_try_get_placement(key).get("index", 0))
			GDEditorUi.context_menu(_page, [rename, duplicate, {"text": "重设 ID…", "do": func() -> void: reset_instance_id(key)}, null,
				{"text": "上移", "do": func() -> void: _move_instance(key, index - 1), "disabled": index == 0},
				{"text": "下移", "do": func() -> void: _move_instance(key, index + 2), "disabled": index >= layout.placements.size() - 1},
				null, remove])
		GDLevelPage.Kind.PATH:
			GDEditorUi.context_menu(_page, [rename, duplicate, null, remove])
		GDLevelPage.Kind.CAMERA:
			GDEditorUi.context_menu(_page, [{"text": "应用到主相机", "do": func() -> void: apply_camera(key)}, null, rename, duplicate, null, remove])
		_:
			GDEditorUi.context_menu(_page, [
				{"text": "新建路径", "do": func() -> void: add_item(GDLevelPage.Kind.PATH)},
				{"text": "记录主相机", "do": func() -> void: add_item(GDLevelPage.Kind.CAMERA)},
				null,
				{"text": "显示全部", "do": _page.fit_plan, "shortcut": GDEditorUi.key(KEY_F)},
			])


func add_item(kind: GDLevelPage.Kind) -> void:
	if not _page.require_edit_scene():
		return
	match kind:
		GDLevelPage.Kind.PATH:
			var center := _page.view_center()
			var id := layout.editor_add_path(0, GDPathSystem.SplineData.build_default_spline(Vector3(center.x, 0.0, center.y)), 1.0)
			_commit("新建路径")
			_page.select_item(GDLevelPage.Kind.PATH, id)
		GDLevelPage.Kind.CAMERA:
			var index := layout.camera_poses.size()
			var pose := GDCameraPoseSystem.CameraPose.new(Vector3(0, 15, 15), Vector3(-45, 0, 0), 60.0)
			pose.editor_init_identity(_unique_pose_name(), "相机 %d" % (index + 1))
			var camera := GDLevelInspector.viewport_camera()
			layout.camera_poses.append(GDLevelInspector.pose_from_camera(pose, camera) if camera != null else pose)
			layout.emit_changed()
			_commit("记录主相机")
			_page.select_item(GDLevelPage.Kind.CAMERA, index)
			if camera == null:
				_page.say("没有 3D 视口，已按默认机位记录")


func _unique_pose_name() -> String:
	var n := layout.camera_poses.size()
	while bool(layout.try_get_camera_pose("Camera_%d" % n).get("ok", false)):
		n += 1
	return "Camera_%d" % n


func rename_item(kind: GDLevelPage.Kind, key: int) -> void:
	if not _page.require_edit_scene():
		return
	var target := layout
	var current := ""
	match kind:
		GDLevelPage.Kind.PLACEMENT:
			current = _page.placement_title(_page.find_placement(key))
		GDLevelPage.Kind.PATH:
			current = GDLevelPage.path_title(_page.find_path(key))
		GDLevelPage.Kind.CAMERA:
			current = _page.find_pose(key).display_name
		_:
			return
	GDDialogs.prompt(_page, "重命名", "显示名", current, func(text: String) -> void:
		if layout != target or not _page.require_edit_scene():
			return
		match kind:
			GDLevelPage.Kind.PLACEMENT:
				layout.editor_replace_placement(key, _page.find_placement(key).with_display_name(text))
			GDLevelPage.Kind.PATH:
				layout.editor_replace_path(key, _page.find_path(key).with_display_name(text))
			GDLevelPage.Kind.CAMERA:
				layout.editor_replace_camera_pose_at(key, _page.find_pose(key).with_display_name(text))
		_commit("重命名")
	, func(text: String) -> String: return "显示名不能为空" if text.is_empty() else "")


## 复制品稍微挪开一点，免得和原件重叠看不出来。
func duplicate_item(kind: GDLevelPage.Kind, key: int) -> void:
	if not _page.require_edit_scene():
		return
	var id := 0
	match kind:
		GDLevelPage.Kind.PLACEMENT:
			var source := _page.find_placement(key)
			var added := layout.editor_try_add_placement(source.archetype_stable_id, source.position + Vector3(1, 0, 1), source.euler_angles, source.scale, source.initial_level)
			if not bool(added.get("ok", false)):
				_page.say(str(added.get("error", "复制失败")), &"danger")
				return
			id = int(added["instance_id"])
			layout.editor_replace_placement(id, _page.find_placement(id).with_overrides(source.attribute_overrides))
			GDLevelSceneDrop.reconcile_scene(layout)
		GDLevelPage.Kind.PATH:
			var source := _page.find_path(key)
			var spline := source.spline.clone_spline()
			for knot in spline.knots:
				knot.position += Vector3(1, 0, 1)
			id = layout.editor_add_path(source.path_type_keyword, spline, source.speed)
			layout.editor_replace_path(id, _page.find_path(id).with_display_name("%s 副本" % GDLevelPage.path_title(source)))
		GDLevelPage.Kind.CAMERA:
			var source := _page.find_pose(key)
			layout.camera_poses.append(source.with_name(_unique_pose_name()).with_display_name("%s 副本" % source.display_name))
			layout.emit_changed()
			id = layout.camera_poses.size() - 1
		_:
			return
	_commit("复制")
	_page.select_item(kind, id)


func delete_item(kind: GDLevelPage.Kind, key: int) -> void:
	if not _page.require_edit_scene():
		return
	match kind:
		GDLevelPage.Kind.PLACEMENT:
			var title := _page.placement_title(_page.find_placement(key))
			GDLevelSceneDrop.erase_placed(layout, key)
			_commit("删除实例")
			_page.say("已删除「%s」，可以撤销" % title)
		GDLevelPage.Kind.PATH:
			layout.editor_remove_path(key)
			_commit("删除路径")
		GDLevelPage.Kind.CAMERA:
			layout.editor_remove_camera_pose_at(key)
			_commit("删除相机")


func _move_instance(id: int, insert_index: int) -> void:
	if not _page.require_edit_scene():
		return
	if layout.editor_move_placement(id, insert_index):
		_commit("调整实例顺序")


func reset_instance_id(id: int) -> void:
	if not _page.require_edit_scene():
		return
	var target := layout
	GDDialogs.prompt(_page, "重设实例 ID", "新 ID", str(id), func(text: String) -> void:
		if layout != target or not _page.require_edit_scene():
			return
		var was_selected := _page.selected_placement() == id
		if layout.editor_reset_instance_id(id, text.to_int()):
			GDLevelSceneDrop.reconcile_scene(layout)
			_commit("重设实例 ID")
			if was_selected:
				_page.select_item(GDLevelPage.Kind.PLACEMENT, text.to_int())
	, func(text: String) -> String:
		if not text.is_valid_int() or text.to_int() <= 0:
			return "ID 必须是正整数"
		if text.to_int() == id:
			return "和当前 ID 相同"
		return "ID %s 已被占用" % text if _page.find_placement(text.to_int()) != null else ""
	)


func standardize_instance_ids(archetype: GDArchetypeRes) -> void:
	if not _page.require_edit_scene():
		return
	var selected := _page.selected_placement()
	var result := layout.editor_try_standardize_instance_ids(archetype)
	if not bool(result.get("ok", false)):
		_page.say(str(result.get("error", "标准化失败")), &"danger")
		return
	var remaps: Array = result.get("remaps", [])
	for remap: Dictionary in remaps:
		if selected == int(remap["old_id"]):
			selected = int(remap["new_id"])
	GDLevelSceneDrop.reconcile_scene(layout)
	_commit("标准化实例 ID")
	if selected != 0:
		_page.select_item(GDLevelPage.Kind.PLACEMENT, selected)
	_page.say("已重排 %d 个实例 ID" % remaps.size(), &"ok")


func apply_camera(index: int) -> void:
	if not _page.require_edit_scene():
		return
	var camera := GDLevelInspector.scene_camera()
	if camera == null:
		_page.say("当前场景里没有 Camera3D", &"warn")
		return
	GDLevelInspector.apply_pose(_page.find_pose(index), camera)
	_page.say("已应用到 %s" % camera.name, &"ok")


# ── 文件与工具 ──

func new_level() -> void:
	GDDialogs.form(_page, "新建关卡", [
		{"key": "name", "label": "名称", "value": "NewLevel", "placeholder": "英文标识符"},
	], func(values: Dictionary) -> void:
		var created := GDLevelSceneRes.new()
		created.resource_name = str(values["name"])
		created.display_name = str(values["name"])
		_page.set_layout(created)
		_page.save_current()
	, func(values: Dictionary) -> String:
		if not _is_identifier(str(values["name"])):
			return "名称必须是合法标识符"
		return "已有同名关卡" if ResourceLoader.exists("%s/%s.tres" % [GDLevelPage.LEVEL_DIR, values["name"]]) else ""
	)


func open_level() -> void:
	GDLevelAssetPicker.open(_page, _page.set_layout)


func edit_types() -> void:
	if layout == null:
		return
	if layout.placement_archetype_type_keywords == null:
		var catalog := GDKeywordCatalogRes.new()
		catalog.enum_namespace = "%s.Keywords" % _module_name()
		catalog.enum_type_name = "PlacementArchetypeTypeKind"
		layout.editor_bind_archetype_type_keywords(catalog)
	GDKeywordCatalogDialog.open(_page, layout.placement_archetype_type_keywords, _commit)


func export_csv() -> void:
	if layout == null:
		return
	var target := layout
	var suggested := target.resource_path.get_basename() + ".csv" if GDLevelPage.is_file(target) else "res://%s.csv" % _page.doc_title(target).validate_filename()
	GDDialogs.save_file(_page, "导出摆放 CSV", PackedStringArray(["*.csv ; CSV 表格"]), suggested, func(path: String) -> void:
		var result := GDLevelCsvExporter.try_write_to_file(target, path)
		if bool(result.get("ok", false)):
			_page.say("已导出 %d 个实例到 %s" % [target.placements.size(), path], &"ok")
		else:
			_page.say(str(result.get("error", "导出失败")), &"danger")
	)


## 迁移会直接写盘，所以先预演，把结果给人看过再执行。
func migrate_ids() -> void:
	if not _page.require_edit_scene():
		return
	var preview := GDLayoutMigration.run_migration([layout])
	if preview.instance_id_reassigned == 0:
		_page.say("实例 ID 已是从 %d 起的连续编号，无需迁移" % GDLevelSceneRes.INSTANCE_ID_START, &"ok")
		return
	var target := layout
	var target_doc := _page.doc
	var message := "%d 个实例中有 %d 个会重新编号为从 %d 起的连续 ID。" % [preview.placement_count, preview.instance_id_reassigned, GDLevelSceneRes.INSTANCE_ID_START]
	if GDLevelPage.is_file(target):
		message += "\n迁移后立即保存到 %s。" % target.resource_path
	GDDialogs.confirm(_page, "迁移 ID", message, "迁移", func() -> void:
		if layout != target or not _page.require_edit_scene():
			return
		var options := GDLayoutMigration.MigrationOptions.new()
		options.dry_run = false
		GDLayoutMigration.run_migration([target], options)
		GDLevelSceneDrop.reconcile_scene(target)
		target_doc.commit("迁移 ID")
		if GDLevelPage.is_file(target):
			target_doc.save()
		_page.say("已迁移 %d 个实例 ID" % preview.instance_id_reassigned, &"ok")
	)
