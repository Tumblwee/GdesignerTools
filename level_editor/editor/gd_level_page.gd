@tool
class_name GDLevelPage
extends GDPage

## 关卡编辑器：左边原型，中间俯视平面图和实例 / 路径 / 相机列表，右边属性。
## 原型拖进 3D / 2D 视口摆放；撤销、重做会把场景节点一起改回来。

const LEVEL_DIR := "res://game_res/level"
const TAB_TITLES: PackedStringArray = ["实例", "路径", "相机"]

enum Kind { NONE, PLACEMENT, PATH, CAMERA }

## 依次对应实例、路径、相机三个页签。
const TAB_KINDS: Array[Kind] = [Kind.PLACEMENT, Kind.PATH, Kind.CAMERA]

var commands: GDLevelCommands = null

var _archetype_list: GDLibraryList = null
var _plan: GDPlanView = null
var _tabs: TabBar = null
var _add_btn: Button = null
var _lists: Array[GDLibraryList] = []
var _form: GDForm = null
var _inspector: GDLevelInspector = null

## 平面上的选中项只记 ID（相机记序号）：路径和相机在撤销后会重建成新对象。
var _kind: Kind = Kind.NONE
var _id: int = 0
## 原型的选中独立于平面选中，这样才能“替换选中实例为此原型”。
var _archetype: GDArchetypeRes = null
## 属性栏显示原型，还是平面上的选中项。
var _inspect_archetype: bool = false
var _probe: Variant = null
## 上次刷新时的实例 ID，用来判断视口拖放或编辑器撤销是否改了关卡。
var _seen_ids: Array[int] = []
var _opened_default: bool = false
var _scene_hint: Label = null
var _opening_scene: bool = false
var _library_label: Label = null
var _last_library: GDLevelLibraryRes = null
var _history_doc: GDDocument = null

var library: GDLevelLibraryRes:
	get:
		return layout.archetype_library if layout != null else null

var library_doc: GDDocument:
	get:
		return _docs.get(library)


var layout: GDLevelSceneRes:
	get:
		return doc.resource as GDLevelSceneRes if doc != null else null


func _build() -> void:
	commands = GDLevelCommands.new(self)
	toolbar.add_child(GDEditorUi.menu_button("文件", &"", "新建、打开、另存为", [
		{"text": "新建关卡…", "do": commands.new_level},
		{"text": "打开关卡…", "do": commands.open_level},
		null,
		{"text": "另存为…", "do": save_as_current},
	]))
	toolbar.add_child(GDEditorUi.text_button("进入编辑场景", open_edit_scene, &"flat"))
	var sync := GDEditorUi.text_button("同步到场景", _sync_to_scene, &"flat")
	sync.tooltip_text = "把场景里还没有的实例生成到 Placements 下"
	toolbar.add_child(sync)
	toolbar.add_child(GDEditorUi.text_button("全局类型", commands.edit_types, &"flat"))
	toolbar_right.add_child(GDEditorUi.menu_button("", &"GuiTabMenuHl", "更多", [
		{"text": "导出摆放 CSV…", "do": commands.export_csv},
		{"text": "迁移 ID…", "do": commands.migrate_ids},
	]))

	_archetype_list = GDLibraryList.new("原型", "搜索名称或 ID")
	var library_box := VBoxContainer.new()
	var library_bar := HBoxContainer.new()
	library_box.add_child(library_bar)
	_library_label = GDEditorUi.hint_label("")
	_library_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_bar.add_child(_library_label)
	library_bar.add_child(GDEditorUi.menu_button("", &"Filesystem", "选择可跨关卡共用的原型库", [
		{"text": "选择原型库…", "do": choose_library},
		{"text": "新建原型库…", "do": new_library},
		{"text": "打开原型库文件…", "do": open_library},
	]))
	library_box.add_child(_archetype_list)
	_archetype_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_archetype_list.header.add_child(GDEditorUi.tool_button(&"Add", "新建原型", commands.new_archetype))
	_archetype_list.drag_provider = func(archetype: GDArchetypeRes) -> Variant: return GDLevelSceneDrop.begin(archetype, layout)
	_archetype_list.item_selected.connect(select_archetype)
	_archetype_list.item_activated.connect(func(archetype: GDArchetypeRes) -> void: place_at_view.call_deferred(archetype))
	_archetype_list.context_requested.connect(commands.archetype_menu)
	_archetype_list.delete_requested.connect(commands.delete_archetype)
	_archetype_list.rename_requested.connect(commands.rename_archetype)
	_archetype_list.duplicate_requested.connect(commands.duplicate_archetype)

	_form = GDForm.new()
	_form.committed.connect(func(label: String, merge: bool) -> void:
		if _inspect_archetype:
			commit_library("修改%s" % label, merge)
		elif doc != null and (_kind == Kind.NONE or can_edit_scene()):
			_history_doc = doc
			doc.commit("修改%s" % label, merge)
	)
	_inspector = GDLevelInspector.new(self, _form)
	set_panes(GDEditorUi.pane(library_box), _build_center(), GDEditorUi.pane(GDEditorUi.scroll_of(_form)))
	GDLevelSceneDrop.bind_status(_on_drop_status, _on_scene_bound)
	_show_tab(0)
	_refresh()


