@tool
class_name GDGameModeLink
extends RefCounted

## Only plain, serializable payloads cross this boundary.
signal received(kind: String, payload: Dictionary)


func send(_kind: String, _payload: Dictionary) -> void:
	pass


func close() -> void:
	pass
