@tool
class_name GDGameModePage
extends GDPage

const CONFIG_ROOT := "res://game_res/game_mode"
var config: GDGameModeConfigRes:
	get: return doc.resource as GDGameModeConfigRes if doc != null else null

var _graph: GDGameModeGraph
var _tree: Tree
var _global_tree: Tree
var _new_button: Button
var _open_button: Button
var _add_state_button: Button
var _form: GDForm
var _search: LineEdit
var _session_picker: OptionButton
var _status_label: Label
var _follow: CheckBox
var _view_picker: OptionButton
var _timeline: ItemList
var _kind_filter: OptionButton
var _module_filter: LineEdit
var _command_buttons: Array[Button] = []
var _apply_button: Button
var _command_result_label: Label
var _report: Dictionary = {"errors": [], "warnings": [], "issues": []}
var _selected_key := "@config"
var _selected_module: Variant = -1
var _monitor := false
var _session_id := -1
var _debugger: GDGameModeDebuggerPlugin
var _refreshing := false
var _last_follow_key := ""
var _timeline_signature := ""


func _build() -> void:
	_new_button = GDEditorUi.text_button("新建", new_config)
	_open_button = GDEditorUi.text_button("打开", _open_config)
	toolbar.add_child(_new_button)
	toolbar.add_child(_open_button)
	_view_picker = OptionButton.new()
	_view_picker.add_item("配置视图")
	_view_picker.add_item("运行监控")
	_view_picker.item_selected.connect(func(index: int) -> void:
		_monitor = index == 1
		if not _monitor and not _selected_module is int:
			_selected_key = "@config"
			_selected_module = -1
		_form.clear()
		_refresh()
	)
	toolbar.add_child(_view_picker)
	toolbar_right.add_child(GDEditorUi.menu_button("", &"GuiTabMenuHl", "文件", [
		{"text": "另存为…", "do": save_as_current},
		{"text": "生成并打开示例", "do": _open_sample},
	]))
	var status := HBoxContainer.new()
	status.add_child(Label.new())
	status.get_child(0).text = "会话："
	_session_picker = OptionButton.new()
	_session_picker.custom_minimum_size.x = 150
	_session_picker.item_selected.connect(func(index: int) -> void:
		_session_id = _session_picker.get_item_id(index)
		_last_follow_key = ""
		_refresh()
	)
	status.add_child(_session_picker)
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.clip_text = true
	status.add_child(_status_label)
	_follow = CheckBox.new()
	_follow.text = "跟随当前状态"
	_follow.button_pressed = true
	_follow.toggled.connect(func(_enabled: bool) -> void:
		_last_follow_key = ""
		_refresh()
	)
	status.add_child(_follow)
	set_status_row(status)
	var left := VBoxContainer.new()
	_global_tree = Tree.new()
	_global_tree.hide_root = true
	_global_tree.allow_rmb_select = true
	_global_tree.add_theme_stylebox_override("panel", GDEditorUi.flat_box(
		GDEditorUi.tone(&"sunken").lerp(GDGameModeGraph.global_color(), 0.12),
		Color(GDGameModeGraph.global_color(), 0.4), 3, 1))
	_global_tree.item_selected.connect(_tree_selected.bind(_global_tree))
	_global_tree.item_mouse_selected.connect(_module_tree_context_menu.bind(_global_tree))
	_global_tree.item_activated.connect(func() -> void: open_source(_selected_module))
	left.add_child(_global_tree)
	left.add_child(HSeparator.new())
	_search = LineEdit.new()
	_search.placeholder_text = "搜索状态 / 模块"
	_search.text_changed.connect(func(_value: String) -> void: _refresh_tree())
	left.add_child(_search)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.allow_rmb_select = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_tree_selected.bind(_tree))
	_tree.item_mouse_selected.connect(_module_tree_context_menu.bind(_tree))
	_tree.item_activated.connect(func() -> void: open_source(_selected_module))
	left.add_child(_tree)
	var actions := HBoxContainer.new()
	for definition in [["↑", -1], ["↓", 1]]:
		actions.add_child(GDEditorUi.text_button(definition[0], move_selected.bind(definition[1])))
	actions.add_child(GDEditorUi.text_button("删除", delete_selected))
	actions.add_child(GDEditorUi.spacer())
	_add_state_button = GDEditorUi.text_button("+ 状态", _prompt_state)
	actions.add_child(_add_state_button)
	left.add_child(actions)
	_graph = GDGameModeGraph.new()
	_graph.picked.connect(_select)
	_graph.source_requested.connect(open_source)
	_graph.positions_changed.connect(move_nodes)
	_graph.layout_requested.connect(auto_layout)
	_graph.default_state_requested.connect(set_default_state)
	_graph.module_create_requested.connect(_create_module)
	_graph.module_add_requested.connect(_pick_module_script)
	_form = GDForm.new()
	_form.committed.connect(func(label: String, merge: bool) -> void: _commit("修改 " + label, merge))
	set_panes(GDEditorUi.pane(left), GDEditorUi.pane(_graph, 0), GDEditorUi.pane(GDEditorUi.scroll_of(_form)), 220, 300)
	var bottom := VBoxContainer.new()
	var commands := HBoxContainer.new()
	bottom.add_child(commands)
	for definition in [["切换到选中状态", "switch_state"], ["重启当前状态", "restart_state"], ["重启选中模块", "restart_module"]]:
		var button := GDEditorUi.text_button(definition[0], _send_command.bind(definition[1]))
		button.tooltip_text = "切换会跳过业务前置条件，仅用于调试" if definition[1] == "switch_state" else "运行命令不进入文档撤销栈"
		_command_buttons.append(button)
		commands.add_child(button)
	_apply_button = GDEditorUi.text_button("应用配置并重启 GameMode", _apply_config)
	commands.add_child(_apply_button)
	_command_result_label = GDEditorUi.hint_label("")
	bottom.add_child(_command_result_label)
	var filters := HBoxContainer.new()
	bottom.add_child(filters)
	filters.add_child(GDEditorUi.muted_label("时间线"))
	_kind_filter = OptionButton.new()
	for kind in ["全部事件", "state_", "module_construct", "module_begin_play", "module_dispose", "module_fault", "command_", "reentry_overflow", "switch_rejected", "gm_"]:
		_kind_filter.add_item(kind)
	_kind_filter.item_selected.connect(func(_index: int) -> void: _refresh_timeline())
	filters.add_child(_kind_filter)
	_module_filter = LineEdit.new()
	_module_filter.placeholder_text = "模块 ID 筛选"
	_module_filter.text_changed.connect(func(_text: String) -> void: _refresh_timeline())
	filters.add_child(_module_filter)
	_timeline = ItemList.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.custom_minimum_size.y = 70
	bottom.add_child(_timeline)
	set_bottom(bottom, 180)
	document_state_changed.connect(_refresh_status)
	_refresh()


