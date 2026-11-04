@tool
class_name GDActorEditorWindow
extends VBoxContainer

## 演员编辑器主界面与向导弹窗（对应 ActorEditorWindow + ActorLibraryCreatorWindow + ActorArchetypeCreatorWindow + Duplicate/Rename/Override 弹窗）
## 两栏布局：
##   左栏：演员原型目录（按类型分组折叠、响应式卡片网格、Variant 角标与复写目标切换、右键菜单 [定位/重命名/复制原型/新建 Override 实例/删除原型]）
##   右栏：内嵌 ActorArchetypeSOEditor（演员原型类型分类、Override 复写块、实例/预览 Address、交互式 3D/2D 外观预览、原子块、自定义属性块）

var _library: GDActorLibraryRes = null
var _archetype_catalog: Array[GDActorLibraryRes.ActorArchetypeRes] = []
var _archetype_type_catalog: GDKeywordCatalogSystem.KeywordCatalogRes = null
var _selected_archetype: GDActorLibraryRes.ActorArchetypeRes = null
var _type_group_foldouts: Dictionary = {} # int -> bool

# UI 引用
var _library_label: Label = null
var _catalog_title: Label = null
var _catalog_query: String = ""
var _catalog_box: VBoxContainer = null
var _properties_box: VBoxContainer = null
var _preview_panel: GDArchetypePreviewPanel = null
var _type_edit_popup: GDLevelEditorPopups.TypeEditPopup = null
var _lib_creator_win: ActorLibraryCreatorDialog = null
var _arch_creator_win: ActorArchetypeCreatorDialog = null

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()

func set_library(library: GDActorLibraryRes) -> void:
	if _library != library:
		_selected_archetype = null
	_library = library
	_archetype_type_catalog = library.actor_type_keywords if library != null else null
	refresh_archetype_catalog_from_library()

func get_current_library() -> GDActorLibraryRes:
	return _library

func get_selected_archetype() -> GDActorLibraryRes.ActorArchetypeRes:
	return _selected_archetype

func select_archetype(archetype: GDActorLibraryRes.ActorArchetypeRes) -> void:
	_selected_archetype = archetype
	refresh_ui()

func reload_current_library() -> void:
	if _library != null:
		set_library(_library)
	else:
		refresh_archetype_catalog_from_library()

