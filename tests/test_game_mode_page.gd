extends SceneTree

var passes := 0
var failures := 0

class SessionPage extends GDGameModePage:
	var test_session: GDGameModeSession
	func _session() -> GDGameModeSession:
		return test_session

class FormParams extends Resource:
	@export var key: StringName = &"before"
	@export var tint: Color = Color.RED
	@export var unsupported: Array = [1, 2]


class RequiredParams extends Resource:
	func _init(_required: String) -> void:
		pass

class RequiredParamsModule extends GDGameFramework.GameModuleBase:
	const PARAMS_SCRIPT := RequiredParams
	const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.MISC

class InvalidParams extends RefCounted:
	static var constructions := 0
	func _init() -> void:
		constructions += 1

class InvalidParamsModule extends GDGameFramework.GameModuleBase:
	const PARAMS_SCRIPT := InvalidParams
	const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.MISC


func _test_parameter_constructor_guard() -> void:
	var page := SessionPage.new()
	root.add_child(page)
	page.new_config()
	var entry := page.add_module("login", RequiredParamsModule)
	_check(entry != null and entry.module_script == RequiredParamsModule and entry.params == null, "module with required parameter constructor remains repairable without invoking an invalid new call")
	_check(not GDGameModeValidation.validate(page.config).ok, "required parameter constructor is reported by configuration validation")
	var valid_script: Script = load("res://addons/gdesigner_tools/sample/game_mode/sample_login_module.gd")
	page.change_module_script(entry.module_id, valid_script)
	var valid_params := entry.params
	_check(valid_params != null and GDGameModeValidation.validate(page.config).ok, "changing to a valid parameter script repairs the module")
	page.doc.undo()
	_check(entry.module_script == RequiredParamsModule and entry.params == null, "undo restores the invalid parameter declaration without instantiation")
	page.doc.redo()
	_check(entry.module_script == valid_script and entry.params == valid_params, "redo restores the already-created valid parameters")
	var before := InvalidParams.constructions
	page.change_module_script(entry.module_id, InvalidParamsModule)
	_check(entry.params == null and InvalidParams.constructions == before, "non-Resource parameter declarations are rejected before running their constructors")
	_check(not GDGameModeValidation.validate(page.config).ok, "non-Resource parameter declarations remain visible to validation")
	await process_frame
	page.queue_free()
	await process_frame


func _test_form_fields() -> void:
	var params := FormParams.new()
	var document := GDDocument.new(params)
	var form := GDForm.new()
	root.add_child(form)
	form.committed.connect(func(label: String, merge: bool) -> void: document.commit(label, merge))
	form.auto(params)
	var name_edit := form.get_child(0).get_child(1) as LineEdit
	name_edit.text = "after"
	name_edit.text_submitted.emit("after")
	_check(params.key == &"after" and typeof(params.key) == TYPE_STRING_NAME, "StringName field retains type")
	document.undo()
	_check(params.key == &"before", "StringName parameter undo")
	var color_picker := form.get_child(1).get_child(1) as ColorPickerButton
	color_picker.color_changed.emit(Color.BLUE)
	_check(params.tint == Color.BLUE, "Color parameter editing")
	document.undo()
	_check(params.tint == Color.RED, "Color parameter undo")
	_check("首版不支持编辑" in (form.get_child(2) as Label).text, "unsupported parameter type is explicitly read only")
	form.free()