func _ready() -> void:
	_bind_debugger()


func _process(_delta: float) -> void:
	_bind_debugger()


func _bind_debugger() -> void:
	var candidate := GDGameModeDebuggerPlugin.current
	if candidate == _debugger:
		return
	if is_instance_valid(_debugger) and _debugger.sessions_changed.is_connected(_sessions_changed):
		_debugger.sessions_changed.disconnect(_sessions_changed)
	_debugger = candidate
	if _debugger != null:
		_debugger.sessions_changed.connect(_sessions_changed)
	_sessions_changed()


func activate() -> void:
	_bind_debugger()
	if config == null and DirAccess.dir_exists_absolute(CONFIG_ROOT):
		var files := DirAccess.get_files_at(CONFIG_ROOT)
		for file in files:
			if file.ends_with(".tres"):
				load_config_path(CONFIG_ROOT.path_join(file))
				if config != null:
					break


func new_config() -> void:
	var value := GDGameModeConfigRes.new()
	value.display_name = "GameMode_Default"
	var state := GDGameStateBindingRes.new()
	state.key = &"login"
	state.display_name = "登录"
	state.graph_position = Vector2(340, 40)
	value.states.append(state)
	value.default_state_key = state.key
	value.global_graph_position = Vector2(40, 40)
	load_config(value)
	doc.mark_unsaved()


func load_config(value: GDGameModeConfigRes) -> void:
	if value != null and not _docs.has(value):
		_docs[value] = GDDocument.new(value, _external_parameters(value))
	open_document(value)
	_selected_key = "@config"
	_selected_module = -1
	_form.clear()
	_refresh()
	_graph.frame_all.call_deferred()


func load_config_path(path: String) -> void:
	var value := ResourceLoader.load(path) as GDGameModeConfigRes
	if value == null:
		say("无法读取游戏进程配置：" + path, &"danger")
		return
	load_config(value)


func _open_config() -> void:
	GDGameModeConfigPicker.open(self, load_config, _docs.keys())


func _suggest_save_path(resource: Resource) -> String:
	return CONFIG_ROOT.path_join((resource as GDGameModeConfigRes).display_name.validate_filename() + ".tres")


func prepare_save(target: GDDocument) -> void:
	(target.resource as GDGameModeConfigRes).prepare_save()


func _commit(label: String, merge: bool = false) -> void:
	if doc != null:
		doc.snapshot_exclusions = _external_parameters(config)
		doc.commit(label, merge)


static func _external_parameters(value: GDGameModeConfigRes) -> Array[Resource]:
	var result: Array[Resource] = []
	if value != null:
		for entry in value.all_modules():
			if entry != null:
				_collect_external(entry.params, result, {})
	return result