func _build_center() -> Control:
	_plan = GDPlanView.new()
	_plan.picked.connect(_on_plan_picked)
	_plan.moved.connect(_on_plan_moved)
	_plan.move_finished.connect(func(kind: StringName, _key: int) -> void:
		if doc != null and can_edit_scene():
			doc.commit("移动实例" if kind == GDPlanView.MARK else "移动路径节点")
	)
	_plan.dropped.connect(_on_plan_dropped)
	_plan.context_requested.connect(func(kind: StringName, key: int) -> void: commands.item_menu(_kind_of(kind), key))
	_plan.delete_requested.connect(func() -> void: commands.delete_item(_kind, _id))
	_plan.rename_requested.connect(func() -> void: commands.rename_item(_kind, _id))
	_plan.duplicate_requested.connect(func() -> void: commands.duplicate_item(_kind, _id))

	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", GDEditorUi.GAP)
	_scene_hint = GDEditorUi.hint_label("请进入此关卡的编辑场景后选择或编辑实例。")
	bottom.add_child(_scene_hint)
	var bar := HBoxContainer.new()
	bottom.add_child(bar)
	_tabs = TabBar.new()
	_tabs.clip_tabs = false
	for title in TAB_TITLES:
		_tabs.add_tab(title)
	_tabs.tab_changed.connect(_show_tab)
	bar.add_child(_tabs)
	bar.add_child(GDEditorUi.spacer())
	_add_btn = GDEditorUi.tool_button(&"Add", "", func() -> void: commands.add_item(TAB_KINDS[_tabs.current_tab]))
	bar.add_child(_add_btn)
	var empties: Array[Control] = [
		GDEditorUi.empty_state("还没有实例", "把左侧原型拖进 3D 视口或平面图。"),
		_quiet_empty_state("还没有路径", "新建路径", func() -> void: commands.add_item(Kind.PATH)),
		_quiet_empty_state("还没有相机", "记录主相机", func() -> void: commands.add_item(Kind.CAMERA)),
	]
	for i in range(TAB_KINDS.size()):
		var kind := TAB_KINDS[i]
		var list := GDLibraryList.new("", "搜索名称或 ID")
		list.header.visible = false
		list.set_detail_width(64)
		list.set_empty_state(empties[i])
		list.item_selected.connect(func(key: Variant) -> void: _pick(kind, int(key)))
		list.context_requested.connect(func(key: Variant) -> void: commands.item_menu(kind if key != null else Kind.NONE, int(key) if key != null else 0))
		list.delete_requested.connect(func(key: Variant) -> void: commands.delete_item(kind, int(key)))
		list.rename_requested.connect(func(key: Variant) -> void: commands.rename_item(kind, int(key)))
		list.duplicate_requested.connect(func(key: Variant) -> void: commands.duplicate_item(kind, int(key)))
		bottom.add_child(list)
		_lists.append(list)

	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var top := GDEditorUi.pane(_plan, 0)
	var below := GDEditorUi.pane(bottom)
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.size_flags_stretch_ratio = 1.4
	below.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(top)
	split.add_child(below)
	_remember_split(split, "GDLevelPage.plan", 0)
	return split


## 页面上只留一个强调色按钮（原型列表的“新建原型”），这里用普通按钮。
static func _quiet_empty_state(title: String, action_text: String, on_action: Callable) -> Control:
	var state := GDEditorUi.empty_state(title)
	var action := GDEditorUi.text_button(action_text, on_action)
	action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	state.get_child(0).add_child(action)
	return state


func activate() -> void:
	if not _opened_default and doc == null:
		_opened_default = true
		set_layout(GDSampleFactory.load_level_scene())
	if doc != null and GDLevelSceneDrop.pull_transforms_from_scene(layout):
		doc.commit("同步场景位姿")
	else:
		_refresh()


