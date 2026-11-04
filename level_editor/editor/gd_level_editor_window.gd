@tool
class_name GDLevelEditorWindow
extends VBoxContainer

## 关卡编辑器主界面（对应 TimiMiniGame.SceneEditor.Editor.Scene.LevelEditorWindow）
## 放在独立窗口里，和 Godot 的 3D/2D 视口同时存在。
## 三栏布局：
##   左栏：建筑原型目录（按类型分组、卡片按住拖进视口落点、单击看属性）
##   中栏：属性面板（位姿会写回场景节点；放置模式可把原型拖到替换区）
##   右栏：已摆放实例列表（保存时从场景回写位姿、同步到场景、删除）
##   底栏：可折叠内嵌 CLI 面板（13 条命令 + 快捷按钮 + 历史记录）

enum RightPaneMode {
	NONE = 0,
	PLACEMENT = 1,
	ARCHETYPE = 2,
}

var _layout: GDLevelSceneRes = null
var _archetype_catalog: Array[GDArchetypeRes] = []
var _archetype_type_catalog: GDKeywordCatalogSystem.KeywordCatalogRes = null

var _selected_instance_id: int = 0
var _selected_archetype: GDArchetypeRes = null
var _right_pane_mode: int = RightPaneMode.NONE
var _lock_scale: bool = true
var _ground_opacity: float = 0.45
var _art_scene_loaded: bool = false
var _preview_session_active: bool = false
var _active_runtime_session: GDSceneEditorRuntime.PlacementSession = null

var _cli_panel_open: bool = false
var _cli_history: Array[String] = []
var _type_group_foldouts: Dictionary = {} # int -> bool

# UI 节点引用
var _layout_label: Label = null
var _cli_toggle_btn: Button = null
var _catalog_box: VBoxContainer = null
var _properties_box: VBoxContainer = null
var _placed_list_box: VBoxContainer = null
var _cli_panel: VBoxContainer = null
var _cli_input: LineEdit = null
var _cli_output: TextEdit = null
var _status_bar_label: Label = null
var _catalog_title: Label = null
var _placed_title: Label = null
var _catalog_query: String = ""
var _placed_query: String = ""
var _preview_panel: GDArchetypePreviewPanel = null

var _path_editor_win: GDPathEditorWindow = null
var _camera_pose_win: GDCameraPoseEditorWindow = null
var _type_edit_popup: GDLevelEditorPopups.TypeEditPopup = null
var _reset_id_popup: GDLevelEditorPopups.ResetInstanceIdPopup = null

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()

func set_layout(layout: GDLevelSceneRes) -> void:
	_layout = layout
	if _layout != null:
		_archetype_catalog.clear()
		for a in _layout.archetypes:
			if a != null:
				_archetype_catalog.append(a)
		_archetype_type_catalog = _layout.placement_archetype_type_keywords
	else:
		_archetype_catalog.clear()
		_archetype_type_catalog = null
	_selected_instance_id = 0
	_selected_archetype = null
	_right_pane_mode = RightPaneMode.NONE
	refresh_all()

func get_current_layout() -> GDLevelSceneRes:
	return _layout

func select_placement_for_right_pane(instance_id: int) -> void:
	_right_pane_mode = RightPaneMode.PLACEMENT
	_selected_instance_id = instance_id
	_selected_archetype = null
	refresh_all()

func select_archetype_for_right_pane(archetype: GDArchetypeRes) -> void:
	_right_pane_mode = RightPaneMode.ARCHETYPE
	_selected_instance_id = 0
	_selected_archetype = archetype
	if archetype != null:
		_type_group_foldouts[archetype.archetype_type_stable_id] = true
	refresh_all()

