extends SceneTree

const SAMPLE_MODULE := preload("res://addons/gdesigner_tools/sample/game_mode/sample_game_module.gd")
var _passed := 0
var _failed := 0
var _files: Array[String] = []


class InvalidCategory extends GDGameFramework.GameModuleBase:
	const MODULE_CATEGORY := 999


class RequiredConstructor extends GDGameFramework.GameModuleBase:
	const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.MISC
	func _init(_required: int) -> void:
		pass


class OptionalConstructor extends RequiredConstructor:
	func _init(value: int = 0) -> void:
		super(value)


class DigestParams extends Resource:
	@export var payload: Array = []


class ProbeModule extends GDGameFramework.GameModuleBase:
	const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.SCENE
	const DEBUG_RESTARTABLE := true
	static var trace: Array[String] = []
	static var creates := 0
	var updates := 0
	var fixed_updates := 0
	func _init() -> void:
		creates += 1
	func on_update(_delta: float) -> void:
		updates += 1
		trace.append("update")
	func on_late_update(_delta: float) -> void:
		trace.append("late")
	func on_fixed_update(_delta: float) -> void:
		fixed_updates += 1


class OrdinaryNode extends Node:
	func _process(_delta: float) -> void:
		ProbeModule.trace.append("ordinary")


class ApplyTwice extends GDGameFramework.GameModuleBase:
	const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.SCENE
	static var requests: Array[Dictionary] = []
	func on_construct(_ctx: GDGameFramework.GameModeContext) -> void:
		var batch := requests.duplicate()
		requests.clear()
		for request in batch:
			GDGameMode.current.apply_config(request.path, request.digest)


class ShutdownOnConstruct extends GDGameFramework.GameModuleBase:
	const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.SCENE
	static var disposed_inside_callback := false
	func on_construct(_ctx: GDGameFramework.GameModeContext) -> void:
		GDGameMode.current.shutdown()
		disposed_inside_callback = is_disposed


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_validation_and_digest()
	_test_cyclic_digest()
	_test_missing_dependency()
	_test_host_and_protocol()
	_test_host_recreation()
	_test_apply_reentry_and_faults()
	await _test_tree_lifecycle()
	for path in _files:
		DirAccess.remove_absolute(path)
	GDCoreServices.shutdown_for_tests()
	print("GAME MODE RUNTIME: %d passed, %d failed" % [_passed, _failed])
	quit(_failed)