func set_layout(new_layout: GDLevelSceneRes) -> void:
	GDLevelSceneDrop.cancel()
	if doc != null:
		_pull_scene(doc)
	_clear_selection()
	var assigned_identity := new_layout != null and new_layout.layout_id.is_empty()
	GDLevelSceneDrop.ensure_layout_identity(new_layout)
	GDLevelSceneDrop.register_layout(new_layout)
	# 场景绑定属于文档身份，先建立再记录初始快照，避免撤销把工作区解绑。
	var scene_setup: Dictionary = {}
	var migrated := false
	if new_layout != null:
		var types_doc := _shared_document(GDLevelLibraries.catalog())
		var types_before := GDDocument.capture(types_doc.resource)
		migrated = GDLevelLibraries.prepare(new_layout, _last_library)
		if GDDocument.capture(types_doc.resource) != types_before:
			types_doc.commit("合并旧关卡类型")
		_last_library = new_layout.archetype_library
		var shared := _shared_document(_last_library)
		if migrated and _last_library.resource_path.is_empty():
			shared.mark_unsaved()
		if not _docs.has(new_layout):
			_docs[new_layout] = GDDocument.new(new_layout, [new_layout.archetype_library, types_doc.resource])
	if new_layout != null and Engine.is_editor_hint():
		scene_setup = GDLevelEditScene.ensure_scene(new_layout)
	open_document(new_layout)
	_history_doc = doc
	if new_layout != null:
		if migrated or (assigned_identity and not new_layout.resource_path.is_empty()) or bool(scene_setup.get("binding_changed", false)):
			doc.mark_unsaved()
		new_layout.editor_reconcile_next_ids_after_load()
		doc.on_restored = func() -> void:
			var restored_doc: GDDocument = _docs[new_layout]
			restored_doc.snapshot_exclusions = [new_layout.archetype_library, GDLevelLibraries.catalog()]
			GDLevelSceneDrop.reconcile_scene(new_layout)
	_refresh()
	_plan.fit_all()
	if new_layout != null and Engine.is_editor_hint():
		_open_layout_scene.call_deferred(new_layout)


## 关卡数据可以浏览；场景对象只允许在本关卡的编辑场景中修改。
func can_edit_scene() -> bool:
	return GDLevelSceneDrop.is_bound_to_scene(layout, GDLevelSceneDrop.edited_root())


func require_edit_scene() -> bool:
	if can_edit_scene():
		return true
	say("请先进入此关卡的编辑场景，再选择或编辑实例。", &"warn")
	return false


func open_edit_scene() -> void:
	if layout != null:
		_open_layout_scene.call_deferred(layout)


func _open_layout_scene(target: GDLevelSceneRes) -> void:
	if layout != target or not Engine.is_editor_hint() or _opening_scene:
		return
	# 重开已经处于前台的场景前，先保留视口中的未提交位姿。
	_pull_scene(doc)
	_opening_scene = true
	var result := GDLevelEditScene.open_scene(target)
	_opening_scene = false
	if not bool(result.get("ok", false)):
		say(str(result.get("error", "无法打开编辑场景")), &"danger")
		_refresh()
		return
	if bool(result.get("binding_changed", false)):
		doc.mark_unsaved()
	_finish_open_scene.call_deferred(target)


func _finish_open_scene(target: GDLevelSceneRes) -> void:
	if layout != target:
		return
	if not can_edit_scene():
		say("编辑场景尚未激活，请点击“进入编辑场景”重试。", &"warn")
		return
	GDLevelSceneDrop.reconcile_scene(target)
	on_scene_changed()


func on_scene_changed() -> void:
	GDLevelSceneDrop.cancel()
	if not can_edit_scene():
		_clear_selection()
	_refresh()


func _step_history(back: bool) -> void:
	var target := _history_doc if _history_doc != null else doc
	if target == null or (target == doc and not require_edit_scene()):
		return
	if back:
		target.undo()
	else:
		target.redo()
	_refresh()


func get_current_layout() -> GDLevelSceneRes:
	return layout


func select_placement(id: int) -> void:
	select_item(Kind.PLACEMENT, id)


func select_archetype(archetype: GDArchetypeRes) -> void:
	_archetype = archetype
	_inspect_archetype = archetype != null
	_history_doc = library_doc if archetype != null else doc
	_sync_chrome()
	_refresh_selection()