func apply_instance_id_remaps(remaps: Array) -> void:
	if remaps == null or remaps.is_empty():
		refresh_all()
		return
	for r in remaps:
		var old_id := int(r.get("old_id", 0))
		var new_id := int(r.get("new_id", 0))
		if _selected_instance_id == old_id:
			_selected_instance_id = new_id
	refresh_all()

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	# ── 顶部工具栏 ──
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	add_child(toolbar)

	var open_btn := Button.new()
	open_btn.text = "打开"
	open_btn.tooltip_text = "打开已有关卡。当前没有关卡时会载入通用示例关卡。"
	open_btn.pressed.connect(_on_open_or_create_demo_layout)
	GDEditorUi.style_button(open_btn, "primary")
	toolbar.add_child(open_btn)

	var new_layout_btn := Button.new()
	new_layout_btn.text = "新建关卡"
	new_layout_btn.tooltip_text = "在内存里新建一份关卡，并带上两个通用示例原型"
	new_layout_btn.pressed.connect(_create_new_in_memory_layout)
	GDEditorUi.style_button(new_layout_btn, "quiet")
	toolbar.add_child(new_layout_btn)

	var sync_btn := Button.new()
	sync_btn.text = "同步"
	sync_btn.tooltip_text = "把关卡数据里还没有出现在当前场景中的实例生成到 Placements 下"
	sync_btn.pressed.connect(_sync_layout_to_scene)
	GDEditorUi.style_button(sync_btn, "quiet")
	toolbar.add_child(sync_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_layout_label = Label.new()
	_layout_label.text = "编辑中：(无关卡场景)"
	GDEditorUi.style_context_label(_layout_label)
	toolbar.add_child(_layout_label)

	_cli_toggle_btn = Button.new()
	_cli_toggle_btn.text = "CLI"
	_cli_toggle_btn.tooltip_text = "展开或收起本页命令行"
	_cli_toggle_btn.pressed.connect(func() -> void:
		_cli_panel_open = not _cli_panel_open
		_cli_toggle_btn.text = "CLI"
		_cli_panel.visible = _cli_panel_open
	)
	GDEditorUi.style_button(_cli_toggle_btn, "quiet")
	toolbar.add_child(_cli_toggle_btn)

	var tools_menu := MenuButton.new()
	tools_menu.text = GDSceneEditorL10n.l("工具")
	var popup := tools_menu.get_popup()
	popup.add_item("路径编辑器 (Path Editor)", 1)
	popup.add_item("相机配置 (Camera Pose Editor)", 2)
	popup.add_item("导出摆放 CSV (UTF-8 BOM)", 3)
	popup.add_item("迁移关卡场景 ID (Migrate IDs)", 4)
	popup.add_separator()
	popup.add_item("切换语言 中文 / English", 5)
	popup.id_pressed.connect(_on_tools_menu_id_pressed)
	GDEditorUi.style_button(tools_menu, "quiet")
	toolbar.add_child(tools_menu)
	GDEditorUi.wrap_toolbar(toolbar)

	# ── 主体三栏分割 ──
	var main_split := HSplitContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.split_offset = 300
	main_split.resized.connect(func() -> void:
		GDEditorUi.ensure_split_usable(main_split, 240, 520)
	)
	add_child(main_split)

	# 左栏：建筑原型目录
	var left_panel := PanelContainer.new()
	left_panel.clip_contents = true
	left_panel.custom_minimum_size.x = 260
	GDEditorUi.apply_panel(left_panel, 10)
	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)
	main_split.add_child(left_panel)

	_catalog_title = GDEditorUi.section_title("原型")
	left_vbox.add_child(_catalog_title)

	var cat_tools := HBoxContainer.new()
	cat_tools.add_theme_constant_override("separation", 6)
	var edit_type_btn := Button.new()
	edit_type_btn.text = "类型"
	edit_type_btn.tooltip_text = GDSceneEditorL10n.l("编辑类型")
	edit_type_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_type_btn.pressed.connect(_open_type_edit_popup)
	GDEditorUi.style_button(edit_type_btn, "quiet")
	cat_tools.add_child(edit_type_btn)

	var add_arch_btn := Button.new()
	add_arch_btn.text = "+ 原型"
	add_arch_btn.tooltip_text = "新建一个建筑原型"
	add_arch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_arch_btn.pressed.connect(_create_quick_archetype)
	GDEditorUi.style_button(add_arch_btn, "primary")
	cat_tools.add_child(add_arch_btn)

	var ref_arch_btn := Button.new()
	ref_arch_btn.text = "刷新"
	ref_arch_btn.tooltip_text = "刷新建筑原型目录"
	ref_arch_btn.pressed.connect(refresh_all)
	GDEditorUi.style_button(ref_arch_btn, "quiet")
	cat_tools.add_child(ref_arch_btn)
	left_vbox.add_child(cat_tools)

	var cat_search := GDEditorUi.search_field("搜索名称或 ID")
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
	_catalog_box.add_theme_constant_override("separation", 8)
	cat_scroll.add_child(_catalog_box)
	GDEditorUi.configure_vertical_scroll(cat_scroll, _catalog_box)
	GDLevelSceneDrop.bind_status(Callable(self, "_on_drop_status"))

	# 中右分割
	var mid_right_split := HSplitContainer.new()
	mid_right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_right_split.split_offset = 380
	mid_right_split.resized.connect(func() -> void:
		GDEditorUi.ensure_split_usable(mid_right_split, 280, 220)
	)
	main_split.add_child(mid_right_split)

	# 中栏：属性面板
	var mid_panel := PanelContainer.new()
	mid_panel.clip_contents = true
	mid_panel.custom_minimum_size.x = 280
	GDEditorUi.apply_panel(mid_panel, 10)
	var mid_vbox := VBoxContainer.new()
	mid_vbox.add_theme_constant_override("separation", 8)
	mid_panel.add_child(mid_vbox)
	mid_right_split.add_child(mid_panel)

	mid_vbox.add_child(GDEditorUi.section_title(GDSceneEditorL10n.l("属性")))

	var prop_scroll := ScrollContainer.new()
	prop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_vbox.add_child(prop_scroll)

	_properties_box = VBoxContainer.new()
	_properties_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_properties_box.add_theme_constant_override("separation", 6)
	prop_scroll.add_child(_properties_box)
	GDEditorUi.configure_vertical_scroll(prop_scroll, _properties_box)

	# 右栏：已摆放实例列表
	var right_panel := PanelContainer.new()
	right_panel.clip_contents = true
	right_panel.custom_minimum_size.x = 240
	GDEditorUi.apply_panel(right_panel, 10)
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(right_vbox)
	mid_right_split.add_child(right_panel)

	_placed_title = GDEditorUi.section_title(GDSceneEditorL10n.l("已摆放实例"))
	right_vbox.add_child(_placed_title)

	var placed_search := GDEditorUi.search_field("搜索已摆放的名称或 ID")
	placed_search.text_changed.connect(func(t: String) -> void:
		_placed_query = t
		_rebuild_placed_pane()
	)
	right_vbox.add_child(placed_search)

	var save_reload_row := HBoxContainer.new()
	save_reload_row.add_theme_constant_override("separation", 6)
	var save_btn := Button.new()
	save_btn.text = GDSceneEditorL10n.l("保存")
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_save_current_layout)
	GDEditorUi.style_button(save_btn, "primary")
	save_reload_row.add_child(save_btn)

	var reload_btn := Button.new()
	reload_btn.text = GDSceneEditorL10n.l("重新加载")
	reload_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reload_btn.pressed.connect(refresh_all)
	GDEditorUi.style_button(reload_btn, "quiet")
	save_reload_row.add_child(reload_btn)
	right_vbox.add_child(save_reload_row)

	var placed_scroll := ScrollContainer.new()
	placed_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(placed_scroll)

	_placed_list_box = VBoxContainer.new()
	_placed_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_placed_list_box.add_theme_constant_override("separation", 4)
	placed_scroll.add_child(_placed_list_box)
	GDEditorUi.configure_vertical_scroll(placed_scroll, _placed_list_box)

	var status_bar := PanelContainer.new()
	GDEditorUi.apply_panel(status_bar, 8)
	_status_bar_label = Label.new()
	_status_bar_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_bar_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_bar_label.text = "按住左侧原型，拖进 3D 或 2D 视口后松开。单击卡片只查看属性。"
	_status_bar_label.add_theme_color_override("font_color", Color(0.74, 0.88, 0.78))
	status_bar.add_child(_status_bar_label)
	add_child(status_bar)

	# ── 底部内嵌 CLI 面板 ──
	_cli_panel = VBoxContainer.new()
	_cli_panel.visible = false
	_cli_panel.custom_minimum_size.y = 160
	_cli_panel.add_theme_constant_override("separation", 4)
	add_child(_cli_panel)
	_build_cli_panel()

	refresh_all()