func refresh_archetype_catalog_from_library() -> void:
	_archetype_catalog.clear()
	if _library != null:
		for so in _library.archetypes:
			if so != null and not _archetype_catalog.has(so):
				_archetype_catalog.append(so)
	_archetype_catalog.sort_custom(func(a: GDActorLibraryRes.ActorArchetypeRes, b: GDActorLibraryRes.ActorArchetypeRes) -> bool:
		return a.stable_id < b.stable_id
	)
	if _selected_archetype != null and not _archetype_catalog.has(_selected_archetype):
		_selected_archetype = null
	refresh_ui()

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	# 顶部工具栏
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	add_child(toolbar)

	var open_lib_btn := Button.new()
	open_lib_btn.text = "打开演员库…"
	open_lib_btn.tooltip_text = "打开已有演员库。当前没有库时会载入通用演员库。"
	open_lib_btn.pressed.connect(_on_open_or_create_demo_library)
	GDEditorUi.style_button(open_lib_btn, "primary")
	toolbar.add_child(open_lib_btn)

	var new_lib_btn := Button.new()
	new_lib_btn.text = "新建演员库"
	new_lib_btn.pressed.connect(_open_library_creator_wizard)
	GDEditorUi.style_button(new_lib_btn, "quiet")
	toolbar.add_child(new_lib_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_library_label = Label.new()
	_library_label.text = "编辑中：(无演员库)"
	GDEditorUi.style_context_label(_library_label)
	toolbar.add_child(_library_label)

	var tools_menu := MenuButton.new()
	tools_menu.text = "工具"
	var popup := tools_menu.get_popup()
	popup.add_item("刷新原型目录", 1)
	popup.add_item("从选中原型新建 Override", 2)
	popup.add_item("创建并绑定类型目录", 3)
	popup.add_item("演员库创建向导", 4)
	popup.id_pressed.connect(_on_tools_menu_pressed)
	GDEditorUi.style_button(tools_menu, "quiet")
	toolbar.add_child(tools_menu)
	GDEditorUi.wrap_toolbar(toolbar)

	# 主体两栏分割
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 360
	split.resized.connect(func() -> void:
		GDEditorUi.ensure_split_usable(split, 260, 280)
	)
	add_child(split)

	# 左栏：演员原型目录
	var left_panel := PanelContainer.new()
	left_panel.clip_contents = true
	left_panel.custom_minimum_size.x = 260
	GDEditorUi.apply_panel(left_panel, 10)
	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)
	split.add_child(left_panel)

	_catalog_title = GDEditorUi.section_title("演员")
	left_vbox.add_child(_catalog_title)

	var cat_tools := HBoxContainer.new()
	cat_tools.add_theme_constant_override("separation", 6)
	var edit_type_btn := Button.new()
	edit_type_btn.text = "类型"
	edit_type_btn.tooltip_text = "编辑演员类型分组"
	edit_type_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_type_btn.pressed.connect(_open_type_edit_popup)
	GDEditorUi.style_button(edit_type_btn, "quiet")
	cat_tools.add_child(edit_type_btn)

	var add_arch_btn := Button.new()
	add_arch_btn.text = "+ 演员"
	add_arch_btn.tooltip_text = "新建一个演员原型"
	add_arch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_arch_btn.pressed.connect(_open_archetype_creator_wizard)
	GDEditorUi.style_button(add_arch_btn, "primary")
	cat_tools.add_child(add_arch_btn)

	var ref_btn := Button.new()
	ref_btn.text = "刷新"
	ref_btn.tooltip_text = "重新读取当前演员库登记的原型"
	ref_btn.pressed.connect(refresh_archetype_catalog_from_library)
	GDEditorUi.style_button(ref_btn, "quiet")
	cat_tools.add_child(ref_btn)
	left_vbox.add_child(cat_tools)

	var cat_search := GDEditorUi.search_field("搜索演员名称或 ID")
	cat_search.text_changed.connect(func(t: String) -> void:
		_catalog_query = t
		_rebuild_catalog_pane()
	)
	left_vbox.add_child(cat_search)

	var cat_scroll := ScrollContainer.new()
	cat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(cat_scroll)

	_catalog_box = VBoxContainer.new()
	_catalog_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_box.add_theme_constant_override("separation", 6)
	cat_scroll.add_child(_catalog_box)
	GDEditorUi.configure_vertical_scroll(cat_scroll, _catalog_box)

	# 右栏：属性 Inspector
	var right_panel := PanelContainer.new()
	right_panel.clip_contents = true
	right_panel.custom_minimum_size.x = 280
	GDEditorUi.apply_panel(right_panel, 10)
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(right_vbox)
	split.add_child(right_panel)

	right_vbox.add_child(GDEditorUi.section_title("属性"))

	var prop_scroll := ScrollContainer.new()
	prop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(prop_scroll)

	_properties_box = VBoxContainer.new()
	_properties_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_properties_box.add_theme_constant_override("separation", 6)
	prop_scroll.add_child(_properties_box)
	GDEditorUi.configure_vertical_scroll(prop_scroll, _properties_box)

	refresh_ui()

func refresh_ui() -> void:
	if _library_label == null:
		return
	var lib_label := "(无演员库)"
	if _library != null:
		lib_label = _library.display_name if not _library.display_name.is_empty() else (
			_library.resource_name if not _library.resource_name.is_empty() else "ActorLibrary"
		)
	_library_label.text = "编辑中：" + lib_label
	_rebuild_catalog_pane()
	_rebuild_properties_pane()