func _test_default_states() -> void:
	var page := SessionPage.new()
	root.add_child(page)
	_check(not page.set_default_state("entry"), "default cannot be set without a configuration")
	var empty := GDGameModeConfigRes.new()
	var previous_default := empty.default_state_key
	page.load_config(empty)
	var first := page.add_state("entry", "入口")
	_check(first != null and empty.default_state_key == &"entry", "first added state replaces the empty configuration default")
	page.doc.undo()
	_check(empty.states.is_empty() and empty.default_state_key == previous_default, "undo first state restores the previous default atomically")
	page.doc.redo()
	_check(empty.find_state(&"entry") == first and empty.default_state_key == &"entry", "redo first state restores its default designation")
	page.add_state("game", "游戏")
	_check(empty.default_state_key == &"entry", "adding a later state preserves the default")
	_check(page.set_default_state("game") and empty.default_state_key == &"game", "existing state can be made the default")
	page.doc.undo()
	_check(empty.default_state_key == &"entry", "undo default change")
	page.doc.redo()
	_check(empty.default_state_key == &"game", "redo default change")
	var last := page.add_state("credits", "结束")
	page.move_selected(-1)
	_check(empty.states[1] == last and empty.default_state_key == &"game", "adding and reordering states preserve the chosen default")
	page.doc.mark_saved()
	_check(not page.set_default_state("missing") and not page.set_default_state("@global") and not page.set_default_state(""), "missing and non-state targets cannot become default")
	_check(not page.set_default_state("game") and not page.doc.dirty, "setting the current default is a no-op and rejected targets leave the document clean")
	page._monitor = true
	_check(not page.set_default_state("entry") and empty.default_state_key == &"game" and not page.doc.dirty, "monitoring cannot change the configured default")
	page._monitor = false
	page._select("credits", -1)
	page.delete_selected()
	_check(empty.find_state(&"credits") == null and empty.default_state_key == &"game", "deleting a non-default state preserves the chosen default")
	page._select("game", -1)
	page.delete_selected()
	_check(empty.find_state(&"game") == null and empty.default_state_key == &"entry", "deleting the default selects the first remaining state")
	page.doc.undo()
	_check(empty.find_state(&"game") != null and empty.default_state_key == &"game", "undo default state deletion restores the state and default together")
	page.doc.redo()
	_check(empty.find_state(&"game") == null and empty.default_state_key == &"entry", "redo default state deletion restores the fallback")
	page._select("entry", -1)
	page.delete_selected()
	_check(empty.states.is_empty() and empty.default_state_key.is_empty(), "deleting the last state clears the default")
	page.doc.undo()
	_check(empty.find_state(&"entry") == first and empty.default_state_key == &"entry", "undo last state deletion restores its default designation")
	var sparse := GDGameModeConfigRes.new()
	var other := GDGameStateBindingRes.new()
	other.key = &"other"
	sparse.states.assign([null, first, other])
	sparse.default_state_key = &"other"
	page.load_config(sparse)
	page._select("other", -1)
	page.delete_selected()
	_check(sparse.default_state_key == &"entry", "default fallback skips missing state bindings")
	first.graph_position = Vector2(970, 840)
	page._commit("Move sparse state")
	page.auto_layout()
	_check(first.graph_position == Vector2(340, 40) and sparse.states[0] == null, "auto layout skips missing state bindings without removing validation evidence")
	page.doc.undo()
	_check(first.graph_position == Vector2(970, 840), "sparse configuration layout remains undoable")
	await process_frame
	page.queue_free()
	await process_frame


func _find_named_control(node: Node, text: String, button: bool = false) -> Control:
	if button and node is Button and node.text == text:
		return node
	if not button and node is LineEdit and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_named_control(child, text, button)
		if found != null:
			return found
	return null


