extends SceneTree

var passes := 0
var failures := 0
var _fixture_root: String
var _default_path: String
var _default_directory_existed := false
var _scripts_directory_existed := false


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, description: String) -> void:
	if ok:
		passes += 1
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _run() -> void:
	if not str(ProjectSettings.get_setting("application/config/name", "")).contains("Validation"):
		push_error("Run module creation tests only in an isolated Validation project.")
		quit(1)
		return
	root.gui_embed_subwindows = true
	root.position = Vector2i.ZERO
	root.size = Vector2i(1280, 900)
	root.content_scale_size = root.size
	_fixture_root = "res://_module_creation_test_%d" % Time.get_ticks_usec()
	_default_directory_existed = DirAccess.dir_exists_absolute("res://scripts/game_mdl")
	_scripts_directory_existed = DirAccess.dir_exists_absolute("res://scripts")
	DirAccess.make_dir_recursive_absolute(_fixture_root)
	await _test_cancel_and_collisions()
	await _test_menu_creation()
	await process_frame
	_cleanup_fixture(_fixture_root)
	if not _default_path.is_empty():
		DirAccess.remove_absolute(_default_path)
		if FileAccess.file_exists(_default_path + ".uid"):
			DirAccess.remove_absolute(_default_path + ".uid")
	if not _default_directory_existed:
		_remove_empty_directory("res://scripts/game_mdl")
	if not _scripts_directory_existed:
		_remove_empty_directory("res://scripts")
	print("TOTAL PASSED: %d FAILED: %d" % [passes, failures])
	quit(failures)


func _test_cancel_and_collisions() -> void:
	var page := GDGameModePage.new()
	root.add_child(page)
	page.new_config()
	var original := page.config
	page._create_module("login")
	var dialog := _creator_for(page)
	_check(dialog != null and dialog.get_ok_button().disabled, "new module requires a name before creating code")
	if dialog == null:
		page.queue_free()
		return
	var cancel_directory := _fixture_root.path_join("cancel_should_not_exist")
	dialog._directory = cancel_directory
	_set_name(dialog, "CanceledModule")
	dialog.canceled.emit()
	dialog.hide()
	_check(not DirAccess.dir_exists_absolute(cancel_directory) and original.find_state(&"login").modules.is_empty(), "cancel creates neither code directory nor module binding")
	_check(DirAccess.dir_exists_absolute("res://scripts/game_mdl") == _default_directory_existed, "opening and canceling does not create the default code directory")
	await process_frame
	await process_frame
	page._create_module("login")
	dialog = _creator_for(page)
	dialog._directory = _fixture_root
	_set_name(dialog, "ExistingModule")
	_check(not dialog.get_ok_button().disabled, "an unused destination is initially available")
	var occupied := _fixture_root.path_join("ExistingModule.gd")
	var existing_source := "extends RefCounted\n# Existing project code must survive.\n"
	FileAccess.open(occupied, FileAccess.WRITE).store_string(existing_source)
	dialog.confirmed.emit()
	_check(FileAccess.get_file_as_string(occupied) == existing_source, "a script appearing after the dialog opens is never overwritten")
	_check(dialog.visible and dialog._error_label.visible and original.find_state(&"login").modules.is_empty(), "name conflict keeps the dialog open and leaves configuration untouched")
	_set_name(dialog, "../EscapedModule")
	dialog.confirmed.emit()
	_check(dialog.get_ok_button().disabled and not FileAccess.file_exists("res://EscapedModule.gd"), "module names cannot escape the selected code directory")
	dialog._directory = "user://module_creation_outside_project"
	_set_name(dialog, "OutsideModule")
	dialog.confirmed.emit()
	_check(dialog.get_ok_button().disabled and not FileAccess.file_exists("user://module_creation_outside_project/OutsideModule.gd"), "code creation rejects locations outside the project")
	dialog._directory = _fixture_root
	DirAccess.make_dir_recursive_absolute(_fixture_root.path_join("OccupiedDirectory.gd"))
	_set_name(dialog, "OccupiedDirectory")
	dialog.confirmed.emit()
	_check(DirAccess.dir_exists_absolute(_fixture_root.path_join("OccupiedDirectory.gd")) and original.find_state(&"login").modules.is_empty(), "a directory at the script path is preserved and cannot become a module")
	dialog.hide()
	await process_frame
	page.queue_free()
	await process_frame