func _test_validation_and_digest() -> void:
	var cfg := GDSampleFactory.build_game_mode_config()
	_check(GDGameModeValidation.validate(cfg, true).ok, "sample passes runtime validation")
	var digest := cfg.runtime_digest()
	cfg.global_graph_position += Vector2(100, 20)
	cfg.states[0].graph_position += Vector2(100, 20)
	_check(digest == cfg.runtime_digest(), "graph positions do not change runtime digest")
	cfg.states[0].modules[0].params.next_state = &"other"
	_check(digest != cfg.runtime_digest(), "StringName params affect digest")
	cfg.states[0].modules[0].params.next_state = &"game"
	_check(digest == cfg.runtime_digest(), "restoring params restores digest")
	cfg.states[0].modules[0].params.accent = Color.RED
	_check(digest != cfg.runtime_digest(), "Color params affect digest")
	cfg = GDSampleFactory.build_game_mode_config()
	cfg.states[1].key = cfg.states[0].key
	_check(not GDGameModeValidation.validate(cfg).ok, "duplicate keys rejected")
	cfg.states[1].key = &"bad-key"
	_check(not GDGameModeValidation.validate(cfg).ok, "illegal keys rejected")
	cfg = GDSampleFactory.build_game_mode_config()
	cfg.states[1].modules[0].module_id = 1
	_check(not GDGameModeValidation.validate(cfg).ok, "duplicate IDs across global and states rejected")
	cfg = GDSampleFactory.build_game_mode_config()
	cfg.states[0].modules[0].module_script = null
	cfg.states[0].modules[0].script_path_hint = "res://deleted_module.gd"
	var validation := GDGameModeValidation.validate(cfg)
	_check(not validation.ok and str(validation.errors).contains("deleted_module.gd"), "missing script error preserves path hint")
	cfg.states[0].modules[0].module_script = load("res://addons/gdesigner_tools/sample/game_mode/sample_flow_params.gd")
	_check(not GDGameModeValidation.validate(cfg).ok, "non-module scripts rejected")
	cfg = GDSampleFactory.build_game_mode_config()
	cfg.states[1].modules[0].module_script = InvalidCategory
	_check(not GDGameModeValidation.validate(cfg).ok, "invalid category rejected without instantiation")
	cfg.states[1].modules[0].module_script = SAMPLE_MODULE
	cfg.states[0].modules[0].params = Resource.new()
	_check(not GDGameModeValidation.validate(cfg).ok, "incorrect parameter type rejected")
	var creates := ProbeModule.creates
	var meta := GDGameModuleMeta.read(ProbeModule)
	_check(meta.valid_module and meta.debug_restartable and ProbeModule.creates == creates, "metadata reads constants without creating modules")
	_check(not GDGameModeValidation.validate(_one_module_config(RequiredConstructor), true).ok, "required constructor arguments are rejected before runtime module creation")
	_check(GDGameModeValidation.validate(_one_module_config(OptionalConstructor), true).ok, "derived constructor with defaults can satisfy required base constructor arguments")
	cfg = GDSampleFactory.build_game_mode_config()
	cfg.next_module_id = 1
	_check(cfg.allocate_module_id() == 4 and cfg.allocate_module_id() == 5, "ID allocator repairs stale counter and remains monotonic")
	var entry := cfg.states[0].modules[0]
	entry.set_module_script(SAMPLE_MODULE)
	_check(entry.params == null, "changing PARAMS_SCRIPT clears old params")
	entry.set_module_script(load("res://addons/gdesigner_tools/sample/game_mode/sample_login_module.gd"))
	_check(entry.params != null, "changing to typed module creates params")
	var path := _test_path("config.tres")
	cfg.prepare_save()
	_check(ResourceSaver.save(cfg, path) == OK, "configuration saves using native Resource references")
	var loaded := GDGameModeValidation.load_checked(path)
	_check(loaded.ok and loaded.config.runtime_digest() == cfg.runtime_digest(), "saved/reloaded digest is stable")


func _test_cyclic_digest() -> void:
	var cfg := _one_module_config(ProbeModule)
	var params := DigestParams.new()
	cfg.states[0].modules[0].params = params
	var array: Array = []
	array.append(array)
	params.payload = array
	var array_digest := cfg.runtime_digest()
	_check(array_digest.length() == 64 and cfg.runtime_digest() == array_digest, "self-referential parameter arrays produce a stable digest without recursion overflow")
	array.append("changed")
	_check(cfg.runtime_digest() != array_digest, "cyclic array digest still detects scalar parameter changes")
	array.clear()
	var dictionary: Dictionary = {}
	dictionary["self"] = dictionary
	params.payload = [dictionary]
	var dictionary_digest := cfg.runtime_digest()
	_check(dictionary_digest.length() == 64 and cfg.runtime_digest() == dictionary_digest, "self-referential parameter dictionaries produce a stable digest")
	dictionary["value"] = 1
	_check(cfg.runtime_digest() != dictionary_digest, "cyclic dictionary digest still detects scalar parameter changes")
	dictionary.clear()
	params.payload = [[1], [1]]
	var independent_digest := cfg.runtime_digest()
	params.payload[1].append(2)
	_check(cfg.runtime_digest() != independent_digest, "distinct equal-looking containers are not mistaken for reference cycles")
	params.payload.clear()


func _test_missing_dependency() -> void:
	var path := _test_path("missing.tres")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('[gd_resource type="Resource" load_steps=2 format=3]\n[ext_resource type="Script" path="res://missing_dependency.gd" id="1"]\n[resource]\nscript = ExtResource("1")\n')
	file.close()
	var missing := GDGameModeValidation.preflight_dependencies(path)
	_check(missing.has("res://missing_dependency.gd"), "dependency preflight names missing script before loading")
	_check(GDGameModeValidation.load_checked(path).code == "missing_dependency", "missing dependency refuses checked load")
	var cached_path := _test_path("cached_deleted.tres")
	ResourceSaver.save(Resource.new(), cached_path)
	var cached := ResourceLoader.load(cached_path)
	DirAccess.remove_absolute(cached_path)
	_check(cached != null and GDGameModeValidation.preflight_dependencies(cached_path).has(cached_path), "cached resources cannot hide deleted dependency files")


