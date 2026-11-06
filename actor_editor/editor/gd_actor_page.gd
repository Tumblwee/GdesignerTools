@tool
class_name GDActorPage
extends GDPage

## 演员编辑器：左边演员列表，中间真实预览，右边属性。

var _list: GDLibraryList = null
var _preview: GDArchetypePreviewPanel = null
var _form: GDForm = null
var _selected: GDActorLibraryRes.ActorArchetypeRes = null
var _opened_default: bool = false
var level_provider: Callable = Callable()


var library: GDActorLibraryRes:
	get:
		return doc.resource as GDActorLibraryRes if doc != null else null


func _build() -> void:
	toolbar.add_child(GDEditorUi.menu_button("文件", &"", "新建、打开、另存为", [
		{"text": "新建演员库…", "do": _new_library},
		{"text": "打开演员库…", "do": _open_library},
		null,
		{"text": "另存为…", "do": save_as_current},
	]))
	toolbar.add_child(GDEditorUi.text_button("类型目录", _edit_types, &"flat"))

	_list = GDLibraryList.new("演员", "搜索名称或 ID")
	_list.header.add_child(GDEditorUi.tool_button(&"Add", "新建演员", _new_actor))
	_list.set_empty_state(GDEditorUi.empty_state("还没有演员", "演员是可复用的角色原型。", "新建演员", _new_actor))
	_list.item_selected.connect(select_archetype)
	_list.context_requested.connect(_show_context_menu)
	_list.delete_requested.connect(_delete)
	_list.rename_requested.connect(_rename)
	_list.duplicate_requested.connect(_duplicate)
	_list.drag_provider = _begin_actor_drag

	_preview = GDArchetypePreviewPanel.new()
	_form = GDForm.new()
	_form.committed.connect(func(label: String, merge: bool) -> void:
		if doc != null:
			doc.commit("修改%s" % label, merge)
	)
	set_panes(GDEditorUi.pane(_list), GDEditorUi.pane(_preview, 0), GDEditorUi.pane(GDEditorUi.scroll_of(_form)))
	_refresh()


func activate() -> void:
	if not _opened_default and doc == null:
		_opened_default = true
		set_library(GDSampleFactory.load_actor_library())


func set_library(new_library: GDActorLibraryRes) -> void:
	_selected = null
	open_document(new_library)
	if new_library != null:
		new_library.editor_reconcile_next_ids_after_load()
	_refresh()


func get_current_library() -> GDActorLibraryRes:
	return library


func _begin_actor_drag(actor: GDArchetypeRes) -> Variant:
	var target: GDLevelSceneRes = level_provider.call() if level_provider.is_valid() else null
	if target == null:
		say("请先在关卡页打开需要摆放演员的关卡。", &"warn")
		return null
	if library.resource_path.is_empty():
		save_current()
		if library.resource_path.is_empty():
			say("请先保存演员库，再拖入场景。", &"warn")
			return null
	var payload := GDLevelSceneDrop.begin_actor(actor, library, target)
	return payload if not payload.is_empty() else null


func select_archetype(archetype: GDActorLibraryRes.ActorArchetypeRes) -> void:
	_selected = archetype
	_refresh_detail()


func _suggest_save_path(resource: Resource) -> String:
	return "res://game_res/actors/%s.tres" % resource.resource_name if not resource.resource_name.is_empty() else ""


func _refresh() -> void:
	_refresh_list()
	_refresh_detail()


func _refresh_list() -> void:
	if library == null:
		_list.set_empty_state(GDEditorUi.empty_state("没有打开演员库", "", "打开演员库", _open_library))
		_list.set_items([])
		return
	_list.set_empty_state(GDEditorUi.empty_state("还没有演员", "演员是可复用的角色原型。", "新建演员", _new_actor))
	var groups := {}
	for archetype: GDActorLibraryRes.ActorArchetypeRes in library.archetypes:
		if archetype != null:
			groups.get_or_add(archetype.archetype_type_stable_id, []).append(_row_of(archetype))
	var ordered: Array = []
	for type_id: int in _ordered_types(groups):
		ordered.append({"key": type_id, "title": _type_name(type_id), "items": groups[type_id]})
	_list.set_items(ordered)
	_list.select_key(_selected)


