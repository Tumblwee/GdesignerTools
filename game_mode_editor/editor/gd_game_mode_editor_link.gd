@tool
class_name GDGameModeEditorLink
extends GDGameModeLink

var session: EditorDebuggerSession


func _init(value: EditorDebuggerSession = null) -> void:
	session = value


func send(kind: String, payload: Dictionary) -> void:
	if session != null and session.is_active():
		session.send_message("gdesigner_gm:" + kind, [payload])


func deliver(kind: String, payload: Dictionary) -> void:
	received.emit(kind, payload)