static func _collect_external(value: Variant, result: Array[Resource], seen: Dictionary) -> void:
	if value is Resource and not seen.has(value):
		seen[value] = true
		if not value.resource_path.is_empty() and not "::" in value.resource_path:
			result.append(value)
			return
		for prop in value.get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE and prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_collect_external(value.get(prop.name), result, seen)
	elif value is Array:
		for entry in value:
			_collect_external(entry, result, seen)
	elif value is Dictionary:
		for entry in value.values():
			_collect_external(entry, result, seen)


func add_state(key: String, title: String = "") -> GDGameStateBindingRes:
	if config == null or not _key_error(key).is_empty():
		return null
	var state := GDGameStateBindingRes.new()
	state.key = StringName(key)
	state.display_name = title if not title.is_empty() else key
	state.graph_position = Vector2(340 + (config.states.size() % 3) * 290, 40 + (config.states.size() / 3) * 230)
	if config.states.is_empty():
		config.default_state_key = state.key
	config.states.append(state)
	_selected_key = key
	_selected_module = -1
	_commit("新增状态 " + key)
	return state


func set_default_state(key: String) -> bool:
	if config == null or _monitor or key.begins_with("@"):
		return false
	var state := config.find_state(StringName(key))
	if state == null or config.default_state_key == state.key:
		return false
	config.default_state_key = state.key
	_commit("设置默认状态 " + key)
	return true


func rename_state_key(old_key: String, new_key: String) -> bool:
	if config == null or not _key_error(new_key, old_key).is_empty():
		return false
	var state := config.find_state(StringName(old_key))
	if state == null:
		return false
	state.key = StringName(new_key)
	if config.default_state_key == StringName(old_key):
		config.default_state_key = state.key
	_selected_key = new_key
	_commit("修改状态 Key")
	return true


func _key_error(value: String, except: String = "") -> String:
	var regex := RegEx.new()
	regex.compile("^[a-z0-9_]+$")
	if regex.search(value) == null:
		return "Key 只允许小写字母、数字和下划线，不能为空"
	if value != except and config != null and config.find_state(StringName(value)) != null:
		return "Key 已存在"
	return ""


func _prompt_state() -> void:
	if config == null or _monitor:
		return
	GDDialogs.prompt(self, "新增状态", "状态 Key", "", func(value: String) -> void: add_state(value), _key_error)


func add_module(key: String, script_value: Script) -> GDGameModuleEntryRes:
	if config == null:
		return null
	var modules := _modules_for(key)
	if key != "@global" and config.find_state(StringName(key)) == null:
		return null
	var entry := GDGameModuleEntryRes.new()
	entry.module_id = config.allocate_module_id()
	entry.set_module_script(script_value)
	entry.display_name = script_value.resource_path.get_file().get_basename() if script_value != null else "模块"
	modules.append(entry)
	_selected_key = key
	_selected_module = entry.module_id
	_commit("新增模块")
	return entry


func change_module_script(module_id: int, script_value: Script) -> void:
	var entry := config.find_module(module_id) if config != null else null
	if entry != null:
		entry.set_module_script(script_value)
		_form.clear()
		_commit("更换模块脚本和参数")


func make_parameters_local(module_id: int) -> void:
	if config == null or _monitor:
		return
	var entry := config.find_module(module_id)
	if entry == null or entry.params == null or entry.params.resource_path.is_empty() or "::" in entry.params.resource_path:
		return
	var params_script := entry.params.get_script() as Script
	if params_script == null or not params_script.is_tool():
		return
	var local_params := entry.params.duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL)
	if local_params == null:
		say("无法复制参数，请检查参数脚本的初始化方法。", &"danger")
		return
	entry.params = local_params
	_commit("复制为内嵌参数")


func _can_add_module(key: String) -> bool:
	return config != null and not _monitor and (key == "@global" or config.find_state(StringName(key)) != null)


func _create_module(key: String) -> void:
	if not _can_add_module(key):
		return
	var target := config
	_select(key, -1)
	var scope_title := "全局模块"
	if key != "@global":
		var state := config.find_state(StringName(key))
		scope_title = "%s [%s]" % [state.display_name, key]
	GDGameModuleCreatorDialog.open(self, func(script_value: Script) -> void:
		_attach_module(target, key, script_value)
	, scope_title)


func _pick_module_script(key: String) -> void:
	if not _can_add_module(key):
		return
	var target := config
	_select(key, -1)
	GDDialogs.open_file(self, "添加模块脚本", PackedStringArray(["*.gd ; GDScript"]), func(path: String) -> void:
		_attach_module(target, key, load(path) as Script)
	)


func _attach_module(target: GDGameModeConfigRes, key: String, script_value: Script) -> void:
	if config != target or not _can_add_module(key):
		say("目标配置或状态已改变，请重新添加模块。", &"warn")
		return
	# 普通业务脚本在编辑器里 can_instantiate() 为 false；编译和继承检查不执行模块。
	if script_value == null or script_value.reload(true) != OK or not GDGameModuleMeta.read(script_value).valid_module:
		say("请选择继承 GDGameFramework.GameModuleBase 的有效模块脚本。", &"danger")
		return
	if not GDGameModuleMeta.can_construct_without_arguments(script_value):
		say("模块的构造函数不能要求必填参数，请为参数提供默认值。", &"danger")
		return
	add_module(key, script_value)