func _rebuild_catalog_pane() -> void:
	GDEditorUi.clear_children(_catalog_box)
	if _catalog_title != null:
		_catalog_title.text = "演员    %d" % _archetype_catalog.size()

	if _library == null:
		_catalog_box.add_child(GDEditorUi.empty_state("先打开演员库", [
			"点左上角「打开演员库…」。",
			"或者「新建演员库」，按向导建一份。",
			"库准备好之后，再用「+ 演员」加原型。",
		]))
		return

	if _archetype_catalog.is_empty():
		_catalog_box.add_child(GDEditorUi.empty_state("库里还没有演员", [
			"点「+ 演员」新建一个原型。",
			"点「刷新」重新读取库里已有的原型。",
			"点卡片后，在右侧改类型和外观。",
		]))
		return

	# 按类型分组
	var groups: Dictionary = {}
	for a in _archetype_catalog:
		if a == null:
			continue
		var t := a.archetype_type_stable_id
		if not groups.has(t):
			groups[t] = []
		groups[t].append(a)

	var ordered_type_ids: Array[int] = []
	if _archetype_type_catalog != null:
		for e in _archetype_type_catalog.entries:
			if e != null and not e.deprecated and groups.has(e.stable_id) and not ordered_type_ids.has(e.stable_id):
				ordered_type_ids.append(e.stable_id)
	if groups.has(0) and not ordered_type_ids.has(0):
		ordered_type_ids.append(0)
	for k in groups.keys():
		if not ordered_type_ids.has(int(k)):
			ordered_type_ids.append(int(k))

	var shown := 0
	for tid in ordered_type_ids:
		var list: Array = groups[tid]
		var gname := _resolve_type_name(tid)
		var visible: Array = []
		for arch in list:
			if arch == null:
				continue
			var disp: String = arch.display_name if not arch.display_name.is_empty() else arch.resource_name
			if GDEditorUi.matches_query("%s %d %s" % [disp, arch.stable_id, gname], _catalog_query):
				visible.append(arch)
		if visible.is_empty():
			continue
		shown += visible.size()
		var open: bool = bool(_type_group_foldouts.get(tid, true))

		var fold_btn := GDEditorUi.fold_button(gname, visible.size(), open)
		var cap_tid := tid
		fold_btn.pressed.connect(func() -> void:
			_type_group_foldouts[cap_tid] = not bool(_type_group_foldouts.get(cap_tid, true))
			_rebuild_catalog_pane()
		)
		_catalog_box.add_child(fold_btn)

		if not open:
			continue

		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		_catalog_box.add_child(flow)

		for arch in visible:
			flow.add_child(_create_actor_card(arch))

	if shown == 0:
		_catalog_box.add_child(GDEditorUi.muted("没有匹配「%s」的演员。" % _catalog_query.strip_edges()))
	elif _catalog_title != null and not _catalog_query.strip_edges().is_empty():
		_catalog_title.text = "演员    %d / %d" % [shown, _archetype_catalog.size()]

func _create_actor_card(arch: GDActorLibraryRes.ActorArchetypeRes) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(168, 120)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GDEditorUi.style_card(card, _selected_archetype == arch)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var top_bar := HBoxContainer.new()
	top_bar.add_child(GDEditorUi.swatch(GDEditorUi.hue_color(arch.archetype_type_stable_id)))
	if arch.is_override_archetype:
		var var_menu := MenuButton.new()
		var_menu.text = "Variant"
		var base_a := arch.override_base_archetype
		var_menu.tooltip_text = ("复写自：%s" % (base_a.display_name if base_a != null else "已丢失"))
		var_menu.modulate = Color(1.0, 0.72, 0.25) if base_a != null else Color(0.95, 0.36, 0.32)
		var vp := var_menu.get_popup()
		for i in range(_archetype_catalog.size()):
			var cand := _archetype_catalog[i]
			if cand != null and cand != arch and not GDActorEditorServices.ActorArchetypeOverrideService.would_form_cycle(arch, cand):
				vp.add_item("复写自：%s" % cand.display_name, i)
		vp.id_pressed.connect(func(idx: int) -> void:
			var picked := _archetype_catalog[idx]
			GDActorEditorServices.ActorArchetypeOverrideService.try_rebind_base(arch, picked)
			reload_current_library()
			select_archetype(arch)
		)
		top_bar.add_child(var_menu)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(sp)

	var ctx_menu := MenuButton.new()
	ctx_menu.text = "⋯"
	var p := ctx_menu.get_popup()
	p.add_item("在 Project 中定位", 1)
	p.add_item("重命名", 2)
	p.add_item("复制原型", 3)
	p.add_item("新建 Override 实例", 4)
	p.add_separator()
	p.add_item("删除原型", 5)
	p.id_pressed.connect(func(id: int) -> void:
		_on_actor_card_context_menu(arch, id)
	)
	top_bar.add_child(ctx_menu)
	vbox.add_child(top_bar)

	var sel_btn := Button.new()
	var disp := arch.display_name if not arch.display_name.is_empty() else arch.resource_name
	sel_btn.flat = true
	sel_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	sel_btn.text = disp
	sel_btn.add_theme_font_size_override("font_size", 14)
	sel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_btn.pressed.connect(func() -> void:
		select_archetype(arch)
	)
	vbox.add_child(sel_btn)
	vbox.add_child(GDEditorUi.muted("ID  %d" % arch.stable_id))
	return card