func _build_cli_panel() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	_cli_panel.add_child(bar)

	var help_btn := Button.new()
	help_btn.text = "帮助"
	help_btn.pressed.connect(func() -> void:
		_cli_output.text = "全部命令：\n  - " + "\n  - ".join(GDSceneEditorCli.ALL_COMMANDS)
	)
	bar.add_child(help_btn)

	var clr_btn := Button.new()
	clr_btn.text = "清空"
	clr_btn.pressed.connect(func() -> void:
		_cli_output.text = "输入命令后回车。输入 'help' 查看全部命令。"
	)
	bar.add_child(clr_btn)

	var kw_list_btn := Button.new()
	kw_list_btn.text = "Keywords: List"
	kw_list_btn.pressed.connect(func() -> void: _execute_cli_command("keywords.list"))
	bar.add_child(kw_list_btn)

	var kw_val_btn := Button.new()
	kw_val_btn.text = "Keywords: Validate"
	kw_val_btn.pressed.connect(func() -> void: _execute_cli_command("keywords.validate"))
	bar.add_child(kw_val_btn)

	var lay_list_btn := Button.new()
	lay_list_btn.text = "Layout: List"
	lay_list_btn.pressed.connect(func() -> void: _execute_cli_command("layout.list"))
	bar.add_child(lay_list_btn)

	var in_row := HBoxContainer.new()
	var prompt_lbl := Label.new()
	prompt_lbl.text = "$"
	in_row.add_child(prompt_lbl)
	_cli_input = LineEdit.new()
	_cli_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cli_input.text_submitted.connect(func(t: String) -> void: _execute_cli_command(t))
	in_row.add_child(_cli_input)
	var run_btn := Button.new()
	run_btn.text = "运行"
	run_btn.pressed.connect(func() -> void: _execute_cli_command(_cli_input.text))
	in_row.add_child(run_btn)
	_cli_panel.add_child(in_row)

	_cli_output = TextEdit.new()
	_cli_output.editable = false
	_cli_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cli_output.text = "输入命令后回车。输入 'help' 查看全部命令。"
	_cli_panel.add_child(_cli_output)

func _execute_cli_command(raw: String) -> void:
	var clean := raw.strip_edges()
	if clean.is_empty():
		return
	if clean == "help":
		_cli_output.text = "全部命令：\n  - " + "\n  - ".join(GDSceneEditorCli.ALL_COMMANDS)
		_cli_input.text = ""
		return
	_cli_history.append(clean)
	if _cli_history.size() > 10:
		_cli_history.pop_front()
	var parts := GDCliRoot.split_command_line(clean)
	var cmd := parts[0]
	var args: Array = []
	for i in range(1, parts.size()):
		args.append(parts[i])
	if _archetype_type_catalog != null and not _archetype_type_catalog.resource_path.is_empty() and not args.has("--catalog"):
		args.append("--catalog")
		args.append(_archetype_type_catalog.resource_path)
	if _layout != null and not _layout.resource_path.is_empty() and not args.has("--layout"):
		args.append("--layout")
		args.append(_layout.resource_path)
	var res := GDSceneEditorCli.run(cmd, args)
	_cli_output.text = "> %s\n%s" % [clean, res]
	_cli_input.text = ""
	refresh_all()

func refresh_all() -> void:
	if _layout_label == null:
		return
	var lname := "(无关卡场景)"
	if _layout != null:
		lname = _layout.display_name if not _layout.display_name.is_empty() else (
			_layout.resource_name if not _layout.resource_name.is_empty() else "LevelScene"
		)
	_layout_label.text = "%s%s" % [GDSceneEditorL10n.l("编辑中："), lname]
	_rebuild_catalog_pane()
	_rebuild_properties_pane()
	_rebuild_placed_pane()

func _on_drop_status(text: String, refresh_ui: bool) -> void:
	if _status_bar_label != null and not text.is_empty():
		_status_bar_label.text = text
	if refresh_ui:
		refresh_all()

func _sync_layout_to_scene() -> void:
	var res := GDLevelSceneDrop.sync_layout_to_scene(_layout)
	if _status_bar_label != null:
		_status_bar_label.text = str(res.get("message", ""))
	refresh_all()

func _rebuild_catalog_pane() -> void:
	GDEditorUi.clear_children(_catalog_box)
	if _catalog_title != null:
		_catalog_title.text = "原型    %d" % _archetype_catalog.size()
	if _archetype_catalog.is_empty():
		_catalog_box.add_child(GDEditorUi.empty_state("还没有原型", [
			"点上方「新建关卡」，或「+ 原型」。",
			"卡片可以按住拖进 3D / 2D 视口。",
			"单击卡片，在中间查看和修改属性。",
		]))
		return

	# 按类型分组
	var groups: Dictionary = {} # type_id -> Array[GDArchetypeRes]
	for a in _archetype_catalog:
		if a == null:
			continue
		var tid := a.archetype_type_stable_id
		if not groups.has(tid):
			groups[tid] = []
		groups[tid].append(a)

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
			var title_str: String = arch.display_name if not arch.display_name.is_empty() else ("Archetype#%d" % arch.stable_id)
			if GDEditorUi.matches_query("%s %d %s" % [title_str, arch.stable_id, gname], _catalog_query):
				visible.append(arch)
		if visible.is_empty():
			continue
		shown += visible.size()
		var is_open: bool = bool(_type_group_foldouts.get(tid, true))

		var fold_btn := GDEditorUi.fold_button(gname, visible.size(), is_open)
		var cap_tid := tid
		fold_btn.pressed.connect(func() -> void:
			_type_group_foldouts[cap_tid] = not bool(_type_group_foldouts.get(cap_tid, true))
			_rebuild_catalog_pane()
		)
		_catalog_box.add_child(fold_btn)

		if not is_open:
			continue

		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		_catalog_box.add_child(flow)

		for arch in visible:
			flow.add_child(_create_archetype_card(arch))

	if shown == 0:
		_catalog_box.add_child(GDEditorUi.muted("没有匹配「%s」的原型。" % _catalog_query.strip_edges()))
	elif _catalog_title != null and not _catalog_query.strip_edges().is_empty():
		_catalog_title.text = "原型    %d / %d" % [shown, _archetype_catalog.size()]