func _modules_for(key: String) -> Array[GDGameModuleEntryRes]:
	if key == "@global":
		return config.global_modules
	var state := config.find_state(StringName(key))
	return state.modules if state != null else []


func delete_selected() -> void:
	if config == null or _monitor:
		return
	if _config_module_id() >= 0:
		var entry := config.find_module(_selected_module)
		_modules_for(_selected_key).erase(entry)
		_selected_module = -1
		_commit("删除模块")
	elif not _selected_key.begins_with("@"):
		var state := config.find_state(StringName(_selected_key))
		if state == null:
			return
		config.states.erase(state)
		if config.default_state_key == state.key:
			config.default_state_key = &""
			for remaining in config.states:
				if remaining != null:
					config.default_state_key = remaining.key
					break
		_selected_key = "@config"
		_commit("删除状态")


func move_selected(direction: int) -> void:
	if config == null or _monitor:
		return
	var list: Array = _modules_for(_selected_key) if _config_module_id() >= 0 else config.states
	var item: Resource = config.find_module(_config_module_id()) if _config_module_id() >= 0 else config.find_state(StringName(_selected_key))
	var index := list.find(item)
	var target := index + direction
	if index < 0 or target < 0 or target >= list.size():
		return
	list.remove_at(index)
	list.insert(target, item)
	_commit("模块排序" if _config_module_id() >= 0 else "状态排序")


func move_nodes(positions: Dictionary) -> void:
	if config == null or _monitor:
		return
	var changed := false
	for key: String in positions:
		if key == "@global":
			changed = changed or config.global_graph_position != positions[key]
			config.global_graph_position = positions[key]
		else:
			var state := config.find_state(StringName(key))
			if state != null:
				changed = changed or state.graph_position != positions[key]
				state.graph_position = positions[key]
	if changed:
		_commit("移动状态节点", true)


func auto_layout() -> void:
	if config == null or _monitor:
		return
	var positions := {"@global": Vector2(40, 40)}
	var index := 0
	for state in config.states:
		if state == null:
			continue
		positions[str(state.key)] = Vector2(340 + (index % 3) * 290, 40 + (index / 3) * 230)
		index += 1
	move_nodes(positions)


func _config_module_id() -> int:
	return int(_selected_module) if _selected_module is int else -1


func _select(key: String, module_id: Variant) -> void:
	_selected_key = key
	_selected_module = module_id
	_sync_tree_selection()
	if _monitor:
		_follow.set_pressed_no_signal(false)
	_graph.select_state(key)
	_refresh_inspector()
	_refresh_status()


func _tree_selected(tree: Tree) -> void:
	if _refreshing:
		return
	var item := tree.get_selected()
	if item != null:
		var data: Dictionary = item.get_metadata(0)
		_select(data.key, data.id)


func _module_tree_context_menu(at: Vector2, button: int, tree: Tree) -> void:
	if button != MOUSE_BUTTON_RIGHT or config == null or _monitor:
		return
	var item := tree.get_item_at_position(at)
	if item == null:
		return
	var data: Dictionary = item.get_metadata(0)
	var key := str(data.key)
	if not _can_add_module(key):
		return
	_select(key, data.id)
	var items: Array = [
		{"text": "新建模块…", "icon": &"Add", "do": _create_module.bind(key)},
		{"text": "添加已有模块…", "icon": &"Load", "do": _pick_module_script.bind(key)},
	]
	if data.id == -1 and key != "@global":
		var is_default := config.default_state_key == StringName(key)
		items.append(null)
		items.append({"text": "已是默认状态" if is_default else "设为默认状态", "do": set_default_state.bind(key), "disabled": is_default})
	GDEditorUi.context_menu(tree, items)


func _sync_tree_selection() -> void:
	var was_refreshing := _refreshing
	_refreshing = true
	for tree: Tree in [_global_tree, _tree]:
		tree.deselect_all()
		_select_tree_branch(tree.get_root())
	_refreshing = was_refreshing


func _select_tree_branch(item: TreeItem) -> void:
	if item == null:
		return
	var data: Variant = item.get_metadata(0)
	if data is Dictionary and data.key == _selected_key and str(data.id) == str(_selected_module):
		item.select(0)
	for child in item.get_children():
		_select_tree_branch(child)


func _refresh() -> void:
	if _graph == null:
		return
	_report = GDGameModeValidation.validate(config) if config != null else {"errors": [], "warnings": [], "issues": []}
	_refresh_tree()
	_refresh_graph()
	_refresh_inspector()
	_refresh_status()
	_refresh_timeline()