func _on_actor_card_context_menu(arch: GDActorLibraryRes.ActorArchetypeRes, menu_id: int) -> void:
	if _library == null or arch == null:
		return
	match menu_id:
		2: # 重命名
			var mod := GDActorEditorServices.ActorArchetypeAssetPaths.resolve_module_name(_library)
			var stem := GDActorEditorServices.ActorArchetypeAssetPaths.resolve_archetype_stem(arch, mod)
			GDActorEditorServices.ActorArchetypeRenameService.try_rename(
				arch, _library, stem + "_R", arch.display_name + "_改名"
			)
			reload_current_library()
			select_archetype(arch)
		3: # 复制原型
			var defs := GDActorEditorServices.ActorArchetypeDuplicateService.try_build_defaults(arch, _library)
			if bool(defs.get("ok", false)):
				var res := GDActorEditorServices.ActorArchetypeDuplicateService.try_duplicate(
					arch, _library, str(defs["archetype_name"]), str(defs["display_name"])
				)
				if bool(res.get("ok", false)):
					reload_current_library()
					select_archetype(res["created"])
		4: # 新建 Override 实例
			var defs := GDActorEditorServices.ActorArchetypeOverrideService.try_build_defaults(arch, _library)
			if bool(defs.get("ok", false)):
				var res := GDActorEditorServices.ActorArchetypeOverrideService.try_create(
					arch, _library, str(defs["archetype_name"]), str(defs["display_name"])
				)
				if bool(res.get("ok", false)):
					reload_current_library()
					select_archetype(res["created"])
		5: # 删除原型
			_library.editor_remove_archetype(arch)
			if _selected_archetype == arch:
				_selected_archetype = null
			reload_current_library()

