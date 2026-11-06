@tool
class_name GDActorReferenceRes
extends Resource

## 库内 ID 只在该演员库内唯一。保存库引用避免把其内嵌演员复制到关卡里。
@export var library: GDActorLibraryRes = null:
	set(value):
		library = value
		emit_changed()
@export var stable_id: int = 0:
	set(value):
		stable_id = value
		emit_changed()
@export var standalone_archetype: GDArchetypeRes = null:
	set(value):
		standalone_archetype = value
		emit_changed()

func _init() -> void:
	resource_local_to_scene = true

static func same(a: GDActorReferenceRes, b: GDActorReferenceRes) -> bool:
	if a == null or b == null:
		return a == b
	return a.library == b.library and a.stable_id == b.stable_id and a.standalone_archetype == b.standalone_archetype

static func from_actor(actor: GDArchetypeRes, source: GDActorLibraryRes = null) -> GDActorReferenceRes:
	var reference := GDActorReferenceRes.new()
	if source != null and source.archetypes.has(actor):
		reference.library = source
		reference.stable_id = actor.stable_id
	else:
		reference.standalone_archetype = actor
	return reference

func resolve() -> GDArchetypeRes:
	if library != null:
		for actor: GDArchetypeRes in library.archetypes:
			if actor != null and actor.stable_id == stable_id:
				return actor
		return null
	return standalone_archetype