func _test_external_parameters() -> void:
	var fixture_root := "user://gm_external_params_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(fixture_root)
	var script_path := fixture_root.path_join("params.gd")
	var source := FileAccess.open(script_path, FileAccess.WRITE)
	source.store_string('@tool\nextends "res://addons/gdesigner_tools/sample/game_mode/sample_flow_params.gd"\n@export var linked: Resource\n')
	source.close()
	var params_script := load(script_path) as Script
	var shared := Resource.new()
	var shared_path := fixture_root.path_join("shared.tres")
	ResourceSaver.save(shared, shared_path)
	shared.take_over_path(shared_path)
	var external_params: Resource = params_script.new()
	external_params.set("linked", shared)
	var params_path := fixture_root.path_join("params.tres")
	ResourceSaver.save(external_params, params_path)
	external_params.take_over_path(params_path)
	var external_hash := FileAccess.get_sha256(params_path)
	var cfg := GDSampleFactory.build_game_mode_config()
	var entry := cfg.states[0].modules[0]
	entry.params = external_params
	var page := SessionPage.new()
	root.add_child(page)
	page.load_config(cfg)
	page._select("login", entry.module_id)
	_check(_find_named_control(page._form, "game") == null and not page.doc.dirty, "external parameter fields are read only and do not silently change shared assets")
	var copy_button := _find_named_control(page._form, "复制为内嵌参数", true) as Button
	_check(copy_button != null, "external parameters offer an explicit local copy action")
	if copy_button != null:
		copy_button.pressed.emit()
		var local_params := entry.params
		_check(local_params != external_params and local_params.resource_path.is_empty() and local_params.get("linked") == shared, "local parameter copy is independent while nested external references are preserved")
		var field := _find_named_control(page._form, "game") as LineEdit
		_check(field != null, "local parameter copy becomes editable")
		if field != null:
			field.text = "local_state"
			field.text_submitted.emit("local_state")
			_check(local_params.get("next_state") == &"local_state" and external_params.get("next_state") == &"game", "editing local parameters leaves the shared parameter resource unchanged")
			page.doc.undo()
			_check(entry.params == local_params and local_params.get("next_state") == &"game", "local parameter edits can be undone")
			page.doc.undo()
			_check(entry.params == external_params and not page.doc.dirty, "undoing the copy restores the original external reference")
			page.doc.redo()
			page.doc.redo()
			_check(entry.params == local_params and local_params.get("next_state") == &"local_state", "redo restores the same local parameter instance and its edits")
			page.prepare_save(page.doc)
			var config_path := fixture_root.path_join("config.tres")
			_check(page.doc.save(config_path) == OK, "configuration saves local parameter edits")
			var reloaded := ResourceLoader.load(config_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDGameModeConfigRes
			_check(reloaded != null and reloaded.states[0].modules[0].params.get("next_state") == &"local_state", "local parameter edits survive configuration reload")
			_check(FileAccess.get_sha256(params_path) == external_hash, "saving a local copy never rewrites the external parameter file")
	await process_frame
	page.queue_free()
	await process_frame
	for file in DirAccess.get_files_at(fixture_root):
		DirAccess.remove_absolute(fixture_root.path_join(file))
	DirAccess.remove_absolute(fixture_root)


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
	_test_form_fields()
	await _test_parameter_constructor_guard()
	await _test_default_states()
	await _test_external_parameters()
	var page := SessionPage.new()
	root.add_child(page)
	page.new_config()
	_check(page.config.states.size() == 1 and page.doc.dirty, "new configuration is unsaved and has a default state")
	var added := page.add_state("game", "游戏")
	_check(added != null and page.config.states.size() == 2, "state creation")
	page.doc.undo()
	_check(page.config.states.size() == 1, "undo state creation")
	page.doc.redo()
	_check(page.config.find_state(&"game") == added, "redo retains resource identity")
	_check(page.add_state("game") == null and page.add_state("Invalid Key") == null, "reject duplicate and invalid keys")
	page.rename_state_key("login", "entry")
	_check(page.config.default_state_key == &"entry", "key rename follows default state")
	page.doc.undo()
	_check(page.config.default_state_key == &"login", "key rename undo")
	var digest := page.config.runtime_digest()
	var previous := added.graph_position
	page.move_nodes({"game": Vector2(91, 273)})
	_check(page.config.runtime_digest() == digest and added.graph_position == Vector2(91, 273), "node position does not affect runtime digest")
	page.doc.undo()
	_check(added.graph_position == previous, "node position undo")
	var fixture := GDSampleFactory.build_game_mode_config()
	var module_script: Script = fixture.states[0].modules[0].module_script
	var entry := page.add_module("game", module_script)
	var original_params := entry.params
	_check(entry.module_id > 0 and original_params != null, "module gets stable id and typed parameters")
	var second := page.add_module("game", module_script)
	_check(second.module_id > entry.module_id, "ids increase across module bindings")
	page.move_selected(-1)
	_check(added.modules[0] == second, "module reordering")
	page.doc.undo()
	_check(added.modules[0] == entry, "module ordering undo")
	page.change_module_script(entry.module_id, fixture.global_modules[0].module_script)
	_check(entry.params == null, "changing parameter type replaces old parameters")
	page.doc.undo()
	_check(entry.params == original_params and entry.module_script == module_script, "script and parameter change undo atomically")
	page._select("game", entry.module_id)
	page.delete_selected()
	_check(page.config.find_module(entry.module_id) == null, "delete module")
	page.doc.undo()
	_check(page.config.find_module(entry.module_id) == entry, "undo module deletion")
	page._select("game", -1)
	page.move_selected(-1)
	_check(page.config.states[0] == added, "state ordering")
	page.doc.undo()
	_check(page.config.states[1] == added, "state ordering undo")
	page._select("game", -1)
	page.delete_selected()
	_check(page.config.find_state(&"game") == null, "delete state")
	page.doc.undo()
	_check(page.config.find_state(&"game") == added, "undo state deletion")
	var save_path := "user://gm_page_%d.tres" % Time.get_ticks_usec()
	page.prepare_save(page.doc)
	digest = page.config.runtime_digest()
	_check(page.doc.save(save_path) == OK, "save configuration")
	var reloaded := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDGameModeConfigRes
	_check(reloaded != null and reloaded.runtime_digest() == digest, "saved resource reload matches runtime digest")
	_check(not page.doc.dirty and entry.script_path_hint == module_script.resource_path, "save captures script fallback path and clears dirty state")
	_check(page._graph.get_connection_list().is_empty(), "configuration has no authored edges")
	page._graph.display([{"key": "a", "display_name": "A", "modules": []}, {"key": "b", "display_name": "B", "modules": []}], [], [{"from": "a", "to": "b", "count": 3, "frame": 10}], "b", true)
	_check(page._graph.get_connection_list().size() == 1, "runtime graph draws actual observed transition")
	_check(not page._graph._nodes["b"].draggable, "monitor graph is read only")
	var session := GDGameModeSession.new()
	session.connected = true
	session.handshake_complete = true
	session.welcome = {"protocol": 1, "process_token": "test", "generation": 1, "editor_runtime": true, "project_path": ProjectSettings.globalize_path("res://"), "config_path": save_path, "config_digest": digest}
	session.snapshot = {"current_state_key": "game", "states": [{"key": "game", "display_name": "游戏"}], "modules": [{"id": entry.module_id, "scope": "state:game", "display_name": "测试", "debug_restartable": true, "instance_serial": 8}]}
	session.events = [{"seq": 1, "kind": "module_construct", "module_id": entry.module_id}]
	page.test_session = session
	_check(page.application_status() == "已应用", "matching runtime digest shows applied")
	page._monitor = true
	page._refresh()
	_check(not page.doc.dirty and page._timeline.item_count == 1, "monitor refresh and timeline do not dirty document")
	page._select("game", entry.module_id)
	_check(page._runtime_restartable() and not page._follow.button_pressed, "manual monitor selection stops following and can restart live module")
	page._monitor = false
	session.welcome.config_path = "res://other_config.tres"
	_check(not page._runtime_restartable(), "same module id from a different configuration cannot be restarted from config selection")
	_check(page.application_status().begins_with("运行端使用其他配置"), "other runtime configuration is reported")
	session.welcome.config_path = save_path
	session.welcome.config_digest = "different"
	_check(page.application_status() == "已保存，未应用", "saved but unapplied digest is reported")
	session.snapshot.modules.append({"id": "manual:8:0", "scope": "manual", "display_name": "手动模块", "instance_serial": 9})
	page._monitor = true
	page._refresh()
	page._select("@manual", "manual:8:0")
	_check(page._display_data().manuals.size() == 1 and page._selected_module == "manual:8:0", "manual module identity survives monitoring and selection")
	_check(not page._runtime_restartable(), "manual modules remain read only")
	session.connected = false
	_check(page.application_status() == "未连接" and not session.snapshot.is_empty(), "disconnect preserves snapshot")
	await process_frame
	page.queue_free()
	await process_frame
	DirAccess.remove_absolute(save_path)
	print("TOTAL PASSED: %d FAILED: %d" % [passes, failures])
	quit(failures)
