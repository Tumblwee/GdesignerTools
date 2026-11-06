class_name GDGameMode
extends Node

## Persistent host. Business code changes state through GDGameMode.current.
static var current: GDGameMode
const EVENT_LIMIT := 500

var config: GDGameModeConfigRes
var config_path: String = ""
var config_digest: String = ""
var generation: int = 1
var phase: String = "idle"
var process_token: String = ""
var events: Array[Dictionary] = []
var machine: GDGameFramework.GameStateMachine
var protocol: GDGameModeProtocol
var last_result: Dictionary = {}
var _keys: Dictionary = {}
var _next_seq: int = 1
var _stopping := false
var _has_started := false

var current_state_key: StringName:
	get:
		return machine.state_keys.get(machine.current_state_id, &"") if machine != null else &""

var pending_state_key: StringName:
	get:
		return machine.state_keys.get(machine.pending_state_id, &"") if machine != null else &""


func _init() -> void:
	name = "GDGameMode"
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A new host restarts its event sequence and generation. Give it a fresh
	# identity even when it replaces a previous host in the same game process.
	process_token = Crypto.new().generate_random_bytes(16).hex_encode()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		set_physics_process(false)
		return
	if is_instance_valid(current) and current != self:
		push_warning("GameMode 已存在，忽略重复宿主。")
		queue_free()
		return
	current = self
	var ticker := GDGameModeLateTicker.new()
	ticker.name = "LateTicker"
	ticker.mode = self
	add_child(ticker)
	if protocol == null:
		var link := GDGameModeEngineLink.new()
		link.open()
		attach_link(link)
	if config != null and phase == "idle":
		start(config, config_path)


func attach_link(link: GDGameModeLink) -> void:
	if protocol != null:
		protocol.close()
	protocol = GDGameModeProtocol.new(self, link)


func start(value: GDGameModeConfigRes, path: String = "", restore_key: StringName = &"", reason: StringName = &"switch") -> Error:
	if is_instance_valid(current) and current != self:
		return ERR_ALREADY_IN_USE
	if machine != null:
		return ERR_ALREADY_IN_USE
	var validation := GDGameModeValidation.validate(value, true)
	if not validation.ok:
		phase = "failed"
		last_result = _result(false, "validation_failed", "\n".join(validation.errors), "validation")
		push_error(last_result.message)
		return ERR_INVALID_DATA
	current = self
	if _has_started:
		generation += 1
	_has_started = true
	machine = GDGameFramework.GameStateMachine.new()
	machine.lifecycle_hook = _on_lifecycle
	_assemble_config(value, path)
	var initial_machine := machine
	var initial_generation := generation
	var target := restore_key if has_state(restore_key) else config.default_state_key
	machine.switch_state(_keys[target], reason)
	# Business lifecycle code may have queued shutdown or another configuration.
	if machine == initial_machine and generation == initial_generation and not _stopping:
		phase = "running"
		last_result = _result(true, "ok", "GameMode 已启动。", "begin_play")
	return OK


func _assemble_config(value: GDGameModeConfigRes, path: String) -> void:
	config = value
	config_path = path if not path.is_empty() else value.resource_path
	config_digest = value.runtime_digest()
	_keys.clear()
	phase = "starting"
	record_event("gm_start")
	var globals: Array[Callable] = []
	for i in config.global_modules.size():
		globals.append(_create_module.bind(config.global_modules[i], "global", i))
	machine.register_global_factories(globals)
	for i in config.states.size():
		var state := config.states[i]
		_keys[state.key] = i
		machine.state_keys[i] = state.key
		var factories: Array[Callable] = []
		for j in state.modules.size():
			factories.append(_create_module.bind(state.modules[j], "state:" + String(state.key), j))
		machine.register_state_factories(i, factories)


func _create_module(entry: GDGameModuleEntryRes, scope: String, order: int) -> GDGameFramework.GameModuleBase:
	var module: GDGameFramework.GameModuleBase = entry.module_script.new()
	var meta := GDGameModuleMeta.read(entry.module_script)
	module.module_id = entry.module_id
	module.display_name = entry.display_name
	module.scope = scope
	module.config_order = order
	module.script_path = entry.script_path()
	module.category = int(meta.category)
	module.tick_enabled = bool(meta.tick_enabled)
	module.debug_restartable = bool(meta.debug_restartable)
	# duplicate(true) duplicates internal subresources and retains external ones.
	module.configure(entry.params.duplicate(true) if entry.params != null else null)
	return module