func select_item(kind: Kind, id: int) -> void:
	if kind != Kind.NONE and not require_edit_scene():
		_clear_selection()
		_refresh_selection()
		return
	_kind = kind
	_history_doc = doc
	_sync_chrome()
	_id = id
	_archetype = null
	_inspect_archetype = false
	_probe = null
	if kind != Kind.NONE and TAB_KINDS[_tabs.current_tab] != kind:
		_tabs.current_tab = TAB_KINDS.find(kind)
	_refresh_selection()


## 选中的实例 ID；没有选中实例时为 0。
func selected_placement() -> int:
	return _id if _kind == Kind.PLACEMENT and can_edit_scene() else 0


func cli_context(command: String) -> PackedStringArray:
	var args := PackedStringArray()
	if layout == null or not command.get_slice(".", 0) in ["keywords", "layout", "scaffold", "sceneeditor"]:
		return args
	if is_file(layout):
		args.append_array(["--layout", layout.resource_path])
	if is_file(layout.placement_archetype_type_keywords):
		args.append_array(["--catalog", layout.placement_archetype_type_keywords.resource_path])
	return args


func _suggest_save_path(resource: Resource) -> String:
	if resource is GDLevelLibraryRes or resource is GDKeywordCatalogRes:
		return GDLevelLibraries.save_path(resource)
	return "%s/%s.tres" % [LEVEL_DIR, resource.resource_name] if not resource.resource_name.is_empty() else ""


## The page save hook runs before the dirty check, including Save All and Run.
func prepare_save(target: GDDocument) -> void:
	_pull_scene(target)


func _pull_scene(target: GDDocument, scene_root: Node = null) -> void:
	if not target.resource is GDLevelSceneRes:
		return
	if GDLevelSceneDrop.pull_transforms_from_scene(target.resource as GDLevelSceneRes, scene_root):
		target.commit("同步场景位姿")


func _shared_document(resource: Resource) -> GDDocument:
	if not _docs.has(resource):
		var shared := GDDocument.new(resource)
		_docs[resource] = shared
		shared.changed.connect(_refresh)
		shared.state_changed.connect(_sync_chrome)
		shared.on_restored = func() -> void:
			for candidate: Resource in _docs:
				if candidate is GDLevelSceneRes:
					GDLevelSceneDrop.reconcile_scene(candidate)
		if resource is GDLevelLibraryRes:
			shared.can_restore = func(snapshot: Dictionary) -> bool:
				var restored: Array = snapshot[resource][&"archetypes"]
				for archetype: GDArchetypeRes in resource.archetypes:
					if archetype != null and not restored.has(archetype) and not archetype_users(archetype).is_empty():
						say("无法撤销：此操作会移除其他关卡仍在使用的原型，请先移除对应实例。", &"warn")
						return false
				return true
		if resource.resource_path.is_empty():
			shared.mark_unsaved()
	return _docs[resource]


func commit_library(label: String, merge: bool = false) -> void:
	if library_doc != null:
		_history_doc = library_doc
		library_doc.commit(label, merge)


func edit_global_types() -> void:
	var target := _shared_document(GDLevelLibraries.catalog())
	_history_doc = target
	var dialog := GDKeywordCatalogDialog.open(self, target.resource, func(label: String) -> void:
		_history_doc = target
		target.commit(label)
	)
	dialog.title = "全局原型类型（所有关卡与原型库共用）"
	target.changed.connect(dialog.refresh_colors)
	_sync_chrome()


func bind_library(selected: GDLevelLibraryRes) -> bool:
	if layout == null or selected == null:
		return false
	# 实例只记录 stable_id，换库必须验证对象身份，不能把同号的另一原型当作原件。
	for inst in layout.placements:
		if inst != null and not selected.archetypes.has(layout.find_archetype_by_stable_id(inst.archetype_stable_id)):
			say("此关卡仍有实例引用当前库；请先移除这些实例，再切换原型库。", &"warn")
			return false
	_shared_document(selected)
	layout.archetype_library = selected
	_last_library = selected
	doc.snapshot_exclusions = [selected, GDLevelLibraries.catalog()]
	_clear_selection()
	_history_doc = doc
	doc.commit("选择原型库")
	return true


func new_library() -> void:
	GDDialogs.prompt(self, "新建原型库", "库名称", "新原型库", func(value: String) -> void:
		var created := GDLevelLibraryRes.new()
		created.display_name = value
		created.resource_name = "PlacementLibrary_%s_%08x" % [value.validate_filename(), randi()]
		bind_library(created)
	, func(value: String) -> String: return "库名称不能为空" if value.is_empty() else "")