func _display_data() -> Dictionary:
	if _monitor:
		var session := _session()
		var snapshot: Dictionary = session.snapshot if session != null else {}
		var states: Array = []
		var globals: Array = []
		var manuals: Array = []
		var modules: Array = snapshot.get("modules", [])
		for module: Dictionary in modules:
			if str(module.get("scope", "")) == "global":
				globals.append(module)
			elif str(module.get("scope", "")) == "manual":
				manuals.append(module)
		var same_config := _same_project(session) and config != null and str(session.welcome.get("config_path", "")) == config.resource_path
		for runtime_state: Dictionary in snapshot.get("states", []):
			var state := runtime_state.duplicate()
			state.modules = []
			for module: Dictionary in modules:
				if str(module.get("scope", "")) == "state:" + str(state.key):
					state.modules.append(module)
			if same_config:
				var binding := config.find_state(StringName(str(state.key)))
				if binding != null:
					state.position = binding.graph_position
			states.append(state)
		return {"states": states, "globals": globals, "manuals": manuals, "transitions": snapshot.get("transitions", []), "current": snapshot.get("current_state_key", ""), "default_state_key": str(snapshot.get("default_state_key", "")), "global_position": config.global_graph_position if same_config else Vector2(40, 40)}
	var states: Array = []
	var globals: Array = []
	if config != null:
		for entry in config.global_modules:
			globals.append(_entry_display(entry))
		for binding in config.states:
			if binding == null:
				continue
			var modules: Array = []
			for entry in binding.modules:
				modules.append(_entry_display(entry))
			var issues := 0
			for issue: Dictionary in _report.get("issues", []):
				if str(issue.get("state_key", "")) == str(binding.key):
					issues += 1
			states.append({"key": str(binding.key), "display_name": binding.display_name, "modules": modules, "position": binding.graph_position, "issues": issues})
	var global_issues := 0
	for issue: Dictionary in _report.get("issues", []):
		if str(issue.get("state_key", "")) == "global":
			global_issues += 1
	return {"states": states, "globals": globals, "transitions": [], "current": "", "default_state_key": str(config.default_state_key) if config != null else "", "global_position": config.global_graph_position if config != null else Vector2(40, 40), "global_issues": global_issues}


func _entry_display(entry: GDGameModuleEntryRes) -> Dictionary:
	if entry == null:
		return {"id": -1, "display_name": "缺失模块", "issues": 1}
	var count := 0
	for issue: Dictionary in _report.get("issues", []):
		if int(issue.get("module_id", -1)) == entry.module_id:
			count += 1
	return {"id": entry.module_id, "display_name": entry.display_name, "issues": count}


func _refresh_tree() -> void:
	if _tree == null:
		return
	_refreshing = true
	_tree.clear()
	_global_tree.clear()
	var root := _tree.create_item()
	var data := _display_data()
	var globals := _tree_item(_global_tree, _global_tree.create_item(), "全局模块", "@global", -1)
	globals.set_custom_color(0, GDGameModeGraph.global_color())
	_add_tree_modules(_global_tree, globals, data.globals, "@global")
	var global_rows := 1
	for child in globals.get_children():
		if child.visible:
			global_rows += 1
	var row_gap := _global_tree.get_theme_constant("v_separation")
	var row_height := maxf(GDEditorUi.ROW_HEIGHT, _global_tree.get_theme_font("font").get_height(_global_tree.get_theme_font_size("font_size")) + row_gap * 2)
	_global_tree.custom_minimum_size.y = mini(global_rows, 4) * row_height + _global_tree.get_theme_stylebox("panel").get_minimum_size().y + row_gap * 2
	if not data.get("manuals", []).is_empty():
		var manual_group := _tree_item(_tree, root, "手动模块（只读）", "@manual", -1)
		_add_tree_modules(_tree, manual_group, data.manuals, "@manual")
	for state: Dictionary in data.states:
		var caption := "%s [%s]" % [state.display_name, state.key]
		if str(state.key) == str(data.default_state_key):
			caption += " · 默认"
		var item := _tree_item(_tree, root, caption, str(state.key), -1)
		_add_tree_modules(_tree, item, state.modules, str(state.key))
		item.visible = _search.text.is_empty() or _search.text.to_lower() in item.get_text(0).to_lower() or _any_visible_child(item)
	_refreshing = false


func _tree_item(tree: Tree, parent: TreeItem, caption: String, key: String, module_id: Variant) -> TreeItem:
	var item := tree.create_item(parent)
	item.set_text(0, caption)
	item.set_metadata(0, {"key": key, "id": module_id})
	if _selected_key == key and str(_selected_module) == str(module_id):
		item.select(0)
	return item