func _rebuild_properties_pane() -> void:
	GDEditorUi.clear_children(_properties_box)

	if _selected_archetype == null:
		_properties_box.add_child(GDEditorUi.empty_state("选择一个演员", [
			"在左侧点一张演员卡片。",
			"这里会显示类型、外观和属性。",
			"卡片右上角「⋯」可以复制、改名或删除。",
		]))
		return

	var arch := _selected_archetype
	_properties_box.add_child(GDEditorUi.section_title(arch.display_name if not arch.display_name.is_empty() else arch.resource_name))
	_properties_box.add_child(GDEditorUi.muted("演员 ID  %d" % arch.stable_id))

	# 1. 演员原型类型（分类）
	var type_panel := PanelContainer.new()
	var type_box := VBoxContainer.new()
	type_panel.add_child(type_box)
	_properties_box.add_child(type_panel)

	var tl := Label.new()
	tl.text = "演员原型类型（分类）"
	type_box.add_child(tl)

	if _archetype_type_catalog == null:
		var no_cat := Label.new()
		no_cat.text = "未找到演员类型目录。请点「工具 → 创建并绑定类型目录」。"
		type_box.add_child(no_cat)
	else:
		var type_opt := OptionButton.new()
		type_opt.add_item("（未分类）", 0)
		var sel := 0
		for e in _archetype_type_catalog.entries:
			if e != null and not e.deprecated:
				type_opt.add_item(e.display_name if not e.display_name.is_empty() else e.entry_name, e.stable_id)
				if e.stable_id == arch.archetype_type_stable_id:
					sel = type_opt.item_count - 1
		type_opt.selected = sel
		type_opt.item_selected.connect(func(idx: int) -> void:
			arch.editor_set_archetype_type_stable_id(type_opt.get_item_id(idx))
			refresh_ui()
		)
		type_box.add_child(type_opt)

	# 2. Override 区块
	if arch.is_override_archetype:
		var ov_panel := PanelContainer.new()
		var ov_box := VBoxContainer.new()
		ov_panel.add_child(ov_box)
		_properties_box.add_child(ov_panel)
		var ov_t := Label.new()
		ov_t.text = "复写（Prefab Variant）"
		ov_box.add_child(ov_t)
		var ov_sub := Label.new()
		if arch.override_base_archetype == null:
			ov_sub.text = "⚠ 复写目标已丢失（base 原型被删或被移动）。到目录卡片左上角的 Variant 角标重新指一个。"
			ov_sub.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
		else:
			ov_sub.text = "复写目标：%s\n实例 Prefab 是复写目标实例 Prefab 的 Variant：改这里只落复写，不影响 base。" % arch.override_base_archetype.display_name
		ov_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ov_box.add_child(ov_sub)

	# 3. 显示名与 Prefab 地址
	var disp_row := HBoxContainer.new()
	var disp_lbl := Label.new()
	disp_lbl.text = "显示名"
	disp_lbl.custom_minimum_size.x = 84
	disp_row.add_child(disp_lbl)
	var disp_edit := LineEdit.new()
	disp_edit.text = arch.display_name
	disp_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disp_edit.text_submitted.connect(func(t: String) -> void:
		arch.editor_set_display_name(t)
		refresh_ui()
	)
	disp_row.add_child(disp_edit)
	_properties_box.add_child(disp_row)

	var ent_row := HBoxContainer.new()
	var ent_lbl := Label.new()
	ent_lbl.text = "实例"
	ent_lbl.custom_minimum_size.x = 84
	ent_row.add_child(ent_lbl)
	var ent_edit := LineEdit.new()
	ent_edit.text = arch.manufactured_prefab_address
	ent_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ent_edit.text_submitted.connect(func(t: String) -> void:
		arch.editor_set_prefab_addresses(t.strip_edges(), arch.preview_prefab_address)
		refresh_ui()
	)
	ent_row.add_child(ent_edit)
	_properties_box.add_child(ent_row)

	var prev_row := HBoxContainer.new()
	var prev_lbl := Label.new()
	prev_lbl.text = "预览"
	prev_lbl.custom_minimum_size.x = 84
	prev_row.add_child(prev_lbl)
	var prev_edit := LineEdit.new()
	prev_edit.text = arch.preview_prefab_address
	prev_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_edit.text_submitted.connect(func(t: String) -> void:
		arch.editor_set_prefab_addresses(arch.manufactured_prefab_address, t.strip_edges())
		refresh_ui()
	)
	prev_row.add_child(prev_edit)
	_properties_box.add_child(prev_row)

	# 4. 可交互外观预览面板
	_preview_panel = GDArchetypePreviewPanel.new()
	_properties_box.add_child(_preview_panel)
	_preview_panel.bind_archetype(arch)

	# 5. 自定义属性块
	var empty_bindings: Array[GDEntityAtomSystem.AtomVarTagRegistry.Binding] = []
	GDCoreAtomEditorWidgets.build_custom_attributes_inspector(
		_properties_box,
		arch,
		empty_bindings,
		func() -> void: _rebuild_properties_pane()
	)

func _resolve_type_name(type_stable_id: int) -> String:
	if type_stable_id <= 0:
		return "未分类"
	if _archetype_type_catalog == null:
		return "Type#%d" % type_stable_id
	for e in _archetype_type_catalog.entries:
		if e != null and e.stable_id == type_stable_id:
			return e.display_name if not e.display_name.is_empty() else e.entry_name
	return "Type#%d" % type_stable_id

func _on_tools_menu_pressed(id: int) -> void:
	match id:
		1:
			refresh_archetype_catalog_from_library()
		2:
			if _selected_archetype != null and _library != null:
				_on_actor_card_context_menu(_selected_archetype, 4)
		3:
			_try_create_type_catalog()
		4:
			_open_library_creator_wizard()