func open_library() -> void:
	GDDialogs.open_file(self, "打开共享原型库", PackedStringArray(["*.tres ; 原型库"]), func(path: String) -> void:
		var selected := load(path) as GDLevelLibraryRes
		if selected == null:
			say("请选择 GDLevelLibraryRes 原型库资源。", &"warn")
		else:
			bind_library(selected)
	)


func choose_library() -> void:
	var libraries: Array[GDLevelLibraryRes] = GDLevelLibraries.scan_libraries()
	for resource: Resource in _docs:
		if resource is GDLevelLibraryRes and not libraries.has(resource):
			libraries.append(resource)
	var items: Array = []
	for index in range(libraries.size()):
		items.append(["%s · %d 个原型" % [libraries[index].display_name, libraries[index].archetypes.size()], index])
	if items.is_empty():
		new_library()
		return
	GDDialogs.form(self, "选择共享原型库", [{"key": "library", "label": "原型库", "value": maxi(0, libraries.find(library)), "items": items}], func(values: Dictionary) -> void:
		bind_library(libraries[int(values.library)])
	)


## 共享原型删除前检查磁盘关卡及尚未保存的关卡，避免跨关卡悬空引用。
func archetype_users(archetype: GDArchetypeRes) -> PackedStringArray:
	var levels := GDLevelAssetPicker.scan_levels()
	for resource: Resource in _docs:
		if resource is GDLevelSceneRes and not levels.has(resource):
			levels.append(resource)
	var users := PackedStringArray()
	for level in levels:
		if level.archetypes.has(archetype) and level.editor_count_placements_by_archetype_stable_id(archetype.stable_id) > 0:
			users.append(doc_title(level))
	return users


func _save_shared() -> Error:
	# 类型先保存，再保存库（含外部原型），最后由调用者保存关卡的引用。
	for kind in [0, 1]:
		for resource: Resource in _docs:
			if (kind == 0 and not resource is GDKeywordCatalogRes) or (kind == 1 and not resource is GDLevelLibraryRes):
				continue
			var target: GDDocument = _docs[resource]
			if not target.dirty and not resource.resource_path.is_empty():
				continue
			var err := GDLevelLibraries.save_external_children(resource)
			if err == OK:
				err = target.save(_suggest_save_path(resource) if resource.resource_path.is_empty() else "")
			if err != OK:
				say("保存共享资产失败：%s（%s）" % [doc_title(resource), error_string(err)], &"danger")
				return err
	var saved_actors := {}
	for resource: Resource in _docs:
		if not resource is GDLevelSceneRes:
			continue
		for inst in resource.placements:
			if inst == null or inst.actor_reference == null:
				continue
			var actor_library: GDActorLibraryRes = inst.actor_reference.library
			if actor_library == null or saved_actors.has(actor_library):
				continue
			var err := GDLevelLibraries.save_external_children(actor_library)
			if err == OK:
				err = GDDocument.new(actor_library).save()
			if err != OK:
				say("请先保存生成点引用的演员库：%s" % actor_library.display_name, &"danger")
				return err
			saved_actors[actor_library] = true
	return OK


func _save(target: GDDocument) -> void:
	prepare_save(target)
	if _save_shared() == OK:
		super._save(target)


func _save_as(target: GDDocument, path: String, allow_overwrite: bool = false) -> Error:
	prepare_save(target)
	var err := _save_shared()
	return super._save_as(target, path, allow_overwrite) if err == OK else err


func _sync_chrome() -> void:
	super._sync_chrome()
	var target := _history_doc if _history_doc != null else doc
	if target != null:
		_undo_btn.disabled = not target.can_undo
		_redo_btn.disabled = not target.can_redo
		_undo_btn.tooltip_text = "撤销：%s" % target.undo_label
		_redo_btn.tooltip_text = "重做：%s" % target.redo_label
	if doc != null:
		_doc_label.text = "%s%s" % [doc_title(doc.resource), "  ●" if is_dirty() else ""]


func capture_scene(scene_root: Node) -> void:
	for candidate: GDDocument in _docs.values():
		if GDLevelSceneDrop.is_bound_to_scene(candidate.resource as GDLevelSceneRes, scene_root):
			_pull_scene(candidate, scene_root)


func _on_scene_bound(bound_layout: GDLevelSceneRes) -> void:
	var candidate: GDDocument = _docs.get(bound_layout)
	if candidate != null:
		candidate.commit("绑定关卡场景")


# ── 查询 ──

func find_placement(id: int) -> GDPlacementData.PlacementInstance:
	return layout.editor_try_get_placement(id).get("inst") if layout != null else null


func find_path(id: int) -> GDPathSystem.PathInstance:
	return layout.editor_try_get_path(id).get("path") if layout != null else null