func has_state(key: StringName) -> bool:
	return not key.is_empty() and _keys.has(key)


func switch_state(key: StringName, reason: StringName = &"switch") -> bool:
	if not _is_running():
		record_event("switch_rejected", {"result": "not_running", "detail": {"target": String(key)}})
		return false
	if not has_state(key):
		record_event("switch_rejected", {"result": "invalid_state", "detail": {"target": String(key)}})
		push_warning("GameMode 拒绝未登记或空的状态 Key：%s" % key)
		return false
	return machine.switch_state(int(_keys[key]), reason)


func restart_state() -> bool:
	return machine.restart_state() if _is_running() else false


func restart_module(id: int) -> Error:
	return machine.restart_module(id) if _is_running() else ERR_UNCONFIGURED


func apply_config(path: String, expected_digest: String) -> Error:
	if not _is_running():
		last_result = _result(false, "not_running", "GameMode 未运行。", "validation")
		return ERR_UNCONFIGURED
	# Verify everything before disposing any part of the existing world.
	var loaded := GDGameModeValidation.load_checked(path, true)
	if not loaded.ok:
		last_result = _result(false, loaded.code, loaded.message, "validation")
		return ERR_FILE_MISSING_DEPENDENCIES if loaded.code == "missing_dependency" else ERR_INVALID_DATA
	var next: GDGameModeConfigRes = loaded.config
	if expected_digest.is_empty() or next.runtime_digest() != expected_digest:
		last_result = _result(false, "digest_mismatch", "磁盘配置摘要与编辑器不一致，请保存后重试。", "validation")
		return ERR_INVALID_DATA
	if machine.is_callback_active():
		machine.enqueue_operation(_apply_validated.bind(next, path))
		last_result = _result(true, "queued", "配置将在当前生命周期结束后应用。", "queued")
	else:
		machine.enqueue_operation(_apply_validated.bind(next, path))
	return OK


func _apply_validated(next: GDGameModeConfigRes, path: String) -> void:
	var restore := current_state_key
	phase = "transitioning"
	machine.reset_configuration()
	generation += 1
	_assemble_config(next, path)
	var target := restore if has_state(restore) else config.default_state_key
	machine.enter_configuration_state(int(_keys[target]), &"apply")
	phase = "running"
	var faults: Array = []
	for module in capture_snapshot().modules:
		if module.lifecycle == "faulted":
			faults.append({"module_id": module.id, "fault": module.last_fault})
	last_result = _result(faults.is_empty(), "ok" if faults.is_empty() else "module_fault",
		"配置已应用。" if faults.is_empty() else "配置已应用，但模块报告故障：%s" % JSON.stringify(faults),
		"begin_play" if faults.is_empty() else str(faults[0].fault.get("phase", "begin_play")))
	last_result.applied = true


func execute_debug_command(kind: String, args: Dictionary) -> Dictionary:
	if not _is_running():
		return _result(false, "not_running", "GameMode 未运行。", "validation")
	match kind:
		"switch_state":
			var key := StringName(str(args.get("key", "")))
			var accepted := switch_state(key, &"debug_switch")
			return _result(accepted, "ok" if accepted else "invalid_state", "已受理。" if accepted else "状态无效或与当前目标相同。")
		"restart_state":
			var accepted := restart_state()
			return _result(accepted, "ok" if accepted else "not_restartable", "已受理。" if accepted else "当前状态不可重启。")
		"restart_module":
			var code := restart_module(int(args.get("module_id", -1)))
			return _result(code == OK, "ok" if code == OK else "not_restartable", "已受理。" if code == OK else "模块没有活动实例或未声明可独立重启。")
		"apply_config":
			if not OS.has_feature("editor_runtime"):
				return _result(false, "editor_runtime_required", "仅允许由编辑器启动的游戏实例应用配置。", "validation")
			apply_config(str(args.get("path", "")), str(args.get("expected_digest", "")))
			return last_result.duplicate(true)
	return _result(false, "invalid_request", "未知命令：%s" % kind, "validation")