func _test_host_and_protocol() -> void:
	var cfg := GDSampleFactory.build_game_mode_config()
	var mode := GDGameMode.new()
	var pair := GDGameModeLoopbackLink.create_pair()
	mode.attach_link(pair[0])
	_check(mode.start(cfg) == OK, "host starts valid configuration")
	_check(mode.current_state_key == &"login", "default state selected by key")
	if not OS.has_feature("editor_runtime"):
		var blocked := mode.execute_debug_command("apply_config", {"path": "res://untrusted.tres", "expected_digest": "unused"})
		_check(not blocked.ok and blocked.code == "editor_runtime_required", "standalone runtime rejects debug configuration replacement before reading its path")
	_check(pair[0].sent.is_empty(), "runtime sends nothing before hello")
	var global_serial := _serial(mode, 1)
	var login_serial := _serial(mode, 2)
	_check(not mode.switch_state(&"unknown"), "unknown state key rejected")
	_check(mode.switch_state(&"game") and mode.switch_state(&"login"), "business code switches by stable keys")
	_check(_serial(mode, 1) == global_serial and _serial(mode, 2) != login_serial, "state re-entry recreates instances but preserves globals")
	_check(mode.machine._find_module(2).params != cfg.states[0].modules[0].params, "each module receives independent parameter copy")
	pair[1].send("hello", {"protocol": 1})
	_check(pair[0].sent[0].kind == "welcome", "hello receives welcome first")
	_check(_last_message(pair[0], "welcome").has("process_token"), "welcome carries process identity")
	var buffered: Array = _last_message(pair[0], "events").get("events", [])
	_check(not buffered.is_empty() and buffered[0].kind == "gm_start", "handshake replays startup events")
	var command := {"request_id": "restart", "process_token": mode.process_token,
		"generation": mode.generation, "kind": "restart_state", "args": {}}
	login_serial = _serial(mode, 2)
	pair[1].send("command", command)
	_check(_serial(mode, 2) == login_serial, "received command does not run in transport callback")
	mode.protocol.process_commands()
	_check(_serial(mode, 2) != login_serial and _last_message(pair[0], "command_result").ok, "command executes at safe point")
	login_serial = _serial(mode, 2)
	pair[1].send("command", command)
	mode.protocol.process_commands()
	_check(_serial(mode, 2) == login_serial and _last_message(pair[0], "command_result").code == "duplicate_request", "duplicate request executes at most once")
	command.request_id = "wrong"
	command.process_token = "other"
	pair[1].send("command", command)
	mode.protocol.process_commands()
	_check(_last_message(pair[0], "command_result").code == "wrong_process", "wrong process token refused")
	command.request_id = "stale"
	command.process_token = mode.process_token
	command.generation = 0
	pair[1].send("command", command)
	mode.protocol.process_commands()
	_check(_last_message(pair[0], "command_result").code == "stale_generation", "stale generation refused")
	var path := _test_path("apply.tres")
	var next := GDSampleFactory.build_game_mode_config()
	next.states.remove_at(0)
	next.default_state_key = &"game"
	ResourceSaver.save(next, path)
	_check(mode.apply_config(path, "incorrect") != OK and _serial(mode, 2) == login_serial, "digest mismatch leaves old world intact")
	var state_events: Array[Dictionary] = []
	var collect_event := func(event: Dictionary) -> void: state_events.append(event)
	GDCoreServices.get_event_bus().subscribe(GDGameFramework.GameStateMachine.EVENT_GAME_STATE_CHANGED, collect_event)
	_check(mode.apply_config(path, next.runtime_digest()) == OK and mode.generation == 2, "valid apply increments generation")
	GDCoreServices.get_event_bus().unsubscribe(GDGameFramework.GameStateMachine.EVENT_GAME_STATE_CHANGED, collect_event)
	_check(state_events.size() == 1 and state_events[0].reason == &"apply" and state_events[0].old_state_key == &"login" and state_events[0].new_state_key == &"game", "apply event preserves old and new stable keys")
	_check(mode.current_state_key == &"game" and _serial(mode, 1) != global_serial, "apply removes missing state and recreates globals")
	mode.protocol.update(0.1)
	_check(_last_message(pair[0], "welcome").generation == 2, "business API apply also refreshes editor generation and digest")
	var serial := _serial(mode, 3)
	_check(mode.restart_module(3) == OK and _serial(mode, 3) != serial, "restartable module is replaced")
	_check(mode.restart_module(1) != OK, "module without restart declaration is refused")
	serial = _serial(mode, 3)
	_check(mode.apply_config("res://absent_config.tres", "x") != OK and _serial(mode, 3) == serial, "failed apply preserves running modules")
	var manual := GDGameFramework.GameModuleBase.new()
	manual.display_name = "Legacy module"
	mode.machine.register_state_binding(77, [manual])
	mode.machine.switch_state(77)
	var manual_visible := false
	for module in mode.capture_snapshot().modules:
		if str(module.id) == "manual:77:0":
			manual_visible = module.scope == "manual" and not module.debug_restartable and module.instance_serial == manual.instance_serial
	_check(manual_visible, "host snapshot preserves manual string identity and read-only lifecycle details")
	for i in 510:
		mode.record_event("test", {"detail": {"i": i}})
	_check(mode.events.size() == 500 and mode.events[0].seq < mode.events[-1].seq, "event ring keeps latest 500 in sequence order")
	mode.shutdown()
	_check(GDGameMode.current == null and mode.phase == "idle", "shutdown clears singleton")
	mode.protocol.close()
	mode.protocol = null
	mode.free()


