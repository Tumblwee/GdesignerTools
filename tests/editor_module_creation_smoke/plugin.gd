@tool
extends EditorPlugin

## SceneTree -s tests do not reproduce editor-only script execution restrictions.
var failures := 0
var passes := 0
var _window: GdesignerToolsWindow
var _fixture := ""
var _created_paths: Array[String] = []
var _started_at := 0
var _done := false


func _enter_tree() -> void:
	if ProjectSettings.get_setting("application/config/name", "") != "GdesignerTools Module Creation Validation":
		push_error("Module creation editor smoke requires an isolated Validation project.")
		set_process(false)
		return
	_started_at = Time.get_ticks_msec()
	set_process(true)
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not _done and Time.get_ticks_msec() - _started_at > 30000:
		_check(false, "editor module creation completed before timeout")
		_finish()


func _check(ok: bool, message: String) -> void:
	if ok:
		passes += 1
		print("MODULE_EDITOR PASS: ", message)
	else:
		failures += 1
		push_error("MODULE_EDITOR FAIL: " + message)


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_fixture = "res://_module_editor_smoke_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_fixture)
	_window = GdesignerToolsWindow.new()
	EditorInterface.get_base_control().add_child(_window)
	_window.present(4)
	var page := _window.dock.game_mode_editor
	page.new_config()
	_check(Engine.is_editor_hint(), "regression runs in the real editor context")
	page._create_module("login")
	var dialog := _creator(page)
	_check(dialog != null, "new module opens its dialog in the tools window")
	if dialog == null:
		_finish()
		return
	var name := "EditorCreated_%d" % Time.get_ticks_usec()
	var path := GDGameModuleCreatorDialog.DEFAULT_DIRECTORY.path_join(name + ".gd")
	_created_paths.append(path)
	dialog._name_edit.text = name
	dialog._name_edit.text_changed.emit(name)
	dialog.confirmed.emit()
	var state := page.config.find_state(&"login")
	_check(FileAccess.file_exists(path), "new module code is saved in the default project code directory")
	_check(state.modules.size() == 1, "ordinary non-tool module attaches to the clicked state in the editor")
	var saved_script := ResourceLoader.load(path) as Script
	_check(saved_script != null and not saved_script.is_tool() and not saved_script.can_instantiate(), "fixture reproduces editor execution restrictions for ordinary scripts")
	_check(saved_script != null and GDGameModuleMeta.read(saved_script).valid_module, "ordinary module still has valid GameModuleBase inheritance")
	if state.modules.size() == 1:
		var entry := state.modules[0]
		_check(entry.script_path() == path and entry.display_name == name, "attached module retains its generated code reference and name")
		page.doc.undo()
		_check(state.modules.is_empty() and FileAccess.file_exists(path), "editor undo removes the binding and preserves generated code")
		page.doc.redo()
		_check(state.modules.size() == 1 and state.modules[0] == entry, "editor redo restores the same module")
	page._attach_module(page.config, "@global", saved_script)
	_check(page.config.global_modules.size() == 1, "adding an existing ordinary script also succeeds in the editor")
	var sentinel_path := _fixture.path_join("constructor_ran.txt")
	var tool_path := _fixture.path_join("ToolProbe.gd")
	_created_paths.append(tool_path)
	var file := FileAccess.open(tool_path, FileAccess.WRITE)
	file.store_string('@tool\nextends GDGameFramework.GameModuleBase\nconst MODULE_CATEGORY := GDCoreTypes.ModuleCategory.MISC\nfunc _init() -> void:\n\tFileAccess.open("%s", FileAccess.WRITE).store_string("unexpected")\n' % sentinel_path)
	file.close()
	page._attach_module(page.config, "@global", ResourceLoader.load(tool_path) as Script)
	_check(not FileAccess.file_exists(sentinel_path), "validating and attaching a tool module never executes its constructor")
	var config_path := _fixture.path_join("Config.tres")
	_created_paths.append(config_path)
	page.prepare_save(page.doc)
	_check(page.doc.save(config_path) == OK, "editor-created configuration saves")
	var reloaded := ResourceLoader.load(config_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDGameModeConfigRes
	_check(reloaded != null and reloaded.find_state(&"login").modules.size() == 1 and reloaded.find_state(&"login").modules[0].script_path() == path, "saved configuration reloads the module code reference")
	_finish()


func _creator(page: GDGameModePage) -> GDGameModuleCreatorDialog:
	for child in page.get_children():
		if child is GDGameModuleCreatorDialog and child.visible:
			return child
	return null


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	if is_instance_valid(_window):
		_window.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for path in _created_paths:
		DirAccess.remove_absolute(path)
		if FileAccess.file_exists(path + ".uid"):
			DirAccess.remove_absolute(path + ".uid")
	if not _fixture.is_empty():
		DirAccess.remove_absolute(_fixture.path_join("constructor_ran.txt"))
		DirAccess.remove_absolute(_fixture)
	print("MODULE_EDITOR_SMOKE: %s passes=%d failures=%d" % ["SUCCESS" if failures == 0 else "FAILED", passes, failures])
	get_tree().quit(1 if failures else 0)
