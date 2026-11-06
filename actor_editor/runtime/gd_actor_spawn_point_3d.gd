@tool
class_name GDActorSpawnPoint3D
extends Node3D

@export var actor_reference: GDActorReferenceRes = null:
	set(value):
		if actor_reference != null and actor_reference.changed.is_connected(_queue_refresh):
			actor_reference.changed.disconnect(_queue_refresh)
		actor_reference = value
		if actor_reference != null:
			actor_reference.changed.connect(_queue_refresh)
		_queue_refresh()
@export var initial_level := 1
@export var spawn_on_ready := true
## 仅编辑器拖放时设置，不写入场景，运行时自然恢复正常生成行为。
var preview_only := false
var spawned_actor: Node = null

func _ready() -> void:
	_refresh()

func _queue_refresh() -> void:
	if is_inside_tree():
		_refresh.call_deferred()

func _refresh() -> void:
	GDActorSpawnRuntime.refresh(self)

func spawn_actor() -> Node:
	return GDActorSpawnRuntime.spawn(self, Engine.is_editor_hint() or preview_only)

func clear_actor() -> void:
	GDActorSpawnRuntime.clear(self)