func _add_tree_modules(tree: Tree, parent: TreeItem, modules: Array, key: String) -> void:
	for module: Dictionary in modules:
		var item := _tree_item(tree, parent, "#%s %s" % [str(module.get("id", -1)), module.get("display_name", "模块")], key, module.get("id", -1))
		item.visible = _search.text.is_empty() or _search.text.to_lower() in item.get_text(0).to_lower()


static func _any_visible_child(item: TreeItem) -> bool:
	for child in item.get_children():
		if child.visible:
			return true
	return false


func _refresh_graph() -> void:
	var data := _display_data()
	_graph.layout_enabled = config != null and not _monitor
	_graph.display(data.states, data.globals, data.transitions, str(data.current), _monitor, data.global_position, int(data.get("global_issues", 0)), str(data.default_state_key))
	if _monitor and _follow.button_pressed and not str(data.current).is_empty():
		_selected_key = str(data.current)
		_selected_module = -1
		_graph.select_state(_selected_key, _last_follow_key != _selected_key)
		_last_follow_key = _selected_key
	else:
		_graph.select_state(_selected_key)
	_sync_tree_selection()


func _refresh_inspector() -> void:
	if _monitor:
		_refresh_monitor_inspector()
		return
	if config == null:
		if _form.begin("empty"):
			_form.heading("游戏进程", "新建或打开配置，然后在场景中添加 GDGameModeBootstrap。")
		return
	var entry := config.find_module(_config_module_id())
	var state := config.find_state(StringName(_selected_key))
	var state_keys: Array = []
	for binding in config.states:
		if binding != null:
			state_keys.append(str(binding.key))
	var key := [config, _selected_key, _selected_module, entry.module_script if entry != null else null, entry.params if entry != null else null, state_keys]
	if _form.begin(key):
		if entry != null:
			_form.heading("模块 #%d" % entry.module_id, "范围：" + _selected_key)
			_form.auto(entry, {"only": ["display_name"], "labels": {"display_name": "显示名"}})
			_form.note(entry.script_path())
			var meta := GDGameModuleMeta.read(entry.module_script)
			_form.note("分类：%s · Tick：%s · 可独立重启：%s" % [meta.get("category", 2), meta.get("tick_enabled", true), meta.get("debug_restartable", false)])
			_form.button("打开代码", open_source.bind(entry.module_id))
			_form.button("重新指定脚本", func() -> void:
				GDDialogs.open_file(self, "更换脚本（参数类型改变时重置参数）", PackedStringArray(["*.gd ; GDScript"]), func(path: String) -> void: change_module_script(entry.module_id, load(path) as Script))
			)
			if entry.params != null:
				_form.heading("参数")
				var params_script := entry.params.get_script() as Script
				var external := not entry.params.resource_path.is_empty() and not "::" in entry.params.resource_path
				var readonly := external or (params_script != null and not params_script.is_tool())
				if external:
					_form.note("参数引用外部资源，当前配置不会保存其内容。复制为内嵌参数后可独立编辑。", &"warn")
					_form.note(entry.params.resource_path)
					if params_script != null and params_script.is_tool():
						_form.button("复制为内嵌参数", make_parameters_local.bind(entry.module_id))
				if params_script != null and not params_script.is_tool():
					_form.note("参数脚本没有 @tool，编辑器中只读。", &"warn")
				_form.auto(entry.params, {"readonly": readonly})
		elif state != null:
			_form.heading("状态", "Key：" + str(state.key))
			_form.auto(state, {"only": ["display_name"], "labels": {"display_name": "显示名"}})
			_form.button("修改 Key…", func() -> void:
				var old_key := str(state.key)
				GDDialogs.prompt(self, "修改 Key 会影响引用此 Key 的业务代码", "新的 Key", old_key, func(value: String) -> void: rename_state_key(old_key, value), func(value: String) -> String: return _key_error(value, old_key))
			)
		else:
			_form.heading("配置" if _selected_key == "@config" else "全局模块")
			_form.auto(config, {"only": ["display_name", "tick_when_paused"], "labels": {"display_name": "配置名称", "tick_when_paused": "暂停时 Tick"}})
			var items: Array = []
			for index in range(config.states.size()):
				if config.states[index] != null:
					items.append([str(config.states[index].key), index])
			_form.choice("默认状态", items, func() -> int: return config.states.find(config.find_state(config.default_state_key)), func(index: int) -> void:
				if index >= 0 and index < config.states.size():
					config.default_state_key = config.states[index].key
			)
		_form.live_note(_validation_text)
	_form.sync()


func _validation_text() -> String:
	var lines := PackedStringArray()
	for issue: Dictionary in _report.get("issues", []):
		if _config_module_id() >= 0 and int(issue.get("module_id", -1)) != _selected_module:
			continue
		if _config_module_id() < 0 and not _selected_key.begins_with("@") and str(issue.get("state_key", "")) != _selected_key:
			continue
		lines.append("%s: %s" % [issue.get("severity", ""), issue.get("message", "")])
	return "校验通过" if lines.is_empty() else "\n".join(lines)