func find_pose(index: int) -> GDCameraPoseSystem.CameraPose:
	return layout.editor_try_get_camera_pose(index).get("pose") if layout != null else null


func placement_title(inst: GDPlacementData.PlacementInstance) -> String:
	if inst == null:
		return ""
	return GDPlacementData.PlacementInstanceIdRangeLogic.resolve_display_name(inst, layout.find_archetype_by_stable_id(inst.archetype_stable_id))


static func path_title(path: GDPathSystem.PathInstance) -> String:
	if not path.display_name.is_empty():
		return path.display_name
	return path.path_name if not path.path_name.is_empty() else "路径 #%d" % path.path_id


## 原型和实例均跟随全局类型颜色，不受原型 ID 或编辑器主题影响。
func archetype_color(stable_id: int) -> Color:
	var archetype := layout.find_archetype_by_stable_id(stable_id) if layout != null else null
	var catalog: Resource = layout.placement_archetype_type_keywords if layout != null else null
	return GDEditorUi.type_color(catalog, archetype.archetype_type_stable_id if archetype != null else 0)


## 能被命令行按路径加载的独立资源文件。
static func is_file(resource: Resource) -> bool:
	return resource != null and resource.resource_path.begins_with("res://") and not resource.resource_path.contains("::")


func view_center() -> Vector2:
	return _plan.view_center()


func fit_plan() -> void:
	_plan.fit_all()


## 路径采样预览点；null 表示隐藏。不进撤销栈。
func set_probe(xz: Variant) -> void:
	_probe = xz
	_plan.probe = xz
	_plan.queue_redraw()


func has_probe() -> bool:
	return _probe != null


func _placement_ids() -> Array[int]:
	var ids: Array[int] = []
	if layout != null:
		for inst in layout.placements:
			if inst != null:
				ids.append(inst.instance_id)
	return ids


# ── 刷新 ──

func _refresh() -> void:
	_validate_selection()
	var editable := can_edit_scene()
	_plan.editable = editable
	_add_btn.disabled = not editable
	_scene_hint.visible = layout != null and not editable
	for list in _lists:
		list.modulate.a = 1.0 if editable else 0.55
	_seen_ids = _placement_ids()
	if _library_label != null:
		_library_label.text = "未选择原型库" if library == null else library.display_name
		_library_label.tooltip_text = "" if library == null else library.resource_path
	_refresh_archetypes()
	_refresh_lists()
	_refresh_selection()
	_sync_chrome()


func _validate_selection() -> void:
	if layout == null:
		_clear_selection()
		return
	if not can_edit_scene():
		_kind = Kind.NONE
		_id = 0
		_probe = null
	if _archetype != null and not layout.archetypes.has(_archetype):
		_archetype = null
	_inspect_archetype = _inspect_archetype and _archetype != null
	var exists := false
	match _kind:
		Kind.PLACEMENT:
			exists = find_placement(_id) != null
		Kind.PATH:
			exists = find_path(_id) != null
		Kind.CAMERA:
			exists = find_pose(_id) != null
	if not exists:
		_kind = Kind.NONE
		_probe = null


func _refresh_selection() -> void:
	_archetype_list.select_key(_archetype)
	for i in range(_lists.size()):
		_lists[i].select_key(_id if _kind == TAB_KINDS[i] else null)
	_refresh_plan()
	if layout == null:
		_inspector.show_nothing()
	elif _inspect_archetype:
		_inspector.show_archetype(_archetype)
	else:
		match _kind:
			Kind.PLACEMENT:
				_inspector.show_placement(_id)
			Kind.PATH:
				_inspector.show_path(_id)
			Kind.CAMERA:
				_inspector.show_camera(_id)
			_:
				_inspector.show_level()


func _refresh_archetypes() -> void:
	if layout == null:
		_archetype_list.set_empty_state(GDEditorUi.empty_state("没有打开关卡", "", "打开关卡", commands.open_level))
		_archetype_list.set_items([])
		return
	_archetype_list.set_empty_state(GDEditorUi.empty_state("还没有原型", "原型是可以反复摆放的建筑或物件。", "新建原型", commands.new_archetype))
	var groups := {}
	for archetype: GDArchetypeRes in layout.archetypes:
		if archetype != null:
			groups.get_or_add(archetype.archetype_type_stable_id, []).append(_archetype_row(archetype))
	var ordered: Array = []
	for item: Array in GDArchetypeInspector.type_items(layout.placement_archetype_type_keywords):
		if groups.has(item[1]):
			ordered.append({"key": item[1], "title": item[0], "items": groups[item[1]]})
			groups.erase(item[1])
	for type_id: int in groups:
		ordered.append({"key": type_id, "title": "类型 %d" % type_id, "items": groups[type_id]})
	_archetype_list.set_items(ordered)