func capture_snapshot() -> Dictionary:
	var raw: Dictionary = machine.capture_snapshot() if machine != null else {}
	var modules: Array = []
	var active: Dictionary = {}
	for module in raw.get("modules", []):
		if module.get("scope", "manual") != "manual":
			active[module.get("id", module.get("module_id", -1))] = module
	var states: Array = []
	if config != null:
		_append_snapshot_modules(modules, config.global_modules, "global", active)
		for state in config.states:
			var ids: Array = []
			for entry in state.modules:
				ids.append(entry.module_id)
			states.append({"key": String(state.key), "display_name": state.display_name, "module_ids": ids})
			_append_snapshot_modules(modules, state.modules, "state:" + String(state.key), active)
	# Manual registrations have their own string identities. Preserve them as
	# read-only monitor entries without inventing configurable business keys.
	for module in raw.get("modules", []):
		if module.get("scope", "manual") == "manual":
			modules.append(module.duplicate(true))
	return {"phase": "transitioning" if machine != null and machine.is_transitioning else phase,
		"current_state_key": String(current_state_key), "pending_state_key": String(pending_state_key),
		"default_state_key": String(config.default_state_key) if config != null else "",
		"config_path": config_path, "config_digest": config_digest, "generation": generation,
		"states": states, "modules": modules, "transitions": raw.get("transitions", [])}


func _append_snapshot_modules(target: Array, entries: Array[GDGameModuleEntryRes], scope: String, active: Dictionary) -> void:
	for i in entries.size():
		var entry := entries[i]
		var meta := GDGameModuleMeta.read(entry.module_script)
		var item := {"id": entry.module_id, "display_name": entry.display_name, "scope": scope,
			"script_path": entry.script_path(), "category": meta.category, "config_order": i,
			"initialization_order": -1, "lifecycle": "idle", "tick_enabled": meta.tick_enabled,
			"is_ticking": false, "debug_restartable": meta.debug_restartable,
			"instance_serial": 0, "last_fault": {}}
		if active.has(entry.module_id):
			item.merge(active[entry.module_id], true)
		target.append(item)


func record_event(kind: String, data: Dictionary = {}) -> void:
	var detail: Variant = data.get("detail", data)
	events.append({"seq": _next_seq, "frame": Engine.get_process_frames(), "usec": Time.get_ticks_usec(),
		"generation": generation, "kind": kind, "state_key": str(data.get("state_key", current_state_key)),
		"module_id": data.get("module_id", -1), "result": str(data.get("result", "ok")),
		"detail": _plain(detail)})
	_next_seq += 1
	if events.size() > EVENT_LIMIT:
		events.pop_front()


func _on_lifecycle(kind: StringName, detail: Dictionary) -> void:
	record_event(String(kind), detail)


func _process(delta: float) -> void:
	if protocol != null:
		protocol.process_commands()
	if should_tick():
		machine.tick_update(delta)
	if protocol != null:
		protocol.update(delta)


func _physics_process(delta: float) -> void:
	if should_tick():
		machine.tick_fixed_update(delta)


func should_tick() -> bool:
	return _is_running() and (not is_inside_tree() or not get_tree().paused or config.tick_when_paused)


func _is_running() -> bool:
	return machine != null and phase in ["running", "starting", "transitioning"] and not _stopping


func shutdown() -> void:
	if _stopping:
		return
	_stopping = true
	if machine != null and machine.is_callback_active():
		machine.enqueue_shutdown(_shutdown_now)
	else:
		_shutdown_now()


func _shutdown_now() -> void:
	if machine != null:
		machine.shutdown()
		machine.lifecycle_hook = Callable()
		machine = null
		record_event("gm_shutdown")
	phase = "idle"
	_keys.clear()
	if current == self:
		current = null
	_stopping = false


func _exit_tree() -> void:
	shutdown()
	if protocol != null:
		protocol.close()
		protocol = null


static func _result(ok: bool, code: String, message: String, at_phase: String = "command") -> Dictionary:
	return {"ok": ok, "code": code, "message": message, "phase": at_phase}


static func _plain(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[str(key)] = _plain(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_plain(item))
		return result
	if value is StringName:
		return String(value)
	if value == null or value is String or value is int or value is float or value is bool:
		return value
	return str(value)
