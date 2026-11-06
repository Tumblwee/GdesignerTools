class_name GDGameModeEngineLink
extends GDGameModeLink

const PREFIX := "gdesigner_gm"
var _registered := false


func open() -> void:
	if not _registered and OS.is_debug_build() and EngineDebugger.is_active():
		EngineDebugger.register_message_capture(PREFIX, _capture)
		_registered = true


func send(kind: String, payload: Dictionary) -> void:
	if _registered and EngineDebugger.is_active():
		EngineDebugger.send_message(PREFIX + ":" + kind, [payload])


func close() -> void:
	if _registered:
		EngineDebugger.unregister_message_capture(PREFIX)
		_registered = false


func _capture(kind: String, data: Array) -> bool:
	if data.size() != 1 or not data[0] is Dictionary:
		return false
	received.emit(kind, data[0])
	return true