func _archetype_row(archetype: GDArchetypeRes) -> Dictionary:
	var uses := layout.editor_count_placements_by_archetype_stable_id(archetype.stable_id)
	var row := {
		"key": archetype,
		"text": archetype.display_name if not archetype.display_name.is_empty() else archetype.resource_name,
		"detail": "#%d" % archetype.stable_id,
		"color": archetype_color(archetype.stable_id),
		"tooltip": "%d 个实例 · 拖进视口摆放，双击放到视口中心" % uses,
	}
	if archetype.is_override_archetype:
		var base := archetype.override_base_archetype
		row["tooltip"] = "变体，复写自 %s\n%s" % [base.display_name if base != null else "（丢失）", row["tooltip"]]
		if base == null:
			row["tone"] = &"danger"
	return row


func _refresh_lists() -> void:
	var rows: Array = [[], [], []]
	if layout != null:
		for inst in layout.placements:
			if inst != null:
				var archetype := layout.find_archetype_by_stable_id(inst.archetype_stable_id)
				var title := placement_title(inst)
				# 默认显示名已经带着 ID，就不在右边重复一遍。
				var row := {"key": inst.instance_id, "text": title, "detail": "" if title.contains(str(inst.instance_id)) else "#%d" % inst.instance_id,
					"color": archetype_color(inst.archetype_stable_id), "tooltip": archetype.display_name if archetype != null else "原型丢失"}
				if archetype == null:
					row["tone"] = &"danger"
				rows[0].append(row)
		for path in layout.paths:
			if path != null:
				rows[1].append({"key": path.path_id, "text": path_title(path), "detail": "#%d" % path.path_id,
					"tooltip": "%d 个节点%s" % [path.knot_count, " · 闭环" if path.closed else ""]})
		for i in range(layout.camera_poses.size()):
			var pose: GDCameraPoseSystem.CameraPose = layout.camera_poses[i]
			rows[2].append({"key": i, "text": pose.display_name if not pose.display_name.is_empty() else pose.pose_name,
				"detail": "正交" if pose.projection == GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC else "透视", "tooltip": pose.pose_name})
	for i in range(_lists.size()):
		_lists[i].set_items([{"title": "", "items": rows[i]}])
		_tabs.set_tab_title(i, TAB_TITLES[i] if rows[i].is_empty() else "%s  %d" % [TAB_TITLES[i], rows[i].size()])


func _refresh_plan() -> void:
	var marks: Array[GDPlanView.Mark] = []
	var lines: Array[GDPlanView.PathLine] = []
	var cameras: Array[GDPlanView.CameraMark] = []
	if layout != null:
		for inst in layout.placements:
			if inst != null:
				marks.append(GDPlanView.Mark.new(inst.instance_id, Vector2(inst.position.x, inst.position.z),
					archetype_color(inst.archetype_stable_id), placement_title(inst), _kind == Kind.PLACEMENT and _id == inst.instance_id))
		for path in layout.paths:
			if path != null:
				lines.append(_path_line(path))
		for i in range(layout.camera_poses.size()):
			cameras.append(_camera_mark(i, layout.camera_poses[i]))
	_plan.probe = _probe
	_plan.set_data(marks, lines, cameras)


func _path_line(path: GDPathSystem.PathInstance) -> GDPlanView.PathLine:
	var line := GDPlanView.PathLine.new()
	line.id = path.path_id
	line.label = path_title(path)
	line.selected = _kind == Kind.PATH and _id == path.path_id
	for knot in path.spline.knots:
		line.knots.append(Vector2(knot.position.x, knot.position.z))
	if path.knot_count >= 2:
		for point in path.spline.to_curve3d().tessellate(4, 2.0):
			line.curve.append(Vector2(point.x, point.z))
	return line


func _camera_mark(index: int, pose: GDCameraPoseSystem.CameraPose) -> GDPlanView.CameraMark:
	var mark := GDPlanView.CameraMark.new()
	mark.index = index
	mark.xz = Vector2(pose.position.x, pose.position.z)
	var forward := Basis.from_euler(pose.euler_angles * (PI / 180.0)) * Vector3.FORWARD
	mark.facing = Vector2(forward.x, forward.z)
	mark.label = pose.display_name if not pose.display_name.is_empty() else pose.pose_name
	mark.selected = _kind == Kind.CAMERA and _id == index
	if mark.selected and pose.has_bound and not pose.has_bound_edges and pose.bound_plane == GDCameraPoseSystem.CameraBoundPlane.XZ:
		var half := pose.bound_half_extents
		for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
			mark.bound.append(pose.bound_center + corner.rotated(-deg_to_rad(pose.bound_yaw_deg)))
	return mark