func _test_menu_creation() -> void:
	var page := GDGameModePage.new()
	root.add_child(page)
	page.size = Vector2(1200, 800)
	page.new_config()
	page.add_state("game", "游戏")
	page.doc.mark_saved()
	await process_frame
	await process_frame
	page._select("game", -1)
	var menu := _menu_for_node(page._graph, "login")
	var create_index := _item_index(menu, "新建模块…")
	_check(create_index >= 0 and not menu.is_item_disabled(create_index), "state node context menu offers module creation")
	if create_index < 0:
		page.queue_free()
		return
	_activate_item(menu, create_index)
	var dialog := _creator_for(page)
	_check(dialog != null and "login" in dialog.title, "right-click creation targets the clicked state instead of the previously selected state")
	if dialog == null:
		page.queue_free()
		return
	var module_name := "ModuleCreationTest_%d" % Time.get_ticks_usec()
	_set_name(dialog, module_name)
	_default_path = "res://scripts/game_mdl/" + module_name + ".gd"
	_check(dialog._path_edit.text == _default_path, "default module code location is scripts/game_mdl in the project")
	dialog.confirmed.emit()
	var login := page.config.find_state(&"login")
	var game := page.config.find_state(&"game")
	_check(FileAccess.file_exists(_default_path) and login.modules.size() == 1 and game.modules.is_empty() and page.config.global_modules.is_empty(), "creating from a state menu writes code and attaches only to that state")
	if login.modules.is_empty():
		page.queue_free()
		return
	var module := login.modules[0]
	var reloaded := ResourceLoader.load(_default_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
	_check(reloaded != null and reloaded.can_instantiate() and GDGameModuleMeta.read(reloaded).valid_module, "new code reloads as a compilable GameModuleBase script")
	_check(module.module_script.resource_path == _default_path and page.doc.dirty, "new module retains the code path and marks its configuration unsaved")
	var source_hash := FileAccess.get_sha256(_default_path)
	page.doc.undo()
	_check(login.modules.is_empty() and FileAccess.get_sha256(_default_path) == source_hash, "undo removes the module binding while preserving generated code")
	page.doc.redo()
	_check(login.modules.size() == 1 and login.modules[0] == module, "redo restores the original module binding")
	await process_frame
	await process_frame
	page._select("login", module.module_id)
	menu = _menu_for_node(page._graph, "@global")
	create_index = _item_index(menu, "新建模块…")
	_check(create_index >= 0, "global node context menu also offers module creation")
	if create_index < 0:
		page.queue_free()
		return
	_activate_item(menu, create_index)
	dialog = _creator_for(page)
	var custom_directory := _fixture_root.path_join("custom_code")
	DirAccess.make_dir_recursive_absolute(custom_directory)
	var folder_button := _button_with_tooltip(dialog, "自定义代码位置")
	_check(folder_button != null, "new module dialog exposes a custom code location icon button")
	if folder_button == null:
		page.queue_free()
		return
	folder_button.pressed.emit()
	var directory_dialog: FileDialog = null
	for child in dialog.get_children():
		if child is FileDialog:
			directory_dialog = child
	_check(directory_dialog != null and directory_dialog.file_mode == FileDialog.FILE_MODE_OPEN_DIR and directory_dialog.access == FileDialog.ACCESS_RESOURCES, "custom location button opens a project directory chooser")
	if directory_dialog == null:
		page.queue_free()
		return
	directory_dialog.dir_selected.emit(custom_directory)
	directory_dialog.hide()
	_set_name(dialog, "CustomGlobalModule")
	var custom_path := custom_directory.path_join("CustomGlobalModule.gd")
	_check(dialog._path_edit.text == custom_path, "choosing a custom directory updates the final code path")
	dialog.confirmed.emit()
	_check(FileAccess.file_exists(custom_path) and page.config.global_modules.size() == 1 and page.config.global_modules[0].script_path() == custom_path and login.modules.size() == 1, "custom-location creation attaches to the clicked global node")
	page.prepare_save(page.doc)
	var config_path := _fixture_root.path_join("Config.tres")
	_check(page.doc.save(config_path) == OK, "configuration with newly generated modules saves successfully")
	var saved_config := ResourceLoader.load(config_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDGameModeConfigRes
	var saved_login := saved_config.find_state(&"login") if saved_config != null else null
	_check(saved_login != null and saved_login.modules.size() == 1 and saved_login.modules[0].module_script != null and saved_login.modules[0].script_path() == _default_path and saved_config.global_modules.size() == 1 and saved_config.global_modules[0].module_script != null and saved_config.global_modules[0].script_path() == custom_path, "saved configuration reloads both default-location and custom-location module script references")
	await process_frame
	await process_frame
	page._monitor = true
	page._refresh()
	await process_frame
	menu = _menu_for_node(page._graph, "@global")
	create_index = _item_index(menu, "新建模块…")
	var add_index := _item_index(menu, "添加已有模块…")
	_check(create_index >= 0 and add_index >= 0 and menu.is_item_disabled(create_index) and menu.is_item_disabled(add_index), "runtime monitoring disables both module-adding menu actions")
	menu.hide()
	page._create_module("@global")
	_check(_creator_for(page) == null, "monitoring cannot open the creation dialog through its page action")
	page._attach_module(page.config, "@global", reloaded)
	_check(page.config.global_modules.size() == 1, "monitoring also rejects a pending module attachment")
	await process_frame
	page.queue_free()
	await process_frame


func _set_name(dialog: GDGameModuleCreatorDialog, value: String) -> void:
	dialog._name_edit.text = value
	dialog._name_edit.text_changed.emit(value)


func _creator_for(page: GDGameModePage) -> GDGameModuleCreatorDialog:
	for child in page.get_children():
		if child is GDGameModuleCreatorDialog and child.visible:
			return child
	return null


func _menu_for_node(graph: GDGameModeGraph, key: String) -> PopupMenu:
	var node: GraphNode = graph._nodes[key]
	var canvas_position := node.get_global_transform_with_canvas() * (node.size * 0.5)
	graph._show_context_menu(graph.get_global_transform_with_canvas().affine_inverse() * canvas_position)
	for index in range(graph.get_child_count() - 1, -1, -1):
		var child := graph.get_child(index)
		if child is PopupMenu and child.visible:
			return child
	return null


func _item_index(menu: PopupMenu, caption: String) -> int:
	if menu == null:
		return -1
	for index in range(menu.item_count):
		if menu.get_item_text(index) == caption:
			return index
	return -1


func _activate_item(menu: PopupMenu, index: int) -> void:
	var id := menu.get_item_id(index)
	menu.hide()
	menu.id_pressed.emit(id)


func _button_with_tooltip(node: Node, tip: String) -> Button:
	if node is Button and node.tooltip_text == tip:
		return node
	for child in node.get_children():
		var found := _button_with_tooltip(child, tip)
		if found != null:
			return found
	return null


func _cleanup_fixture(directory: String) -> void:
	var allowed := ProjectSettings.globalize_path(_fixture_root).simplify_path()
	var absolute := ProjectSettings.globalize_path(directory).simplify_path()
	if absolute != allowed and not absolute.begins_with(allowed + "/"):
		return
	for child in DirAccess.get_directories_at(directory):
		_cleanup_fixture(directory.path_join(child))
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)


func _remove_empty_directory(directory: String) -> void:
	if DirAccess.dir_exists_absolute(directory) and DirAccess.get_files_at(directory).is_empty() and DirAccess.get_directories_at(directory).is_empty():
		DirAccess.remove_absolute(directory)