func _row_of(archetype: GDActorLibraryRes.ActorArchetypeRes) -> Dictionary:
	var row := {
		"key": archetype,
		"text": archetype.display_name if not archetype.display_name.is_empty() else archetype.resource_name,
		"detail": "#%d" % archetype.stable_id,
		"color": GDEditorUi.type_color(library.actor_type_keywords, archetype.archetype_type_stable_id),
	}
	if archetype.is_override_archetype:
		row["tooltip"] = "变体，复写自 %s" % (archetype.override_base_archetype.display_name if archetype.override_base_archetype != null else "（丢失）")
		if archetype.override_base_archetype == null:
			row["tone"] = &"danger"
	return row


func _ordered_types(groups: Dictionary) -> Array:
	var ordered: Array = []
	var catalog: Resource = library.actor_type_keywords
	if catalog != null:
		for entry in catalog.entries:
			if entry != null and groups.has(entry.stable_id):
				ordered.append(entry.stable_id)
	for type_id: int in groups:
		if not ordered.has(type_id):
			ordered.append(type_id)
	return ordered


func _type_name(type_id: int) -> String:
	for item: Array in GDArchetypeInspector.type_items(library.actor_type_keywords):
		if item[1] == type_id:
			return item[0]
	return "类型 %d" % type_id


func _refresh_detail() -> void:
	if _selected != null and (library == null or not library.archetypes.has(_selected)):
		_selected = null
	_preview.show_archetype(_selected)
	if _selected == null:
		_form.clear()
		_form.custom(GDEditorUi.empty_state("选择一个演员", "在左侧选中后，这里显示它的属性。"))
		return
	if not _form.begin(GDArchetypeInspector.structure_key(_selected)):
		return
	var archetype := _selected
	GDArchetypeInspector.add_identity(_form, archetype, library.actor_type_keywords)
	GDArchetypeInspector.add_override(_form, archetype, library.archetypes)
	GDArchetypeInspector.add_addresses(_form, archetype)
	GDArchetypeInspector.add_custom_attributes(_form, archetype, func(label: String) -> void: doc.commit(label))


func _show_context_menu(key: Variant) -> void:
	if key == null:
		GDEditorUi.context_menu(self, [{"text": "新建演员…", "do": _new_actor}])
		return
	var archetype: GDActorLibraryRes.ActorArchetypeRes = key
	GDEditorUi.context_menu(self, [
		{"text": "重命名…", "do": func() -> void: _rename(archetype), "shortcut": GDEditorUi.key(KEY_F2)},
		{"text": "复制", "do": func() -> void: _duplicate(archetype), "shortcut": GDEditorUi.key(KEY_D, true)},
		{"text": "创建变体…", "do": func() -> void: _create_variant(archetype)},
		null,
		{"text": "删除", "do": func() -> void: _delete(archetype), "shortcut": GDEditorUi.key(KEY_DELETE)},
	])


func _new_library() -> void:
	GDDialogs.form(self, "新建演员库", [
		{"key": "module", "label": "模块名", "value": "MyActors"},
		{"key": "display", "label": "显示名", "value": "我的演员库"},
	], func(values: Dictionary) -> void:
		var module_name := str(values["module"])
		var created := GDActorLibraryRes.new()
		created.resource_name = "ActorLibrary_%s" % module_name
		created.display_name = str(values["display"])
		var keywords := GDActorTypeKeywordsRes.new()
		keywords.enum_namespace = "%s.Keywords" % module_name
		keywords.enum_type_name = "ActorArchetypeTypeKind"
		keywords.add_entry("Default", "默认分类", "")
		created.editor_set_actor_type_keywords(keywords)
		set_library(created)
		save_current()
	, func(values: Dictionary) -> String:
		return _library_name_error(str(values["module"]))
	)


func _library_name_error(module_name: String) -> String:
	if not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(module_name, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.TYPE_NAME):
		return "模块名必须是合法标识符"
	var asset_name := "ActorLibrary_%s" % module_name
	for opened: Resource in _docs:
		if opened.resource_name == asset_name:
			return "已有同名演员库"
	var path := "res://game_res/actors/%s.tres" % asset_name
	return "文件已存在：%s" % path if FileAccess.file_exists(path) else ""


func _open_library() -> void:
	GDActorLibraryPicker.open(self, set_library, _docs.keys())


