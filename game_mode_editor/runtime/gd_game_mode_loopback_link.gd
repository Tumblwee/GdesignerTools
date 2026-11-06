class_name GDGameModeLoopbackLink
extends GDGameModeLink

var peer: WeakRef
var sent: Array[Dictionary] = []


static func create_pair() -> Array[GDGameModeLoopbackLink]:
	var first := GDGameModeLoopbackLink.new()
	var second := GDGameModeLoopbackLink.new()
	first.peer = weakref(second)
	second.peer = weakref(first)
	return [first, second]


func send(kind: String, payload: Dictionary) -> void:
	var copy: Dictionary = payload.duplicate(true)
	sent.append({"kind": kind, "payload": copy})
	var target: GDGameModeLoopbackLink = peer.get_ref() if peer != null else null
	if target != null:
		target.received.emit(kind, copy)


func close() -> void:
	peer = null