func _refresh_monitor_inspector() -> void:
	var session := _session()
	var snapshot: Dictionary = session.snapshot if session != null else {}
	var module: Dictionary = {}
	for candidate: Dictionary in snapshot.get("modules", []):
		if str(candidate.get("id", -1)) == str(_selected_module):
			module = candidate
	if not _form.begin(["monitor", _session_id, _selected_key, _selected_module, var_to_str(module)]):
		return
	_form.heading("运行监控 · 只读", "当前状态：" + str(snapshot.get("current_state_key", "—")))
	if not module.is_empty():
		var labels := {"display_name": "显示名", "id": "模块 ID", "scope": "所属范围", "script_path": "脚本", "category": "分类", "config_order": "配置顺序", "initialization_order": "初始化顺序", "lifecycle": "生命周期", "instance_serial": "实例序号", "tick_enabled": "允许 Tick", "is_ticking": "正在 Tick", "debug_restartable": "可独立重启", "last_fault": "最近故障"}
		for field in ["display_name", "id", "scope", "script_path", "category", "config_order", "initialization_order", "lifecycle", "instance_serial", "tick_enabled", "is_ticking", "debug_restartable", "last_fault"]:
			_form.note("%s：%s" % [labels[field], str(module.get(field, "—"))])
		_form.button("打开代码", open_source.bind(_selected_module))
	_form.button("在配置中定位", _locate_in_config)


static func _same_project(session: GDGameModeSession) -> bool:
	return session != null and GDGameModeSession._normalized_project(str(session.welcome.get("project_path", ""))) == GDGameModeSession._normalized_project(ProjectSettings.globalize_path("res://"))


func _locate_in_config() -> void:
	if not _selected_module is int:
		say("手动注册的模块不属于配置资产，只能查看运行详情和源码。")
		return
	var session := _session()
	if not _same_project(session):
		say("运行配置来自其他工程，无法在本工程中定位。", &"warn")
		return
	var path := str(session.welcome.get("config_path", ""))
	var key := _selected_key
	var module_id: Variant = _selected_module
	if config == null or config.resource_path != path:
		if not ResourceLoader.exists(path):
			say("本工程中找不到运行配置：" + path, &"warn")
			return
		load_config_path(path)
	_monitor = false
	_view_picker.select(0)
	_selected_key = key
	_selected_module = module_id
	_form.clear()
	_refresh()


func open_source(module_id: Variant) -> void:
	var script_value: Script
	if _monitor:
		var session := _session()
		if session != null:
			for entry: Dictionary in session.snapshot.get("modules", []):
				if str(entry.get("id", -1)) == str(module_id):
					var path := str(entry.get("script_path", ""))
					if ResourceLoader.exists(path):
						script_value = load(path) as Script
	elif config != null and module_id is int:
		var entry := config.find_module(module_id)
		if entry != null:
			script_value = entry.module_script
	if script_value == null:
		say("脚本缺失，请在配置详情中重新指定脚本。", &"warn")
		return
	if Engine.is_editor_hint():
		EditorInterface.edit_script(script_value)
		var external := bool(EditorInterface.get_editor_settings().get_setting("text_editor/external/use_external_editor"))
		if not external:
			EditorInterface.set_main_screen_editor("Script")
			var window := EditorInterface.get_base_control().get_window()
			window.grab_focus()
			DisplayServer.window_move_to_foreground(window.get_window_id())


func _session() -> GDGameModeSession:
	return _debugger.get_session_model(_session_id) if is_instance_valid(_debugger) else null


func _sessions_changed() -> void:
	_session_picker.clear()
	if is_instance_valid(_debugger):
		for id: int in _debugger.sessions:
			_session_picker.add_item(_debugger.get_session_model(id).label(), id)
		if not _debugger.sessions.has(_session_id) and not _debugger.sessions.is_empty():
			_session_id = int(_debugger.sessions.keys()[0])
	if _session_picker.item_count == 0:
		_session_picker.add_item("未连接", -1)
		_session_id = -1
	_session_picker.select(_session_picker.get_item_index(_session_id))
	if _monitor:
		_refresh_tree()
		_refresh_graph()
		_refresh_inspector()
	_refresh_status()
	_refresh_timeline()


func application_status() -> String:
	var session := _session()
	if session == null or not session.connected:
		return "未连接"
	if config == null:
		return "运行端使用其他配置：" + str(session.welcome.get("config_path", ""))
	if doc.dirty or config.resource_path.is_empty():
		return "未保存"
	if not _same_project(session) or str(session.welcome.get("config_path", "")) != config.resource_path:
		return "运行端使用其他配置：" + str(session.welcome.get("config_path", ""))
	return "已应用" if config.runtime_digest() == str(session.welcome.get("config_digest", "")) else "已保存，未应用"


