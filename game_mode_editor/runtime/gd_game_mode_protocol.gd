class_name GDGameModeProtocol
extends RefCounted

const VERSION := 1
const REQUEST_HISTORY := 64
var _mode: WeakRef
var _link: GDGameModeLink
var _hello_received := false
var _compatible := false
var _editor_runtime := OS.has_feature("editor_runtime")
var _commands: Array[Dictionary] = []
var _request_ids: Array[String] = []
var _pending_ids: Dictionary = {}
var _elapsed := 0.0
var _last_snapshot := ""
var _last_event_seq := 0
var _welcome_identity: Array = []


func _init(mode: Node, link: GDGameModeLink) -> void:
	_mode = weakref(mode)
	_link = link
	_link.received.connect(_receive)


func close() -> void:
	if _link != null:
		if _link.received.is_connected(_receive):
			_link.received.disconnect(_receive)
		_link.close()
	_commands.clear()
	_pending_ids.clear()
	_link = null


func _receive(kind: String, payload: Dictionary) -> void:
	var mode: Node = _mode.get_ref()
	if mode == null:
		return
	if kind == "hello":
		_hello_received = true
		_compatible = payload.get("protocol") is int and payload.protocol == VERSION
		_send_welcome()
		_publish(true)
	elif kind == "command" and _hello_received:
		# This callback may be invoked from the debugger's suspended loop. It must
		# never enter business code or touch instances, even for validation.
		_commands.append(payload.duplicate(true))


func process_commands() -> void:
	var mode: Node = _mode.get_ref()
	if mode == null:
		return
	# New commands caused by callbacks wait until the next safe point.
	var batch: Array[Dictionary] = _commands.duplicate()
	_commands.clear()
	for command in batch:
		var id := str(command.get("request_id", ""))
		mode.record_event("command_received", {"detail": {"request_id": id, "kind": command.get("kind", "")}})
		var rejection := ""
		if not _compatible:
			rejection = "protocol_mismatch"
		elif not command.get("request_id") is String or id.is_empty() or not command.get("generation") is int or not command.get("process_token") is String or not command.get("kind") is String:
			rejection = "invalid_request"
		elif _request_ids.has(id) or _pending_ids.has(id):
			rejection = "duplicate_request"
		elif str(command.get("process_token", "")) != mode.process_token:
			rejection = "wrong_process"
		elif int(command.get("generation", -1)) != mode.generation:
			rejection = "stale_generation"
		elif command.kind == "apply_config" and not _editor_runtime:
			rejection = "editor_runtime_required"
		if not rejection.is_empty():
			_result(id, false, rejection, rejection, "validation")
			continue
		_request_ids.append(id)
		if _request_ids.size() > REQUEST_HISTORY:
			_request_ids.pop_front()
		_pending_ids[id] = true
		var arguments: Variant = command.get("args", {})
		var result: Dictionary
		if arguments is Dictionary:
			result = mode.execute_debug_command(str(command.get("kind", "")), arguments)
		else:
			result = {"ok": false, "code": "invalid_request", "message": "命令 args 必须是 Dictionary。", "phase": "validation"}
		_pending_ids.erase(id)
		# Completion handlers may immediately send their next command. Publish the
		# new identity first so that follow-up requests carry the current generation.
		if _welcome_identity != [mode.generation, mode.config_path, mode.config_digest]:
			_send_welcome()
		_result(id, bool(result.get("ok", false)), str(result.get("code", "invalid_request")),
			str(result.get("message", "")), str(result.get("phase", "command")))


func update(delta: float) -> void:
	if not _hello_received:
		return
	var mode: Node = _mode.get_ref()
	if mode != null and _welcome_identity != [mode.generation, mode.config_path, mode.config_digest]:
		_send_welcome()
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		_publish(false)


func _send_welcome() -> void:
	var mode: Node = _mode.get_ref()
	if mode != null and _link != null:
		_welcome_identity = [mode.generation, mode.config_path, mode.config_digest]
		_link.send("welcome", {"protocol": VERSION, "process_token": mode.process_token,
			"generation": mode.generation, "project_path": ProjectSettings.globalize_path("res://"),
			"editor_runtime": _editor_runtime, "config_path": mode.config_path,
			"config_digest": mode.config_digest})


func _publish(force: bool) -> void:
	var mode: Node = _mode.get_ref()
	if mode == null or _link == null:
		return
	var snapshot: Dictionary = mode.capture_snapshot()
	var encoded := JSON.stringify(snapshot)
	if force or encoded != _last_snapshot:
		_last_snapshot = encoded
		_link.send("snapshot", snapshot)
	var events: Array = []
	for event in mode.events:
		if force or int(event.seq) > _last_event_seq:
			events.append(event)
		_last_event_seq = maxi(_last_event_seq, int(event.seq))
	if not events.is_empty():
		_link.send("events", {"events": events})


func _result(id: String, ok: bool, code: String, message: String, phase: String) -> void:
	var payload := {"request_id": id, "ok": ok, "code": code, "message": message, "phase": phase}
	var mode: Node = _mode.get_ref()
	if mode != null:
		mode.record_event("command_result", {"result": code, "detail": payload})
	if _link != null:
		_link.send("command_result", payload)
