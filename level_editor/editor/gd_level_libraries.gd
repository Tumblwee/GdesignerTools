@tool
class_name GDLevelLibraries
extends RefCounted

## 项目级共享资产。测试可把 storage_root 指向 user://，不触碰设计文件。
static var storage_root := "res://game_res/level/libraries"
static var _catalog: GDKeywordCatalogRes = null
static var _default_library: GDLevelLibraryRes = null

static func catalog_path() -> String:
	return storage_root.path_join("PlacementTypes.tres")

static func catalog() -> GDKeywordCatalogRes:
	if _catalog == null:
		_catalog = load(catalog_path()) as GDKeywordCatalogRes if ResourceLoader.exists(catalog_path()) else GDKeywordCatalogRes.new()
		_catalog.resource_name = "PlacementTypes"
		_catalog.enum_namespace = "Project.Keywords"
		_catalog.enum_type_name = "PlacementArchetypeTypeKind"
		_catalog.editor_reconcile_next_stable_id_after_load()
	return _catalog

static func default_library() -> GDLevelLibraryRes:
	if _default_library == null:
		var path := storage_root.path_join("PlacementLibrary_Default.tres")
		_default_library = load(path) as GDLevelLibraryRes if ResourceLoader.exists(path) else GDLevelLibraryRes.new()
		_default_library.resource_name = "PlacementLibrary_Default"
		_default_library.display_name = "默认原型库"
	return _default_library

## 返回是否迁移了旧关卡。原型、实例 ID 和原型对象身份均保持不变。
static func prepare(layout: GDLevelSceneRes, preferred: GDLevelLibraryRes = null) -> bool:
	var migrated := false
	var has_legacy_types := layout.archetype_library == null and not layout.archetypes.is_empty()
	var global_types := catalog()
	if layout.archetype_library == null:
		if layout.archetypes.is_empty():
			layout.archetype_library = preferred if preferred != null else default_library()
		else:
			var library := GDLevelLibraryRes.new()
			library.display_name = "%s原型库" % (layout.display_name if not layout.display_name.is_empty() else layout.resource_name)
			library.resource_name = "PlacementLibrary_%s_%s" % [layout.resource_name.validate_filename(), layout.layout_id]
			library.archetypes = layout.archetypes.duplicate()
			library.next_archetype_stable_id = layout.next_archetype_stable_id
			layout.archetype_library = library
		migrated = true
	if layout.placement_archetype_type_keywords != global_types:
		if has_legacy_types:
			merge_types(layout.placement_archetype_type_keywords, layout.archetypes, global_types)
		layout.placement_archetype_type_keywords = global_types
		migrated = true
	layout.archetype_library.reconcile_ids()
	return migrated

## 旧目录中的同号异名类型必须重映射；绝不把已有原型静默归到别的类型。
static func merge_types(source: Resource, archetypes: Array, target: GDKeywordCatalogRes) -> void:
	if source == target:
		return
	var remaps := {}
	if source != null:
		for entry in source.entries:
			if entry == null:
				continue
			var found = target.find_any_by_name(entry.entry_name)
			# 自动生成的 Type/Type2 名字可能来自不同的中文类型。
			if found != null and found.display_name != entry.display_name:
				found = null
			if found == null:
				var copy := entry.duplicate() as GDKeywordEntryRes
				copy.display_color = entry.get_display_color()
				if target.find_any_by_name(copy.entry_name) != null or not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(copy.entry_name):
					copy.entry_name = GDKeywordCatalogDialog.unique_internal_name(target, copy.entry_name)
				if target.entries.any(func(e: Resource) -> bool: return e != null and e.stable_id == copy.stable_id):
					copy.stable_id = target.editor_allocate_next_stable_id()
				target.entries.append(copy)
				target.editor_reconcile_next_stable_id_after_load()
				found = copy
			remaps[entry.stable_id] = found.stable_id
	for archetype: GDArchetypeRes in archetypes:
		if archetype == null or archetype.archetype_type_stable_id == 0:
			continue
		# 同一份外部原型可能被多个旧关卡引用，迁移只能重映射一次。
		if archetype.get_meta(&"gd_placement_types_catalog", "") == catalog_path():
			continue
		var old_id := archetype.archetype_type_stable_id
		if not remaps.has(old_id):
			var entry_name := "LegacyType%d" % old_id
			var found = target.find_any_by_name(entry_name)
			if found == null:
				found = target.add_entry(entry_name, "原类型 %d" % old_id)
			remaps[old_id] = found.stable_id
		archetype.archetype_type_stable_id = remaps[old_id]
		archetype.set_meta(&"gd_placement_types_catalog", catalog_path())

static func save_path(resource: Resource) -> String:
	return catalog_path() if resource is GDKeywordCatalogRes else storage_root.path_join(resource.resource_name + ".tres")

static func scan_libraries(path: String = "res://") -> Array[GDLevelLibraryRes]:
	var result: Array[GDLevelLibraryRes] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	for file in directory.get_files():
		if file.get_extension() != "tres":
			continue
		var resource_path := path.path_join(file)
		var stream := FileAccess.open(resource_path, FileAccess.READ)
		if stream != null and stream.get_line().contains('script_class="GDLevelLibraryRes"'):
			var library := load(resource_path) as GDLevelLibraryRes
			if library != null:
				result.append(library)
	for child in directory.get_directories():
		var child_path := path.path_join(child)
		if not child.begins_with(".") and not FileAccess.file_exists(child_path.path_join("project.godot")) and not FileAccess.file_exists(child_path.path_join(".gdignore")):
			result.append_array(scan_libraries(child_path))
	return result

## ResourceSaver 不会写回外部 .tres；先保存库引用的独立原型和属性。
static func save_external_children(resource: Resource, visited: Dictionary = {}) -> Error:
	if visited.has(resource):
		return OK
	visited[resource] = true
	for child: Resource in GDDocument.capture(resource):
		if child == resource or visited.has(child):
			continue
		var err := save_external_children(child, visited)
		if err != OK:
			return err
		if not child.resource_path.is_empty() and not child.resource_path.contains("::"):
			err = GDDocument.new(child).save()
			if err != OK:
				return err
	return OK