func _try_create_type_catalog() -> void:
	if _library == null:
		return
	if _library.actor_type_keywords != null:
		_archetype_type_catalog = _library.actor_type_keywords
		refresh_ui()
		return
	var catalog := GDActorTypeKeywordsRes.new()
	var mod := GDActorEditorServices.ActorArchetypeAssetPaths.resolve_module_name(_library)
	catalog.enum_namespace = "%s.Keywords" % mod
	catalog.enum_type_name = "ActorArchetypeTypeKind"
	catalog.add_entry("Unit", "单位", "")
	catalog.add_entry("Npc", "角色", "")
	_library.editor_set_actor_type_keywords(catalog)
	_archetype_type_catalog = catalog
	refresh_ui()

func _open_type_edit_popup() -> void:
	if _library == null:
		return
	if _archetype_type_catalog == null:
		_try_create_type_catalog()
	if _type_edit_popup == null:
		_type_edit_popup = GDLevelEditorPopups.TypeEditPopup.new()
		add_child(_type_edit_popup)
		_type_edit_popup.catalog_changed.connect(refresh_ui)
	_type_edit_popup.bind_catalog(_archetype_type_catalog)
	_type_edit_popup.popup_centered()

func _on_open_or_create_demo_library() -> void:
	if _library != null:
		return
	set_library(GDSampleFactory.load_actor_library())

func _open_library_creator_wizard() -> void:
	if _lib_creator_win == null:
		_lib_creator_win = ActorLibraryCreatorDialog.new()
		add_child(_lib_creator_win)
		_lib_creator_win.library_created.connect(func(lib: GDActorLibraryRes) -> void:
			set_library(lib)
		)
	_lib_creator_win.popup_centered()

func _open_archetype_creator_wizard() -> void:
	if _library == null:
		_on_open_or_create_demo_library()
	if _arch_creator_win == null:
		_arch_creator_win = ActorArchetypeCreatorDialog.new()
		add_child(_arch_creator_win)
		_arch_creator_win.archetype_created.connect(func(created: GDActorLibraryRes.ActorArchetypeRes) -> void:
			reload_current_library()
			select_archetype(created)
		)
	_arch_creator_win.bind_library(_library)
	_arch_creator_win.popup_centered()


## 演员库创建向导（对应 ActorLibraryCreatorWindow）
class ActorLibraryCreatorDialog extends Window:
	signal library_created(lib: GDActorLibraryRes)

	var _module_edit: LineEdit = null
	var _display_edit: LineEdit = null
	var _root_edit: LineEdit = null
	var _create_type_cb: CheckBox = null
	var _result_label: Label = null

	func _init() -> void:
		title = "演员库创建向导"
		size = Vector2i(440, 320)
		close_requested.connect(hide)
		_build_ui()

	func _build_ui() -> void:
		var root := VBoxContainer.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		root.add_theme_constant_override("separation", 6)
		add_child(root)

		_module_edit = GDCoreAtomEditorWidgets.AtomCreatorWindow._add_labeled_line_edit(root, "模块名", "MyActors")
		_display_edit = GDCoreAtomEditorWidgets.AtomCreatorWindow._add_labeled_line_edit(root, "展示名", "我的演员库")
		_root_edit = GDCoreAtomEditorWidgets.AtomCreatorWindow._add_labeled_line_edit(root, "资源路径", "res://game_res/MyActors")

		_create_type_cb = CheckBox.new()
		_create_type_cb.text = "同时创建类型目录"
		_create_type_cb.button_pressed = true
		root.add_child(_create_type_cb)

		var btn := Button.new()
		btn.text = "创建演员库"
		btn.pressed.connect(_do_create)
		root.add_child(btn)

		_result_label = Label.new()
		_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(_result_label)

	func _do_create() -> void:
		var mod := _module_edit.text.strip_edges()
		if not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(
			mod, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.TYPE_NAME
		):
			_result_label.text = "模块名不合法。"
			return
		var lib := GDActorLibraryRes.new()
		lib.resource_name = "ActorLibrary_%s" % mod
		lib.display_name = _display_edit.text.strip_edges()
		lib.set_meta("virtual_resource_root", _root_edit.text.strip_edges())
		if _create_type_cb.button_pressed:
			var kw := GDActorTypeKeywordsRes.new()
			kw.enum_namespace = "%s.Keywords" % mod
			kw.enum_type_name = "ActorArchetypeTypeKind"
			kw.add_entry("DefaultActor", "默认分类", "")
			lib.editor_set_actor_type_keywords(kw)
		library_created.emit(lib)
		hide()


