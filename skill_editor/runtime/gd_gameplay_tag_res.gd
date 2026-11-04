@tool
class_name GDGameplayTagRes
extends Resource

## 玩法标签。带父子层级，可独立存成 .tres 被多个技能引用。

@export var tag_name: String = ""
@export var parent_tag: GDGameplayTagRes = null
@export_multiline var description: String = ""


func is_descendant_of(other: GDGameplayTagRes) -> bool:
	var cursor := self
	var guard := 64
	while cursor != null and guard > 0:
		if cursor == other:
			return true
		cursor = cursor.parent_tag
		guard -= 1
	return false
