@tool
class_name GDGameModeDebuggerPlugin
extends EditorDebuggerPlugin

signal sessions_changed

static var current: GDGameModeDebuggerPlugin
var sessions: Dictionary = {}
var _connections: Array[Dictionary] = []


func _init() -> void:
	current = self


func _has_capture(capture: String) -> bool:
	return capture == "gdesigner_gm"


func _capture(message: String, data: Array, session_id: int) -> bool:
	if not message.begins_with("gdesigner_gm:"):
		return false
	if not sessions.has(session_id) or data.size() != 1 or not data[0] is Dictionary:
		return true
	var model: GDGameModeSession = sessions[session_id]
	(model.link as GDGameModeEditorLink).deliver(message.trim_prefix("gdesigner_gm:"), data[0])
	return true


func _setup_session(session_id: int) -> void:
	if sessions.has(session_id):
		return
	var native_session := get_session(session_id)
	var model := GDGameModeSession.new()
	model.session_id = session_id
	model.bind_transport(GDGameModeEditorLink.new(native_session))
	sessions[session_id] = model
	_connect(native_session.started, model.start)
	_connect(native_session.stopped, model.stop)
	_connect(native_session.breaked, func(_can_debug: bool) -> void: model.set_paused(true))
	_connect(native_session.continued, model.set_paused.bind(false))
	_connect(model.changed, _notify_changed)
	if native_session.is_active():
		model.start()
		model.set_paused(native_session.is_breaked())
	sessions_changed.emit()


func get_session_model(id: int) -> GDGameModeSession:
	return sessions.get(id)


func session_list() -> Array[GDGameModeSession]:
	var result: Array[GDGameModeSession] = []
	var ids := sessions.keys()
	ids.sort()
	for id in ids:
		result.append(sessions[id])
	return result


func poll() -> void:
	for model: GDGameModeSession in sessions.values():
		model.poll_timeout()


func shutdown() -> void:
	for connection in _connections:
		var source: Signal = connection.signal
		var callback: Callable = connection.callback
		if not source.is_null() and source.is_connected(callback):
			source.disconnect(callback)
	_connections.clear()
	for model: GDGameModeSession in sessions.values():
		model.stop()
		model.bind_transport(null)
	sessions.clear()
	if current == self:
		current = null


func _connect(source: Signal, callback: Callable) -> void:
	source.connect(callback)
	_connections.append({"signal": source, "callback": callback})


func _notify_changed() -> void:
	sessions_changed.emit()