func _refresh_visibility() -> void:
	var has_config := config != null
	# 无配置时隐藏通用文档操作及分隔符，只保留新建和打开。
	for control: Control in toolbar.get_parent().get_children():
		control.visible = has_config or control == toolbar
	for control: Control in toolbar.get_children():
		control.visible = has_config or control == _new_button or control == _open_button
	_status_row.visible = has_config
	_bottom_split.visible = has_config


func _refresh_status() -> void:
	if _status_label == null:
		return
	_refresh_visibility()
	_add_state_button.disabled = config == null or _monitor
	var session := _session()
	_status_label.text = "%s · 当前：%s · %s" % [session.status_text() if session != null else "未连接", session.snapshot.get("current_state_key", "—") if session != null else "—", application_status()]
	var enabled := session != null and session.can_command()
	for button in _command_buttons:
		button.disabled = not enabled
	if _command_buttons.size() == 3:
		_command_buttons[0].disabled = not enabled or not _runtime_has_state(_selected_key)
		_command_buttons[2].disabled = not enabled or not _runtime_restartable()
	_apply_button.disabled = not enabled or config == null or not _report.get("errors", []).is_empty() or not session.can_apply()
	_apply_button.tooltip_text = session.apply_block_reason() if session != null else "未连接运行实例"
	_command_result_label.text = ""
	if session != null:
		if not session.pending_request.is_empty():
			_command_result_label.text = "无回执：命令未自动重试，请等待或重新连接。" if session.timed_out else "命令已发送，等待运行端回执…"
		elif not session.last_result.is_empty():
			_command_result_label.text = "%s · %s" % [session.last_result.get("code", ""), session.last_result.get("message", "")]
	_command_result_label.visible = not _command_result_label.text.is_empty()
	_graph.modulate = Color.WHITE if not _monitor or (session != null and session.connected) else Color(0.6, 0.6, 0.6)


func _runtime_restartable() -> bool:
	var session := _session()
	if session == null or not _selected_module is int:
		return false
	if not _monitor and (config == null or not _same_project(session) or config.resource_path != str(session.welcome.get("config_path", ""))):
		return false
	for entry: Dictionary in session.snapshot.get("modules", []):
		if str(entry.get("id", -1)) == str(_selected_module):
			return bool(entry.get("debug_restartable", entry.get("restartable", false))) and int(entry.get("instance_serial", 0)) > 0
	return false


func _runtime_has_state(key: String) -> bool:
	var session := _session()
	if session != null:
		for state: Dictionary in session.snapshot.get("states", []):
			if str(state.get("key", "")) == key:
				return true
	return false


func _send_command(kind: String) -> void:
	var session := _session()
	if session == null or not session.can_command():
		return
	var args := {}
	if kind == "switch_state":
		if not _runtime_has_state(_selected_key):
			return
		args = {"key": _selected_key}
	elif kind == "restart_module":
		if not _runtime_restartable():
			return
		args = {"module_id": _selected_module}
	session.send_command(kind, args)
	_refresh_status()


func _apply_config() -> void:
	var session := _session()
	if session == null or config == null or not session.can_apply() or not _report.get("errors", []).is_empty():
		return
	save_current()
	if doc.dirty or config.resource_path.is_empty():
		say("配置尚未成功保存，保存后再应用。", &"warn")
		return
	session.send_command("apply_config", {"path": config.resource_path, "expected_digest": config.runtime_digest()})
	_refresh_status()


func _refresh_timeline() -> void:
	var session := _session()
	var events: Array = session.events if session != null else []
	var signature := "%d/%s/%d/%s/%d" % [_session_id, events.back().get("seq", 0) if not events.is_empty() else 0, _kind_filter.selected, _module_filter.text, events.size()]
	if signature == _timeline_signature:
		return
	_timeline_signature = signature
	_timeline.clear()
	var filter := "" if _kind_filter.selected == 0 else _kind_filter.get_item_text(_kind_filter.selected)
	for event: Dictionary in events:
		if not filter.is_empty() and not str(event.get("kind", "")).begins_with(filter):
			continue
		if not _module_filter.text.is_empty() and str(event.get("module_id", -1)) != _module_filter.text:
			continue
		var line := "#%s · 帧 %s · G%s · %s · %s · 模块 %s · %s" % [event.get("seq", 0), event.get("frame", 0), event.get("generation", 0), event.get("kind", ""), event.get("state_key", ""), event.get("module_id", -1), event.get("result", "")]
		var index := _timeline.add_item(line)
		_timeline.set_item_tooltip(index, str(event.get("detail", {})))
	if _timeline.item_count > 0:
		_timeline.ensure_current_is_visible()


func _open_sample() -> void:
	# Factory generation is idempotent and never changes the project's main scene.
	load_config(GDSampleFactory.load_game_mode_config())
	if Engine.is_editor_hint():
		EditorInterface.open_scene_from_path(GDSampleFactory.GAME_MODE_SCENE_PATH)
