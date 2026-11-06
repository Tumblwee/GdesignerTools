@tool
class_name GDGameModeSession
extends RefCounted

## 一个调试会话的内存镜像；不接触 GDDocument，也不会把监控数据存入配置。
signal changed
signal command_completed(result: Dictionary)

const PROTOCOL := 1
const EVENT_LIMIT := 500
const COMMAND_TIMEOUT_USEC := 10000000
const HELLO_INTERVAL_USEC := 1000000

var session_id: int = -1
var link: GDGameModeLink
var local_project_path: String = ProjectSettings.globalize_path("res://")
var connected: bool = false
var paused: bool = false
var handshake_complete: bool = false
var ever_connected: bool = false
var welcome: Dictionary = {}
var snapshot: Dictionary = {}
var events: Array[Dictionary] = []
var pending_request: Dictionary = {}
var last_result: Dictionary = {}
var timed_out: bool = false
var _request_serial: int = 0
var _last_event_seq: int = -1
var _last_hello_usec: int = 0


func bind_transport(transport: GDGameModeLink) -> void:
	if link != null and link.received.is_connected(receive):
		link.received.disconnect(receive)
	link = transport
	if link != null:
		link.received.connect(receive)


func start() -> void:
	connected = true
	ever_connected = true
	paused = false
	handshake_complete = false
	pending_request.clear()
	timed_out = false
	if link != null:
		_last_hello_usec = Time.get_ticks_usec()
		link.send("hello", {"protocol": PROTOCOL})
	changed.emit()


func stop() -> void:
	connected = false
	paused = false
	handshake_complete = false
	pending_request.clear()
	timed_out = false
	changed.emit()


func set_paused(value: bool) -> void:
	paused = value
	changed.emit()


func receive(kind: String, payload: Dictionary) -> void:
	if not connected:
		return
	match kind:
		"welcome":
			if not payload.get("protocol") is int or not payload.get("generation") is int or not payload.get("process_token") is String or str(payload.process_token).is_empty():
				return
			var previous_token := str(welcome.get("process_token", ""))
			var next_token := str(payload.get("process_token", ""))
			if previous_token != next_token:
				snapshot.clear()
				events.clear()
				_last_event_seq = -1
				pending_request.clear()
				last_result.clear()
				timed_out = false
			welcome = payload.duplicate(true)
			handshake_complete = not next_token.is_empty()
		"snapshot":
			if not handshake_complete:
				return
			var incoming: Variant = payload.get("snapshot", payload)
			if not _valid_snapshot(incoming):
				return
			snapshot = incoming.duplicate(true)
			_append_events(payload.get("events", []))
		"events":
			if not handshake_complete:
				return
			_append_events(payload.get("events", []))
		"command_result":
			if pending_request.is_empty() or str(payload.get("request_id", "")) != str(pending_request.get("request_id", "")):
				return
			last_result = payload.duplicate(true)
			pending_request.clear()
			timed_out = false
			command_completed.emit(last_result)
		_:
			return
	changed.emit()


static func _valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for field in ["states", "modules", "transitions"]:
		var entries: Variant = value.get(field, [])
		if not entries is Array:
			return false
		for entry in entries:
			if not entry is Dictionary:
				return false
	return true


func _append_events(incoming: Variant) -> void:
	if not incoming is Array:
		return
	for value in incoming:
		if not value is Dictionary or not value.get("seq") is int:
			continue
		var seq := int(value.get("seq", -1))
		if seq <= _last_event_seq:
			continue
		_last_event_seq = seq
		events.append(value.duplicate(true))
	while events.size() > EVENT_LIMIT:
		events.pop_front()


func status_text() -> String:
	if not connected:
		return "已断开" if ever_connected else "未连接"
	if not handshake_complete:
		return "连接中，等待 GameMode"
	if int(welcome.get("protocol", -1)) != PROTOCOL:
		return "协议不兼容"
	if paused:
		return "断点暂停"
	if timed_out:
		return "已连接 · 无回执"
	return "已连接"


func can_command() -> bool:
	return connected and handshake_complete and not paused and pending_request.is_empty() and int(welcome.get("protocol", -1)) == PROTOCOL


func apply_block_reason() -> String:
	if not connected or not handshake_complete:
		return "未连接运行中的 GameMode"
	if int(welcome.get("protocol", -1)) != PROTOCOL:
		return "协议不兼容，只能监控"
	if paused:
		return "断点暂停期间不能改变运行状态"
	if not pending_request.is_empty():
		return "无回执，请等待或重新连接" if timed_out else "正在等待上一条命令的回执"
	if not bool(welcome.get("editor_runtime", false)):
		return "只能向本工程的编辑器运行环境应用配置"
	if _normalized_project(str(welcome.get("project_path", ""))) != _normalized_project(local_project_path):
		return "运行端来自其他工程，不能应用本工程配置"
	return ""


func can_apply() -> bool:
	return apply_block_reason().is_empty()


func send_command(kind: String, args: Dictionary = {}) -> String:
	if not can_command() or link == null:
		return ""
	if kind == "apply_config" and not can_apply():
		return ""
	_request_serial += 1
	var request_id := "%s:%s:%s" % [session_id, Time.get_ticks_usec(), _request_serial]
	var command := {
		"request_id": request_id,
		"process_token": str(welcome.get("process_token", "")),
		"generation": int(welcome.get("generation", 0)),
		"kind": kind,
		"args": args.duplicate(true),
	}
	pending_request = command.duplicate(true)
	pending_request["sent_usec"] = Time.get_ticks_usec()
	timed_out = false
	last_result.clear()
	link.send("command", command)
	changed.emit()
	return request_id


## Timeout is display-only: a delayed command must never be retried automatically.
func poll_timeout(now_usec: int = -1) -> void:
	if now_usec < 0:
		now_usec = Time.get_ticks_usec()
	# Session.started can precede Bootstrap registering the runtime capture.
	# Retry only the idempotent handshake, never a business command.
	if connected and not handshake_complete and link != null and now_usec - _last_hello_usec >= HELLO_INTERVAL_USEC:
		_last_hello_usec = now_usec
		link.send("hello", {"protocol": PROTOCOL})
	if pending_request.is_empty() or timed_out:
		return
	if now_usec - int(pending_request.get("sent_usec", now_usec)) >= COMMAND_TIMEOUT_USEC:
		timed_out = true
		changed.emit()


func label() -> String:
	var token := str(welcome.get("process_token", ""))
	return "%s #%s%s" % ["本地游戏" if bool(welcome.get("editor_runtime", false)) else "游戏", session_id + 1, " · " + token.left(8) if not token.is_empty() else ""]


static func _normalized_project(path: String) -> String:
	var normalized := path.replace("\\", "/").simplify_path().trim_suffix("/")
	return normalized.to_lower() if OS.get_name() == "Windows" else normalized