func _create_archetype_card(arch: GDArchetypeRes) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(176, 118)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GDEditorUi.style_card(card, _selected_archetype == arch)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var top_bar := HBoxContainer.new()
	top_bar.add_child(GDEditorUi.swatch(GDEditorUi.hue_color(arch.archetype_type_stable_id)))
	if arch.is_override_archetype:
		var var_lbl := Label.new()
		var base_a := arch.override_base_archetype
		var_lbl.text = "Variant"
		var_lbl.tooltip_text = "复写自：%s" % (base_a.display_name if base_a != null else "丢失")
		var_lbl.modulate = Color(1.0, 0.78, 0.3) if base_a != null else Color(0.95, 0.4, 0.35)
		top_bar.add_child(var_lbl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(sp)
	var menu_btn := MenuButton.new()
	menu_btn.text = "⋯"
	var p := menu_btn.get_popup()
	p.add_item("重命名", 1)
	p.add_item("复制原型", 2)
	p.add_item("新建 Variant 实例", 3)
	p.add_separator()
	p.add_item("删除原型", 4)
	p.id_pressed.connect(func(id: int) -> void:
		_on_archetype_card_menu(arch, id)
	)
	top_bar.add_child(menu_btn)
	vbox.add_child(top_bar)

	var title_str := arch.display_name if not arch.display_name.is_empty() else ("Archetype#%d" % arch.stable_id)
	var handle := GDLevelSceneDrop.DragSource.new()
	handle.archetype = arch
	handle.layout_getter = Callable(self, "get_current_layout")
	handle.title_text = "%s  #%d" % [title_str, arch.stable_id]
	handle.selected = _selected_archetype == arch
	handle.on_click = func() -> void:
		select_archetype_for_right_pane(arch)
	vbox.add_child(handle)

	var place_btn := Button.new()
	place_btn.text = "⊕"
	place_btn.tooltip_text = "放到视口中心。没有 3D 视口时放在原点。"
	place_btn.disabled = _layout == null
	place_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GDEditorUi.style_button(place_btn, "quiet")
	place_btn.pressed.connect(func() -> void:
		_place_archetype_at_view(arch)
	)
	vbox.add_child(place_btn)
	return card

func _place_archetype_at_view(arch: GDArchetypeRes) -> void:
	if _layout == null or arch == null:
		return
	var result := GDLevelSceneDrop.place_archetype(_layout, arch, GDLevelSceneDrop.suggest_drop_point())
	if bool(result.get("ok", false)):
		select_placement_for_right_pane(int(result.get("instance_id", 0)))
	elif _status_bar_label != null:
		_status_bar_label.text = str(result.get("error", "摆放失败"))

func _on_archetype_card_menu(arch: GDArchetypeRes, menu_id: int) -> void:
	if _layout == null or arch == null:
		return
	match menu_id:
		1: # 重命名
			var old_asset := arch.resource_name
			var old_disp := arch.display_name
			arch.editor_set_display_name(old_disp + "_Renamed")
			_layout.editor_refresh_placement_identities_after_archetype_rename(arch, old_asset, old_disp)
			refresh_all()
		2: # 复制原型
			var new_id := _layout.editor_allocate_next_archetype_stable_id()
			var dup := GDLayoutMigrationAndArchetypeOps.ArchetypeOverrideService.create_duplicate_in_memory(
				arch, new_id, "%s_Copy" % arch.display_name, "%s_1" % arch.display_name, false
			)
			_layout.editor_add_archetype(dup)
			_archetype_catalog.append(dup)
			select_archetype_for_right_pane(dup)
		3: # 新建 Variant 实例
			var new_id := _layout.editor_allocate_next_archetype_stable_id()
			var ov := GDLayoutMigrationAndArchetypeOps.ArchetypeOverrideService.create_duplicate_in_memory(
				arch, new_id, "%s_Override" % arch.display_name, "%s_复写" % arch.display_name, true
			)
			_layout.editor_add_archetype(ov)
			_archetype_catalog.append(ov)
			select_archetype_for_right_pane(ov)
		4: # 删除原型
			_layout.editor_remove_placements_by_archetype_stable_id(arch.stable_id)
			_layout.editor_remove_archetype(arch)
			_archetype_catalog.erase(arch)
			if _selected_archetype == arch:
				_selected_archetype = null
				_right_pane_mode = RightPaneMode.NONE
			refresh_all()

func _rebuild_properties_pane() -> void:
	GDEditorUi.clear_children(_properties_box)

	match _right_pane_mode:
		RightPaneMode.PLACEMENT:
			_draw_properties_placement()
		RightPaneMode.ARCHETYPE:
			_draw_properties_archetype()
		_:
			_properties_box.add_child(GDEditorUi.empty_state("还没有选中内容", [
				"点左侧卡片，编辑这个原型。",
				"按住卡片拖进视口，或点「放到视口中心」。",
				"点右侧已摆放的一项，改位置、名字和 ID。",
			]))

func _draw_properties_placement() -> void:
	if _layout == null or _selected_instance_id <= 0:
		return
	var found := _layout.editor_try_get_placement(_selected_instance_id)
	if not bool(found.get("ok", false)):
		var warn := Label.new()
		warn.text = "该实例不在关卡场景中（可能已被删除）。"
		_properties_box.add_child(warn)
		return
	var inst: GDPlacementData.PlacementInstance = found["inst"]
	var arch := _layout.find_archetype_by_stable_id(inst.archetype_stable_id)
	var disp := GDPlacementData.PlacementInstanceIdRangeLogic.resolve_display_name(inst, arch)
	_properties_box.add_child(GDEditorUi.section_title(disp))
	_properties_box.add_child(GDEditorUi.muted("实例 #%d    等级 %d" % [inst.instance_id, inst.initial_level]))

	# 选中建筑原型按钮
	var focus_arch_btn := Button.new()
	focus_arch_btn.text = "选中建筑原型 · %s" % (arch.display_name if arch != null else ("Unknown#%d" % inst.archetype_stable_id))
	focus_arch_btn.disabled = arch == null
	focus_arch_btn.pressed.connect(func() -> void:
		if arch != null:
			select_archetype_for_right_pane(arch)
	)
	GDEditorUi.style_button(focus_arch_btn, "quiet")
	_properties_box.add_child(focus_arch_btn)

	var drop_zone := GDLevelSceneDrop.ReplaceDrop.new()
	drop_zone.instance_id = inst.instance_id
	drop_zone.layout_getter = Callable(self, "get_current_layout")
	drop_zone.on_replaced = func() -> void:
		select_placement_for_right_pane(inst.instance_id)
	_properties_box.add_child(drop_zone)

	# 替换原型下拉区
	if _archetype_catalog.size() > 1:
		var rep_row := HBoxContainer.new()
		var rep_lbl := Label.new()
		rep_lbl.text = "替换建筑原型"
		rep_lbl.custom_minimum_size.x = 96
		rep_row.add_child(rep_lbl)
		var rep_opt := OptionButton.new()
		rep_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cur_idx := 0
		for i in range(_archetype_catalog.size()):
			var a := _archetype_catalog[i]
			rep_opt.add_item("%s (#%d)" % [a.display_name, a.stable_id], a.stable_id)
			if a.stable_id == inst.archetype_stable_id:
				cur_idx = i
		rep_opt.selected = cur_idx
		rep_opt.item_selected.connect(func(idx: int) -> void:
			var new_arch_id := rep_opt.get_item_id(idx)
			if _layout.editor_replace_placement_archetype(inst.instance_id, new_arch_id):
				refresh_all()
		)
		rep_row.add_child(rep_opt)
		_properties_box.add_child(rep_row)

	_properties_box.add_child(GDEditorUi.muted("右侧平面图拖圆点改水平位置。下面的数字负责高度和精确值。"))
	# 位姿编辑（Position / Euler / LockScale=1 / Scale）
	_add_vec3_editor(_properties_box, GDSceneEditorL10n.l("位置"), inst.position, func(v: Vector3) -> void:
		_layout.editor_replace_placement(inst.instance_id, inst.with_transform(v, inst.euler_angles, inst.scale))
		GDLevelSceneDrop.apply_transform(inst.instance_id, v, inst.euler_angles, inst.scale)
	)
	_add_vec3_editor(_properties_box, GDSceneEditorL10n.l("旋转（欧拉角）"), inst.euler_angles, func(v: Vector3) -> void:
		_layout.editor_replace_placement(inst.instance_id, inst.with_transform(inst.position, v, inst.scale))
		GDLevelSceneDrop.apply_transform(inst.instance_id, inst.position, v, inst.scale)
	)

	var lock_cb := CheckBox.new()
	lock_cb.text = GDSceneEditorL10n.l("锁定缩放 = 1")
	lock_cb.button_pressed = _lock_scale
	lock_cb.toggled.connect(func(on: bool) -> void:
		_lock_scale = on
		if on:
			_layout.editor_replace_placement(inst.instance_id, inst.with_transform(inst.position, inst.euler_angles, Vector3.ONE))
			GDLevelSceneDrop.apply_transform(inst.instance_id, inst.position, inst.euler_angles, Vector3.ONE)
		refresh_all()
	)
	_properties_box.add_child(lock_cb)

	if not _lock_scale:
		_add_vec3_editor(_properties_box, GDSceneEditorL10n.l("缩放"), inst.scale, func(v: Vector3) -> void:
			_layout.editor_replace_placement(inst.instance_id, inst.with_transform(inst.position, inst.euler_angles, v))
			GDLevelSceneDrop.apply_transform(inst.instance_id, inst.position, inst.euler_angles, v)
		)

	# 固有属性分区：实例 ID 只读 + 名称 + 显示名
	_properties_box.add_child(GDEditorUi.section_title(GDSceneEditorL10n.l("固有属性")))

	var id_row := HBoxContainer.new()
	var id_lbl := Label.new()
	id_lbl.text = GDSceneEditorL10n.l("实例 ID")
	id_lbl.custom_minimum_size.x = 84
	id_row.add_child(id_lbl)
	var id_edit := LineEdit.new()
	id_edit.text = str(inst.instance_id)
	id_edit.editable = false
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(id_edit)
	_properties_box.add_child(id_row)

	var nm_row := HBoxContainer.new()
	var nm_lbl := Label.new()
	nm_lbl.text = GDSceneEditorL10n.l("名称")
	nm_lbl.custom_minimum_size.x = 84
	nm_row.add_child(nm_lbl)
	var nm_edit := LineEdit.new()
	nm_edit.text = inst.instance_name
	nm_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm_edit.text_submitted.connect(func(t: String) -> void:
		_layout.editor_replace_placement(inst.instance_id, inst.with_name(t))
		refresh_all()
	)
	nm_row.add_child(nm_edit)
	_properties_box.add_child(nm_row)

	var dp_row := HBoxContainer.new()
	var dp_lbl := Label.new()
	dp_lbl.text = GDSceneEditorL10n.l("显示名")
	dp_lbl.custom_minimum_size.x = 84
	dp_row.add_child(dp_lbl)
	var dp_edit := LineEdit.new()
	dp_edit.text = inst.display_name
	dp_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dp_edit.text_submitted.connect(func(t: String) -> void:
		_layout.editor_replace_placement(inst.instance_id, inst.with_display_name(t))
		refresh_all()
	)
	dp_row.add_child(dp_edit)
	_properties_box.add_child(dp_row)

	# 实例自定义属性覆盖
	_properties_box.add_child(GDEditorUi.section_title(GDSceneEditorL10n.l("自定义属性")))

	if arch == null or arch.custom_attributes.is_empty():
		var no_attr := Label.new()
		no_attr.text = "该原型尚未配置自定义属性。在原型属性栏点「+ 添加属性」。"
		no_attr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_properties_box.add_child(no_attr)
	else:
		var ov_by_tag: Dictionary = {}
		for o in inst.attribute_overrides:
			if o != null and not o.tag.is_empty():
				ov_by_tag[o.tag] = o
		for def in arch.custom_attributes:
			if def == null:
				continue
			var eff: GDPlacementData.PlacementAttributeOverride = ov_by_tag.get(
				def.tag, GDPlacementData.PlacementAttributeOverride.from_custom_attribute_def(def)
			)
			var r := HBoxContainer.new()
			var rl := Label.new()
			rl.text = def.display_name if not def.display_name.is_empty() else def.tag
			rl.custom_minimum_size.x = 96
			r.add_child(rl)
			var val_edit := LineEdit.new()
			val_edit.text = str(eff.get_boxed())
			val_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cap_def := def
			val_edit.text_submitted.connect(func(txt: String) -> void:
				var new_ov: GDPlacementData.PlacementAttributeOverride
				match cap_def.value_type:
					GDCoreTypes.KeywordValueType.INT:
						new_ov = GDPlacementData.PlacementAttributeOverride.of_int(cap_def.tag, txt.to_int())
					GDCoreTypes.KeywordValueType.FLOAT:
						new_ov = GDPlacementData.PlacementAttributeOverride.of_float(cap_def.tag, txt.to_float())
					GDCoreTypes.KeywordValueType.BOOL:
						new_ov = GDPlacementData.PlacementAttributeOverride.of_bool(cap_def.tag, txt.to_lower() == "true" or txt == "1")
					_:
						new_ov = GDPlacementData.PlacementAttributeOverride.of_string(cap_def.tag, txt)
				ov_by_tag[cap_def.tag] = new_ov
				var new_list: Array[GDPlacementData.PlacementAttributeOverride] = []
				for d2 in arch.custom_attributes:
					if d2 != null and ov_by_tag.has(d2.tag):
						new_list.append(ov_by_tag[d2.tag])
				_layout.editor_replace_placement(inst.instance_id, inst.with_overrides(new_list))
			)
			r.add_child(val_edit)
			_properties_box.add_child(r)

func _draw_properties_archetype() -> void:
	if _selected_archetype == null:
		return
	var arch := _selected_archetype

	_properties_box.add_child(GDEditorUi.section_title(arch.display_name if not arch.display_name.is_empty() else "原型"))
	_properties_box.add_child(GDEditorUi.muted("原型 ID  %d" % arch.stable_id))

	# 1. 建筑原型类型下拉
	var type_row := HBoxContainer.new()
	var type_lbl := Label.new()
	type_lbl.text = "建筑类型"
	type_lbl.custom_minimum_size.x = 90
	type_row.add_child(type_lbl)
	var type_opt := OptionButton.new()
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_opt.add_item("（未分类）", 0)
	var sel_idx := 0
	if _archetype_type_catalog != null:
		for e in _archetype_type_catalog.entries:
			if e != null and not e.deprecated:
				type_opt.add_item(e.display_name if not e.display_name.is_empty() else e.entry_name, e.stable_id)
				if e.stable_id == arch.archetype_type_stable_id:
					sel_idx = type_opt.item_count - 1
	type_opt.selected = sel_idx
	type_opt.item_selected.connect(func(idx: int) -> void:
		arch.editor_set_archetype_type_stable_id(type_opt.get_item_id(idx))
		refresh_all()
	)
	type_row.add_child(type_opt)
	_properties_box.add_child(type_row)

	# 2. Override 复写块
	if arch.is_override_archetype:
		var ov_panel := PanelContainer.new()
		var ov_lbl := Label.new()
		var base_n := arch.override_base_archetype.display_name if arch.override_base_archetype != null else "（已丢失）"
		ov_lbl.text = "复写（Prefab Variant）· 复写目标：%s" % base_n
		ov_panel.add_child(ov_lbl)
		_properties_box.add_child(ov_panel)

	# 3. 实例 ID 段 + 标准化实例 ID
	var range_panel := PanelContainer.new()
	var range_box := VBoxContainer.new()
	range_box.add_theme_constant_override("separation", 4)
	range_panel.add_child(range_box)
	_properties_box.add_child(range_panel)

	var use_cb := CheckBox.new()
	use_cb.text = GDSceneEditorL10n.l("自定义 ID 段")
	use_cb.button_pressed = arch.use_custom_instance_id_range
	use_cb.toggled.connect(func(on: bool) -> void:
		arch.editor_set_custom_instance_id_range(on, arch.instance_id_min, arch.instance_id_max)
		_rebuild_properties_pane()
	)
	range_box.add_child(use_cb)

	var minmax_row := HBoxContainer.new()
	var min_sb := SpinBox.new()
	min_sb.prefix = "Min:"
	min_sb.min_value = 0
	min_sb.max_value = 999999
	min_sb.value = arch.instance_id_min
	min_sb.editable = arch.use_custom_instance_id_range
	min_sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var max_sb := SpinBox.new()
	max_sb.prefix = "Max:"
	max_sb.min_value = 0
	max_sb.max_value = 999999
	max_sb.value = arch.instance_id_max
	max_sb.editable = arch.use_custom_instance_id_range
	max_sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	min_sb.value_changed.connect(func(v: float) -> void:
		arch.editor_set_custom_instance_id_range(arch.use_custom_instance_id_range, roundi(v), arch.instance_id_max)
	)
	max_sb.value_changed.connect(func(v: float) -> void:
		arch.editor_set_custom_instance_id_range(arch.use_custom_instance_id_range, arch.instance_id_min, roundi(v))
	)
	minmax_row.add_child(min_sb)
	minmax_row.add_child(max_sb)
	range_box.add_child(minmax_row)

	var std_btn := Button.new()
	std_btn.text = GDSceneEditorL10n.l("标准化实例 ID")
	std_btn.disabled = not arch.use_custom_instance_id_range or _layout == null
	std_btn.pressed.connect(func() -> void:
		if _layout == null:
			return
		var res := _layout.editor_try_standardize_instance_ids(arch)
		if bool(res.get("ok", false)):
			apply_instance_id_remaps(res.get("remaps", []))
	)
	range_box.add_child(std_btn)

	# 4. Prefab 地址块
	var addr_row := HBoxContainer.new()
	var addr_lbl := Label.new()
	addr_lbl.text = "实例 Address"
	addr_lbl.custom_minimum_size.x = 90
	addr_row.add_child(addr_lbl)
	var addr_edit := LineEdit.new()
	addr_edit.text = arch.manufactured_prefab_address
	addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addr_edit.text_submitted.connect(func(t: String) -> void:
		arch.editor_set_prefab_addresses(t.strip_edges(), arch.preview_prefab_address)
		_rebuild_properties_pane()
	)
	addr_row.add_child(addr_edit)
	_properties_box.add_child(addr_row)

	# 5. 外观预览面板
	_preview_panel = GDArchetypePreviewPanel.new()
	_properties_box.add_child(_preview_panel)
	_preview_panel.bind_archetype(arch)

	# 6. 原型自定义属性
	var empty_bindings: Array[GDEntityAtomSystem.AtomVarTagRegistry.Binding] = []
	GDCoreAtomEditorWidgets.build_custom_attributes_inspector(
		_properties_box,
		arch,
		empty_bindings,
		func() -> void: _rebuild_properties_pane()
	)

func _rebuild_placed_pane() -> void:
	GDEditorUi.clear_children(_placed_list_box)
	var total := 0 if _layout == null else _layout.placements.size()
	if _placed_title != null:
		_placed_title.text = "平面    %d" % total
	var board := GDEditorUi.XZBoard.new()
	board.tooltip_text = "俯视图。单击圆点选中，拖动改水平位置。蓝线是 X，绿线是 Z。"
	if _layout != null:
		for inst in _layout.placements:
			if inst == null:
				continue
			var arch := _layout.find_archetype_by_stable_id(inst.archetype_stable_id)
			var mark := GDEditorUi.XZMark.new()
			mark.id = inst.instance_id
			mark.x = inst.position.x
			mark.z = inst.position.z
			mark.color = GDEditorUi.hue_color(inst.archetype_stable_id)
			mark.label = GDPlacementData.PlacementInstanceIdRangeLogic.resolve_display_name(inst, arch)
			mark.selected = inst.instance_id == _selected_instance_id
			board.marks.append(mark)
	board.picked.connect(func(id: int) -> void:
		select_placement_for_right_pane(id)
		GDLevelSceneDrop.focus_instance(id)
	)
	board.moved.connect(func(id: int, x: float, z: float) -> void:
		if _layout == null:
			return
		var found := _layout.editor_try_get_placement(id)
		if not bool(found.get("ok", false)):
			return
		var moved_inst: GDPlacementData.PlacementInstance = found["inst"]
		var pos := Vector3(x, moved_inst.position.y, z)
		_layout.editor_replace_placement(id, moved_inst.with_transform(pos, moved_inst.euler_angles, moved_inst.scale))
		GDLevelSceneDrop.apply_transform(id, pos, moved_inst.euler_angles, moved_inst.scale)
		select_placement_for_right_pane(id)
	)
	_placed_list_box.add_child(board)
	if _layout == null or _layout.placements.is_empty():
		_placed_list_box.add_child(GDEditorUi.muted("把左侧原型拖进视口，或点卡片上的 ⊕。圆点会出现在这张图上。"))
		return

	var shown := 0
	for i in range(_layout.placements.size()):
		var inst = _layout.placements[i]
		if inst == null:
			continue
		var arch := _layout.find_archetype_by_stable_id(inst.archetype_stable_id)
		var disp: String = GDPlacementData.PlacementInstanceIdRangeLogic.resolve_display_name(inst, arch)
		var arch_name: String = arch.display_name if arch != null else ""
		if not GDEditorUi.matches_query("%s %d %s" % [disp, inst.instance_id, arch_name], _placed_query):
			continue
		shown += 1
		var selected: bool = int(inst.instance_id) == _selected_instance_id
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(GDEditorUi.swatch(GDEditorUi.hue_color(inst.archetype_stable_id), 8))

		var sel_btn := Button.new()
		sel_btn.flat = true
		sel_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sel_btn.clip_text = true
		sel_btn.text = disp
		sel_btn.tooltip_text = "#%d  等级 %d  %s" % [inst.instance_id, inst.initial_level, arch_name]
		if selected:
			sel_btn.add_theme_color_override("font_color", Color(0.65, 0.86, 1.0))
		var cap_id: int = inst.instance_id
		sel_btn.pressed.connect(func() -> void:
			select_placement_for_right_pane(cap_id)
			GDLevelSceneDrop.focus_instance(cap_id)
		)
		row.add_child(sel_btn)

		var up_btn := GDEditorUi.icon_button("↑", "上移")
		up_btn.disabled = i == 0
		var cap_idx := i
		up_btn.pressed.connect(func() -> void:
			if _layout.editor_move_placement(cap_id, cap_idx - 1):
				refresh_all()
		)
		row.add_child(up_btn)

		var dn_btn := GDEditorUi.icon_button("↓", "下移")
		dn_btn.disabled = i >= _layout.placements.size() - 1
		dn_btn.pressed.connect(func() -> void:
			if _layout.editor_move_placement(cap_id, cap_idx + 2):
				refresh_all()
		)
		row.add_child(dn_btn)

		var reset_id_btn := GDEditorUi.icon_button("#", "重设实例 ID")
		reset_id_btn.pressed.connect(func() -> void:
			if _reset_id_popup == null:
				_reset_id_popup = GDLevelEditorPopups.ResetInstanceIdPopup.new()
				add_child(_reset_id_popup)
				_reset_id_popup.id_reset_confirmed.connect(func(new_id: int) -> void:
					_selected_instance_id = new_id
					refresh_all()
				)
			_reset_id_popup.open_for(_layout, cap_id)
		)
		row.add_child(reset_id_btn)

		var del_btn := GDEditorUi.icon_button("×", "删除这个实例", "danger")
		del_btn.pressed.connect(func() -> void:
			GDLevelSceneDrop.delete_placement(_layout, cap_id)
			if _selected_instance_id == cap_id:
				_selected_instance_id = 0
				_right_pane_mode = RightPaneMode.NONE
			refresh_all()
		)
		row.add_child(del_btn)
		_placed_list_box.add_child(row)

	if shown == 0:
		_placed_list_box.add_child(GDEditorUi.muted("没有匹配「%s」的实例。" % _placed_query.strip_edges()))
	elif _placed_title != null and not _placed_query.strip_edges().is_empty():
		_placed_title.text = "平面    %d / %d" % [shown, total]

func _resolve_type_name(type_stable_id: int) -> String:
	if type_stable_id <= 0:
		return GDSceneEditorL10n.l("未分类")
	if _archetype_type_catalog != null:
		for e in _archetype_type_catalog.entries:
			if e != null and e.stable_id == type_stable_id:
				return e.display_name if not e.display_name.is_empty() else e.entry_name
	return "Type#%d" % type_stable_id

static func _add_vec3_editor(parent: VBoxContainer, label_text: String, val: Vector3, on_changed: Callable) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	block.add_child(GDEditorUi.muted(label_text))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var axes := ["X", "Y", "Z"]
	var vals := [val.x, val.y, val.z]
	var spins: Array[SpinBox] = []
	for i in range(3):
		var sb := SpinBox.new()
		sb.prefix = axes[i] + " "
		sb.step = 0.1
		sb.allow_greater = true
		sb.allow_lesser = true
		sb.value = vals[i]
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spins.append(sb)
		row.add_child(sb)
	for sb in spins:
		sb.value_changed.connect(func(_v: float) -> void:
			on_changed.call(Vector3(spins[0].value, spins[1].value, spins[2].value))
		)
	block.add_child(row)
	parent.add_child(block)

func _on_open_or_create_demo_layout() -> void:
	if _layout == null:
		set_layout(GDSampleFactory.load_level_scene())

func _create_new_in_memory_layout() -> void:
	GDSampleFactory.ensure_sample_assets()
	set_layout(GDSampleFactory.build_level_scene())

func _create_quick_archetype() -> void:
	if _layout == null:
		_create_new_in_memory_layout()
	var sid := _layout.editor_allocate_next_archetype_stable_id()
	var arch := GDLevelArchetypeRes.new()
	arch.editor_init_with_addresses(sid, "新建筑_%d" % sid, "Entity_Building_%d" % sid, "")
	_layout.editor_add_archetype(arch)
	_archetype_catalog.append(arch)
	select_archetype_for_right_pane(arch)

func _open_type_edit_popup() -> void:
	if _layout == null:
		return
	if _archetype_type_catalog == null:
		_archetype_type_catalog = GDKeywordCatalogRes.new()
		_layout.editor_bind_archetype_type_keywords(_archetype_type_catalog)
	if _type_edit_popup == null:
		_type_edit_popup = GDLevelEditorPopups.TypeEditPopup.new()
		add_child(_type_edit_popup)
		_type_edit_popup.catalog_changed.connect(refresh_all)
	_type_edit_popup.bind_catalog(_archetype_type_catalog)
	_type_edit_popup.popup_centered()

func _save_current_layout() -> void:
	if _layout == null:
		return
	GDLevelSceneDrop.pull_transforms_from_scene(_layout)
	if not _layout.resource_path.is_empty():
		ResourceSaver.save(_layout, _layout.resource_path)
		_status_bar_label.text = "关卡已保存，并已从场景回写位姿。"
	else:
		_status_bar_label.text = "关卡还在内存里。场景中的实例会随当前场景一起保存。"

func _on_tools_menu_id_pressed(id: int) -> void:
	match id:
		1:
			if _path_editor_win == null:
				_path_editor_win = GDPathEditorWindow.new()
				add_child(_path_editor_win)
			_path_editor_win.bind_layout(_layout)
			_path_editor_win.popup_centered()
		2:
			if _camera_pose_win == null:
				_camera_pose_win = GDCameraPoseEditorWindow.new()
				add_child(_camera_pose_win)
			_camera_pose_win.bind_layout(_layout)
			_camera_pose_win.popup_centered()
		3:
			if _layout != null:
				var csv := GDLevelCsvExporter.build_csv(_layout)
				_cli_panel_open = true
				_cli_panel.visible = true
				_cli_output.text = "--- CSV Export ---\n" + csv
		4:
			if _layout != null:
				var opts := GDLayoutMigrationAndArchetypeOps.MigrationOptions.new()
				opts.dry_run = false
				var rep := GDLayoutMigrationAndArchetypeOps.run_migration([_layout], opts)
				_cli_panel_open = true
				_cli_panel.visible = true
				_cli_output.text = rep.format_report()
				refresh_all()
		5:
			GDSceneEditorL10n.current_language = (
				GDSceneEditorL10n.Language.ENGLISH
				if GDSceneEditorL10n.current_language == GDSceneEditorL10n.Language.CHINESE
				else GDSceneEditorL10n.Language.CHINESE
			)
			refresh_all()