func _test_host_recreation() -> void:
	var mode := GDGameMode.new()
	var pair := GDGameModeLoopbackLink.create_pair()
	mode.attach_link(pair[0])
	var cfg := GDSampleFactory.build_game_mode_config()
	_check(mode.start(cfg) == OK, "first host run starts")
	pair[1].send("hello", {"protocol": 1})
	var previous_generation := mode.generation
	var previous_token := mode.process_token
	mode.shutdown()
	var next := GDSampleFactory.build_game_mode_config()
	next.display_name = "Restarted host"
	_check(mode.start(next) == OK and mode.generation == previous_generation + 1, "restarting the same host advances configuration generation")
	mode.protocol.update(0.1)
	var welcome := _last_message(pair[0], "welcome")
	_check(welcome.generation == mode.generation and welcome.config_digest == next.runtime_digest(), "same-host restart refreshes the editor configuration identity")
	mode.shutdown()
	mode.protocol.close()
	mode.protocol = null
	mode.free()
	var replacement := GDGameMode.new()
	_check(replacement.process_token != previous_token, "replacement host has a new identity before event sequence resets")
	replacement.free()


func _test_apply_reentry_and_faults() -> void:
	var first := GDSampleFactory.build_game_mode_config()
	first.display_name = "first"
	var second := GDSampleFactory.build_game_mode_config()
	second.display_name = "second"
	second.states.remove_at(0)
	second.default_state_key = &"game"
	var first_path := _test_path("first.tres")
	var second_path := _test_path("second.tres")
	ResourceSaver.save(first, first_path)
	ResourceSaver.save(second, second_path)
	ApplyTwice.requests = [{"path": first_path, "digest": first.runtime_digest()}, {"path": second_path, "digest": second.runtime_digest()}]
	var mode := GDGameMode.new()
	mode.start(_one_module_config(ApplyTwice))
	_check(mode.generation == 3 and mode.config.display_name == "second" and mode.current_state_key == &"game", "two applies from one lifecycle callback both complete in order")
	mode.shutdown()
	mode.free()
	mode = GDGameMode.new()
	var repeat_apply := func(_event: Variant) -> void:
		mode.apply_config(first_path, first.runtime_digest())
	GDCoreServices.get_event_bus().subscribe(GDGameFramework.GameStateMachine.EVENT_GAME_STATE_CHANGED, repeat_apply)
	mode.start(first)
	GDCoreServices.get_event_bus().unsubscribe(GDGameFramework.GameStateMachine.EVENT_GAME_STATE_CHANGED, repeat_apply)
	var overflow := false
	for event in mode.events:
		if event.kind == "reentry_overflow":
			overflow = true
	_check(overflow and mode.generation == 8, "apply reentry shares the eight-operation bound across generations")
	mode.shutdown()
	mode.free()
	mode = GDGameMode.new()
	mode.start(_one_module_config(ShutdownOnConstruct))
	_check(not ShutdownOnConstruct.disposed_inside_callback and mode.phase == "idle" and GDGameMode.current == null, "shutdown in Construct waits for callback and keeps host idle")
	mode.free()
	var fault_script_path := _test_path("fault.gd")
	var file := FileAccess.open(fault_script_path, FileAccess.WRITE)
	file.store_string('extends GDGameFramework.GameModuleBase\nconst MODULE_CATEGORY = GDCoreTypes.ModuleCategory.SCENE\nfunc on_construct(_ctx):\n\treport_fault(&"construct", "expected fixture fault")\n')
	file.close()
	var fault_cfg := _one_module_config(load(fault_script_path))
	var fault_path := _test_path("fault.tres")
	ResourceSaver.save(fault_cfg, fault_path)
	mode = GDGameMode.new()
	mode.start(first)
	mode.apply_config(fault_path, fault_cfg.runtime_digest())
	_check(mode.last_result.code == "module_fault" and mode.last_result.phase == "construct", "apply reports lifecycle fault with exact phase")
	var snapshot := mode.capture_snapshot()
	_check(snapshot.modules[0].lifecycle == "faulted" and not snapshot.modules[0].is_ticking, "faulted instance remains visible and is not ticking")
	mode.shutdown()
	mode.free()