## 演员原型创建向导（对应 ActorArchetypeCreatorWindow）
class ActorArchetypeCreatorDialog extends Window:
	signal archetype_created(arch: GDActorLibraryRes.ActorArchetypeRes)

	var _library: GDActorLibraryRes = null
	var _name_edit: LineEdit = null
	var _display_edit: LineEdit = null
	var _type_opt: OptionButton = null
	var _err_label: Label = null

	func _init() -> void:
		title = "演员原型创建向导"
		size = Vector2i(420, 300)
		close_requested.connect(hide)
		_build_ui()

	func bind_library(lib: GDActorLibraryRes) -> void:
		_library = lib
		_refresh_types()

	func _build_ui() -> void:
		var root := VBoxContainer.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		root.add_theme_constant_override("separation", 6)
		add_child(root)

		_name_edit = GDCoreAtomEditorWidgets.AtomCreatorWindow._add_labeled_line_edit(root, "名称", "Sample")
		_display_edit = GDCoreAtomEditorWidgets.AtomCreatorWindow._add_labeled_line_edit(root, "显示名", "Sample 演员")

		var t_row := HBoxContainer.new()
		var t_lbl := Label.new()
		t_lbl.text = "演员原型类型"
		t_lbl.custom_minimum_size.x = 110
		t_row.add_child(t_lbl)
		_type_opt = OptionButton.new()
		_type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t_row.add_child(_type_opt)
		root.add_child(t_row)

		var btn := Button.new()
		btn.text = "一键创建 原型 + Entity Prefab"
		btn.custom_minimum_size.y = 34
		btn.pressed.connect(_do_create)
		root.add_child(btn)

		_err_label = Label.new()
		_err_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		root.add_child(_err_label)

	func _refresh_types() -> void:
		if _type_opt == null:
			return
		_type_opt.clear()
		_type_opt.add_item("（未分类 · 0）", 0)
		if _library != null and _library.actor_type_keywords != null:
			for e in _library.actor_type_keywords.entries:
				if e != null and not e.deprecated:
					_type_opt.add_item("%s (%s) · %d" % [e.entry_name, e.display_name, e.stable_id], e.stable_id)

	func _do_create() -> void:
		if _library == null:
			_err_label.text = "未绑定目标演员库。"
			return
		var aname := _name_edit.text.strip_edges()
		if not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(
			aname, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.TYPE_NAME
		):
			_err_label.text = "名称必须是合法 C# 标识符。"
			return
		if GDActorEditorServices.ActorArchetypeAssetPaths.is_archetype_name_taken(_library, aname):
			_err_label.text = "已存在同名原型：%s" % aname
			return

		var mod := GDActorEditorServices.ActorArchetypeAssetPaths.resolve_module_name(_library)
		_library.editor_reconcile_next_ids_after_load()
		var sid := _library.editor_allocate_next_archetype_stable_id()
		var arch := GDActorArchetypeRes.new()
		arch.resource_name = "%s%s_%s" % [GDActorEditorServices.ActorArchetypeAssetPaths.ARCHETYPE_FILE_PREFIX, mod, aname]
		var entity_addr := "%s%s_%s" % [GDActorEditorServices.ActorArchetypeAssetPaths.ENTITY_FILE_PREFIX, mod, aname]
		arch.editor_init_with_addresses(sid, _display_edit.text.strip_edges(), entity_addr, "")
		var tid := _type_opt.get_selected_id()
		if tid > 0:
			arch.editor_set_archetype_type_stable_id(tid)
		_library.editor_add_archetype(arch)
		archetype_created.emit(arch)
		hide()
