@tool
extends EditorPlugin

var debugger: GDGameModeDebuggerPlugin
var elapsed := 0.0
var stage := 0
var started := false
var failures := 0
var receipt: Dictionary = {}
var serial := 0
var global_serial := 0
var generation := 0
var finishing := false
var start_msec := 0
var logged_state := false
var owns_debugger := false
var tool_window: GdesignerToolsWindow
var captured := false
var primary: GDGameModeSession
var peer_model: GDGameModeSession
var previous_token := ""
var extra_pid := 0
var original_plugins := PackedStringArray()
var original_sample: Resource
var protected_run := false


func _enter_tree() -> void:
	# This test deliberately rewrites fixture assets and launches two processes.
	# Never run it in the user's working game project.
	if ProjectSettings.get_setting("application/config/name", "") != "GdesignerTools Validation":
		push_error("GameMode editor smoke requires an isolated project named GdesignerTools Validation.")
		set_process(false)
		return
	protected_run = true
	original_plugins = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	if ResourceLoader.exists(GDSampleFactory.GAME_MODE_CONFIG_PATH):
		original_sample = ResourceLoader.load(GDSampleFactory.GAME_MODE_CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	debugger = GDGameModeDebuggerPlugin.current
	if debugger == null:
		debugger = GDGameModeDebuggerPlugin.new()
		owns_debugger = true
	start_msec = Time.get_ticks_msec()
	if owns_debugger:
		add_debugger_plugin(debugger)
	set_process(true)
	print("GM_EDITOR_SMOKE: editor harness loaded")


func _exit_tree() -> void:
	if protected_run:
		_cleanup_processes()
		if original_sample != null:
			ResourceSaver.save(original_sample, GDSampleFactory.GAME_MODE_CONFIG_PATH)
	if owns_debugger and debugger != null:
		remove_debugger_plugin(debugger)
		debugger.shutdown()


func _process(delta: float) -> void:
	elapsed += delta
	debugger.poll()
	if finishing:
		if elapsed > 1.0:
			if not owns_debugger:
				EditorInterface.set_plugin_enabled("gdesigner_tools", false)
			else:
				debugger.shutdown()
				remove_debugger_plugin(debugger)
				owns_debugger = false
			ProjectSettings.set_setting("editor_plugins/enabled", original_plugins)
			ProjectSettings.save()
			get_tree().quit(1 if failures else 0)
		return
	if Time.get_ticks_msec() - start_msec > 45000:
		_fail("timeout stage %s, sessions %s" % [stage, debugger.sessions.size()])
		_finish()
		return
	if not started and elapsed > 2.0:
		started = true
		GDSampleFactory.ensure_game_mode_assets()
		ResourceSaver.save(GDSampleFactory.build_game_mode_config(), GDSampleFactory.GAME_MODE_CONFIG_PATH)
		_verify_missing_script()
		for child in EditorInterface.get_base_control().get_children():
			if child is GdesignerToolsWindow:
				tool_window = child
				tool_window.present(4)
				tool_window.dock.game_mode_editor.load_config_path(GDSampleFactory.GAME_MODE_CONFIG_PATH)
		EditorInterface.play_custom_scene(GDSampleFactory.GAME_MODE_SCENE_PATH)
		print("GM_EDITOR_SMOKE: editor launched sample")
		return
	var model: GDGameModeSession = primary
	for candidate in debugger.session_list():
		if model == null and candidate.handshake_complete:
			model = candidate
			primary = candidate
			break
	if model == null or model.snapshot.is_empty():
		if not logged_state and Time.get_ticks_msec() - start_msec > 12000:
			logged_state = true
			print("GM_EDITOR_SMOKE: playing=", EditorInterface.is_playing_scene(), " sessions=", debugger.sessions.size())
			for candidate in debugger.session_list():
				print("GM_EDITOR_SMOKE: session=", candidate.session_id, " connected=", candidate.connected, " status=", candidate.status_text())
		return
	match stage:
		0:
			_check(model.status_text() == "已连接", "real debugger handshake")
			_check(model.can_apply(), "editor_runtime and matching project enable apply")
			_check(model.snapshot.get("current_state_key") == "login", "bootstrap starts login")
			if model.events.is_empty():
				return
			_check(model.events[0].kind == "gm_start", "handshake replays startup timeline")
			global_serial = _serial(model, 1)
			model.command_completed.connect(func(result: Dictionary) -> void: receipt = result)
			_send(model, "switch_state", {"key": "game"})
			stage = 1
		1:
			if receipt.is_empty() or model.snapshot.get("current_state_key") != "game":
				return
			_check(receipt.get("ok", false), "debug switch receipt")
			_check(_serial(model, 1) == global_serial, "switch preserves global instance")
			serial = _serial(model, 3)
			if tool_window != null and not captured:
				_capture_preview()
			_send(model, "restart_module", {"module_id": 3})
			stage = 2
		2:
			if receipt.is_empty() or _serial(model, 3) == serial:
				return
			_check(receipt.get("ok", false), "module restart receipt")
			_check(_serial(model, 1) == global_serial, "module restart preserves globals")
			serial = _serial(model, 3)
			_send(model, "restart_state", {})
			stage = 3
		3:
			if receipt.is_empty() or _serial(model, 3) == serial:
				return
			_check(receipt.get("ok", false), "state restart replaces state instance")
			_check(_serial(model, 1) == global_serial, "state restart preserves globals")
			generation = int(model.welcome.generation)
			var config := ResourceLoader.load(GDSampleFactory.GAME_MODE_CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GDGameModeConfigRes
			config.states.remove_at(1)
			config.prepare_save()
			ResourceSaver.save(config, GDSampleFactory.GAME_MODE_CONFIG_PATH)
			_send(model, "apply_config", {"path": GDSampleFactory.GAME_MODE_CONFIG_PATH, "expected_digest": config.runtime_digest()})
			stage = 4
		4:
			if receipt.is_empty() or int(model.welcome.generation) == generation or model.snapshot.get("current_state_key") != "login":
				return
			_check(receipt.get("ok", false), "apply receipt")
			_check(int(model.welcome.generation) == generation + 1, "apply increments generation")
			_check(_serial(model, 1) != global_serial, "apply rebuilds globals")
			_check(model.snapshot.get("current_state_key") == "login", "removed current state falls back to default")
			debugger.get_session(model.session_id).send_message("break")
			stage = 5
		5:
			if not model.paused:
				return
			_check(model.status_text() == "断点暂停" and not model.can_command() and not model.can_apply(), "real debugger pause disables mutations")
			debugger.get_session(model.session_id).send_message("continue")
			stage = 6
		6:
			if model.paused:
				return
			_check(model.can_command(), "real debugger continue enables commands")
			previous_token = str(model.welcome.process_token)
			EditorInterface.stop_playing_scene()
			stage = 7
		7:
			if model.connected:
				return
			_check(model.status_text() == "已断开" and not model.snapshot.is_empty() and not model.events.is_empty(), "stop retains last snapshot and timeline")
			ResourceSaver.save(GDSampleFactory.build_game_mode_config(), GDSampleFactory.GAME_MODE_CONFIG_PATH)
			EditorInterface.play_custom_scene(GDSampleFactory.GAME_MODE_SCENE_PATH)
			stage = 8
		8:
			if not model.handshake_complete or model.snapshot.is_empty() or model.events.is_empty():
				return
			_check(str(model.welcome.process_token) != previous_token and model.snapshot.current_state_key == "login" and model.events[0].seq == 1, "restart handshakes new process and replaces previous data")
			var uri := OS.get_environment("GM_SMOKE_DEBUG_URI")
			if uri.is_empty():
				uri = "tcp://127.0.0.1:%s" % EditorInterface.get_editor_settings().get_setting("network/debug/remote_port")
			extra_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--remote-debug", uri, "--editor-pid", str(OS.get_process_id()), "--scene", GDSampleFactory.GAME_MODE_SCENE_PATH], false)
			_check(extra_pid > 0, "launch second runtime")
			stage = 9
		9:
			for candidate in debugger.session_list():
				if candidate != model and candidate.handshake_complete and not candidate.snapshot.is_empty():
					peer_model = candidate
			if peer_model == null:
				return
			_check(peer_model.session_id != model.session_id and peer_model.welcome.process_token != model.welcome.process_token, "two real runtime sessions have separate identities")
			_send(model, "switch_state", {"key": "game"})
			stage = 10
		10:
			if receipt.is_empty() or model.snapshot.get("current_state_key") != "game":
				return
			_check(peer_model.snapshot.get("current_state_key") == "login", "command changes only selected real session")
			_check(peer_model.events.size() != model.events.size(), "two real timelines remain independent")
			print("GM_EDITOR_SMOKE: SUCCESS failures=", failures)
			_finish()


func _send(model: GDGameModeSession, kind: String, args: Dictionary) -> void:
	receipt = {}
	print("GM_EDITOR_SMOKE: send ", kind)
	_check(not model.send_command(kind, args).is_empty(), "accepted " + kind)


func _serial(model: GDGameModeSession, module_id: int) -> int:
	for module in model.snapshot.get("modules", []):
		if module.get("id") == module_id:
			return int(module.get("instance_serial", 0))
	return 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)
	else:
		print("GM_EDITOR_SMOKE: PASS ", label)


func _fail(message: String) -> void:
	failures += 1
	push_error("GM_EDITOR_SMOKE: FAIL " + message)


func _finish() -> void:
	_cleanup_processes()
	ResourceSaver.save(original_sample if original_sample != null else GDSampleFactory.build_game_mode_config(), GDSampleFactory.GAME_MODE_CONFIG_PATH)
	finishing = true
	elapsed = 0.0


func _cleanup_processes() -> void:
	if extra_pid > 0:
		if OS.is_process_running(extra_pid):
			OS.kill(extra_pid)
		extra_pid = 0
	if started:
		if EditorInterface.is_playing_scene():
			EditorInterface.stop_playing_scene()
		started = false


func _capture_preview() -> void:
	captured = true
	if DisplayServer.get_name() == "headless":
		return
	var page := tool_window.dock.game_mode_editor
	page._monitor = true
	page._view_picker.select(1)
	page._select("game", 3)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(tool_window):
		return
	var picture := tool_window.get_texture().get_image()
	if picture != null:
		picture.save_png(ProjectSettings.globalize_path("res://game-mode-monitor.png"))
		print("GM_EDITOR_SMOKE: screenshot saved")


func _verify_missing_script() -> void:
	var source := FileAccess.get_file_as_string(GDSampleFactory.GAME_MODE_CONFIG_PATH)
	var broken_lines := PackedStringArray()
	var uid_pattern := RegEx.new()
	uid_pattern.compile(' uid="[^"]+"')
	for line in source.split("\n"):
		if line.begins_with("[gd_resource") or (line.begins_with("[ext_resource") and line.contains("sample_global_module.gd")):
			line = uid_pattern.sub(line, "", true)
		line = line.replace("sample_global_module.gd", "missing_global_module.gd")
		broken_lines.append(line)
	var fixture_path := "res://game_res/sample/game_mode/MissingModule_Test.tres"
	var handle := FileAccess.open(fixture_path, FileAccess.WRITE)
	handle.store_string("\n".join(broken_lines))
	handle.close()
	var loaded := ResourceLoader.load(fixture_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDGameModeConfigRes
	_check(loaded != null, "editor loads config despite missing module script")
	if loaded != null:
		_check(loaded.global_modules[0].module_script == null and loaded.global_modules[0].script_path_hint.ends_with("missing_global_module.gd"), "missing module retains path hint")
		loaded.prepare_save()
		_check(ResourceSaver.save(loaded, fixture_path) == OK, "invalid config remains saveable in editor")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