func _test_tree_lifecycle() -> void:
	var cfg := GDGameModeConfigRes.new()
	var state := GDGameStateBindingRes.new()
	state.key = &"login"
	var entry := GDGameModuleEntryRes.new()
	entry.module_id = 1
	entry.module_script = ProbeModule
	state.modules.append(entry)
	cfg.states.append(state)
	var mode := GDGameMode.new()
	mode.config = cfg
	root.add_child(mode)
	var ordinary := OrdinaryNode.new()
	root.add_child(ordinary)
	ProbeModule.trace.clear()
	await process_frame
	await process_frame
	_check(ProbeModule.trace.has("update") and ProbeModule.trace.has("ordinary") and ProbeModule.trace.has("late"), "host dispatches update and late update")
	_check(ProbeModule.trace.find("late") > ProbeModule.trace.find("ordinary"), "LateTicker runs after default-priority scene nodes")
	var instance: ProbeModule = mode.machine._find_module(1)
	paused = true
	var count := instance.updates
	mode._process(0.1)
	_check(instance.updates == count, "paused tree suppresses module tick by default")
	cfg.tick_when_paused = true
	mode._process(0.1)
	_check(instance.updates == count + 1, "tick_when_paused explicitly allows paused tick")
	paused = false
	var bootstrap := GDGameModeBootstrap.new()
	bootstrap.config_path = mode.config_path
	root.add_child(bootstrap)
	await process_frame
	_check(GDGameMode.current == mode, "reloaded bootstrap preserves existing GameMode")
	bootstrap.free()
	ordinary.free()
	mode.free()
	_check(GDGameMode.current == null, "tree exit shuts down persistent host")


func _serial(mode: GDGameMode, id: int) -> int:
	for item in mode.capture_snapshot().modules:
		if item.id == id:
			return int(item.instance_serial)
	return -1


func _one_module_config(script: Script) -> GDGameModeConfigRes:
	var config := GDGameModeConfigRes.new()
	var state := GDGameStateBindingRes.new()
	state.key = &"login"
	var entry := GDGameModuleEntryRes.new()
	entry.module_id = 1
	entry.module_script = script
	state.modules.append(entry)
	config.states.append(state)
	return config


func _last_message(link: GDGameModeLoopbackLink, kind: String) -> Dictionary:
	for i in range(link.sent.size() - 1, -1, -1):
		if link.sent[i].kind == kind:
			return link.sent[i].payload
	return {}


func _test_path(suffix: String) -> String:
	var path := "user://game_mode_runtime_" + suffix
	_files.append(path)
	return path


func _check(value: bool, label: String) -> void:
	if value:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