func _new_actor() -> void:
	if library == null:
		set_library(GDSampleFactory.load_actor_library())
	var target := library
	GDDialogs.form(self, "新建演员", [
		{"key": "name", "label": "名称", "value": "NewActor", "placeholder": "英文标识符"},
		{"key": "display", "label": "显示名", "value": "新演员"},
		{"key": "type", "label": "类型", "value": 0, "items": GDArchetypeInspector.type_items(target.actor_type_keywords)},
	], func(values: Dictionary) -> void:
		var module_name := GDActorEditorServices.ActorArchetypeAssetPaths.resolve_module_name(target)
		var actor_name := str(values["name"])
		var archetype := GDActorArchetypeRes.new()
		archetype.resource_name = "%s%s_%s" % [GDActorEditorServices.ActorArchetypeAssetPaths.ARCHETYPE_FILE_PREFIX, module_name, actor_name]
		var entity := "%s%s_%s" % [GDActorEditorServices.ActorArchetypeAssetPaths.ENTITY_FILE_PREFIX, module_name, actor_name]
		archetype.editor_init_with_addresses(target.editor_allocate_next_archetype_stable_id(), str(values["display"]), entity, "")
		archetype.editor_set_archetype_type_stable_id(int(values["type"]))
		target.editor_add_archetype(archetype)
		_selected = archetype
		doc.commit("新建演员")
	, func(values: Dictionary) -> String:
		var actor_name := str(values["name"])
		if not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(actor_name, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.TYPE_NAME):
			return "名称必须是合法标识符"
		return "已有同名演员" if GDActorEditorServices.ActorArchetypeAssetPaths.is_archetype_name_taken(target, actor_name) else ""
	)


func _rename(archetype: GDActorLibraryRes.ActorArchetypeRes) -> void:
	var module_name := GDActorEditorServices.ActorArchetypeAssetPaths.resolve_module_name(library)
	var stem := GDActorEditorServices.ActorArchetypeAssetPaths.resolve_archetype_stem(archetype, module_name)
	GDDialogs.form(self, "重命名演员", [
		{"key": "name", "label": "名称", "value": stem},
		{"key": "display", "label": "显示名", "value": archetype.display_name},
	], func(values: Dictionary) -> void:
		var result := GDActorEditorServices.ActorArchetypeRenameService.try_rename(archetype, library, str(values["name"]), str(values["display"]))
		if bool(result.get("ok", false)):
			doc.commit("重命名演员")
		else:
			say(str(result.get("error", "重命名失败")), &"danger")
	)


func _duplicate(archetype: GDActorLibraryRes.ActorArchetypeRes) -> void:
	var defaults := GDActorEditorServices.ActorArchetypeDuplicateService.try_build_defaults(archetype, library)
	if not bool(defaults.get("ok", false)):
		say(str(defaults.get("error", "无法复制")), &"danger")
		return
	var result := GDActorEditorServices.ActorArchetypeDuplicateService.try_duplicate(archetype, library, str(defaults["archetype_name"]), str(defaults["display_name"]))
	if bool(result.get("ok", false)):
		_selected = result["created"]
		doc.commit("复制演员")


func _create_variant(archetype: GDActorLibraryRes.ActorArchetypeRes) -> void:
	var defaults := GDActorEditorServices.ActorArchetypeOverrideService.try_build_defaults(archetype, library)
	if not bool(defaults.get("ok", false)):
		say(str(defaults.get("error", "无法创建变体")), &"danger")
		return
	var result := GDActorEditorServices.ActorArchetypeOverrideService.try_create(archetype, library, str(defaults["archetype_name"]), str(defaults["display_name"]))
	if bool(result.get("ok", false)):
		_selected = result["created"]
		doc.commit("创建变体")


## 能撤销就不打断。只有会连带影响变体时才确认。
func _delete(archetype: GDActorLibraryRes.ActorArchetypeRes) -> void:
	var dependents := GDArchetypeOps.count_overrides_of(archetype, library.archetypes)
	if dependents == 0:
		_remove(archetype)
		return
	GDDialogs.confirm(self, "删除演员", "有 %d 个变体复写自「%s」，删除后它们会失去基底。" % [dependents, archetype.display_name], "删除", func() -> void: _remove(archetype))


func _remove(archetype: GDActorLibraryRes.ActorArchetypeRes) -> void:
	library.editor_remove_archetype(archetype)
	if _selected == archetype:
		_selected = null
	doc.commit("删除演员")
	say("已删除「%s」，可以撤销" % archetype.display_name)


func _edit_types() -> void:
	if library == null:
		return
	if library.actor_type_keywords == null:
		var keywords := GDActorTypeKeywordsRes.new()
		keywords.enum_namespace = "%s.Keywords" % GDActorEditorServices.ActorArchetypeAssetPaths.resolve_module_name(library)
		keywords.enum_type_name = "ActorArchetypeTypeKind"
		library.editor_set_actor_type_keywords(keywords)
	var target := doc
	var dialog := GDKeywordCatalogDialog.open(self, library.actor_type_keywords, func(label: String) -> void: target.commit(label))
	target.changed.connect(dialog.refresh_colors)
