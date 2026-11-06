@tool
class_name GDLevelLibraryRes
extends Resource

## 独立的原型集合。多个关卡引用同一个库，实例仍归各自关卡所有。
@export var display_name: String = ""
@export var archetypes: Array[GDArchetypeRes] = []
@export var next_archetype_stable_id: int = 1000

func reconcile_ids() -> void:
	for archetype in archetypes:
		if archetype != null:
			next_archetype_stable_id = maxi(next_archetype_stable_id, archetype.stable_id + 1)