# ── 选中 ──

## 用户点选：实例同时在编辑器里选中对应节点。
func _pick(kind: Kind, id: int) -> void:
	select_item(kind, id)
	if kind == Kind.PLACEMENT and selected_placement() == id:
		GDLevelSceneDrop.focus_instance(id, layout)


func _clear_selection() -> void:
	_kind = Kind.NONE
	_id = 0
	_archetype = null
	_inspect_archetype = false
	_probe = null


func _show_tab(index: int) -> void:
	for i in range(_lists.size()):
		_lists[i].visible = i == index
	_add_btn.visible = TAB_KINDS[index] != Kind.PLACEMENT
	_add_btn.tooltip_text = "新建路径" if TAB_KINDS[index] == Kind.PATH else "记录主相机"


static func _kind_of(plan_kind: StringName) -> Kind:
	match plan_kind:
		GDPlanView.MARK:
			return Kind.PLACEMENT
		GDPlanView.PATH:
			return Kind.PATH
		GDPlanView.CAMERA:
			return Kind.CAMERA
	return Kind.NONE


# ── 平面图 ──

func _on_plan_picked(kind: StringName, key: int) -> void:
	if kind.is_empty():
		_clear_selection()
		_refresh_selection()
	else:
		_pick(_kind_of(kind), key)


## 拖动时只改模型和场景节点，松手时才提交，撤销栈里只有一步。
func _on_plan_moved(kind: StringName, key: int, index: int, xz: Vector2) -> void:
	if not require_edit_scene():
		return
	if kind == GDPlanView.MARK:
		var inst := find_placement(key)
		var pos := Vector3(xz.x, inst.position.y, xz.y)
		layout.editor_replace_placement(key, inst.with_transform(pos, inst.euler_angles, inst.scale))
		GDLevelSceneDrop.apply_transform(key, pos, inst.euler_angles, inst.scale, layout)
	else:
		var knot_y: float = find_path(key).spline.knots[index].position.y
		GDLevelInspector.set_knot(layout, key, index, &"position", Vector3(xz.x, knot_y, xz.y))
	_refresh_plan()
	_form.sync()


func _on_plan_dropped(data: Variant, xz: Vector2) -> void:
	GDLevelSceneDrop.finish_without_placing()
	var archetype := layout.find_archetype_by_stable_id(int(data.get("stable_id", 0))) if layout != null else null
	if archetype != null:
		_place(archetype, Vector3(xz.x, 0.0, xz.y), data.get("actor_reference") if GDLevelSceneDrop.is_actor_payload(data) else null)


# ── 摆放 ──

func place_at_view(archetype: GDArchetypeRes) -> void:
	_place(archetype, GDLevelSceneDrop.suggest_drop_point())


func _place(archetype: GDArchetypeRes, point: Vector3, actor_reference: GDActorReferenceRes = null) -> void:
	if not require_edit_scene():
		return
	var target := layout
	GDLevelSceneDrop.request_scene_binding(target, func() -> void:
		if layout != target:
			return
		var result := GDLevelSceneDrop.place_archetype(target, archetype, point, null, actor_reference)
		if not bool(result.get("ok", false)):
			say(str(result.get("error", "摆放失败")), &"warn")
			return
		_commit_if_placed()
		select_item(Kind.PLACEMENT, int(result["instance_id"]))
	)


## 视口拖放、编辑器里的撤销 / 重做都会改关卡；实例变了就记一步，让撤销栈和场景保持一致。
func _on_drop_status(text: String, refresh: bool) -> void:
	if not text.is_empty():
		say(text)
	if refresh:
		_commit_if_placed()


func _commit_if_placed() -> void:
	if doc != null and _placement_ids() != _seen_ids:
		doc.commit("摆放原型")


func _sync_to_scene() -> void:
	if layout != null:
		var target := layout
		GDLevelSceneDrop.request_scene_binding(target, func() -> void:
			if layout != target:
				return
			var result := GDLevelSceneDrop.sync_layout_to_scene(target)
			say(str(result.get("message", "")), &"ok" if bool(result.get("ok", false)) else &"warn")
		)
