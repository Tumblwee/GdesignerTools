@tool
class_name GDActorLibraryRes
extends Resource

## 演员编辑器数据模型（对应 ActorArchetypeSO / ActorArchetypeTypeKeywordsSO / ActorLibrarySO）
## StableId 从 1000 起算（与关卡侧对齐）。

const STABLE_ID_START := 1000

class ActorArchetypeRes extends GDArchetypeRes:
	pass


class ActorArchetypeTypeKeywordsRes extends GDKeywordCatalogSystem.KeywordCatalogRes:
	func _init() -> void:
		default_entry_value_type = GDCoreTypes.KeywordValueType.STRING


@export var display_name: String = ""
## 原型与类型目录用可落盘子类；数组不标内部类，避免存盘后被丢弃。
@export var archetypes: Array = []
@export var actor_type_keywords: Resource = null
@export var next_archetype_stable_id: int = STABLE_ID_START

func editor_add_archetype(archetype: ActorArchetypeRes) -> void:
	if archetype == null:
		return
	for a in archetypes:
		if a == archetype:
			return
	archetypes.append(archetype)
	if archetype.stable_id >= next_archetype_stable_id:
		next_archetype_stable_id = archetype.stable_id + 1
	emit_changed()

func editor_remove_archetype(archetype: ActorArchetypeRes) -> bool:
	if archetype == null or not archetypes.has(archetype):
		return false
	archetypes.erase(archetype)
	emit_changed()
	return true

func editor_set_actor_type_keywords(catalog: GDKeywordCatalogSystem.KeywordCatalogRes) -> void:
	actor_type_keywords = catalog
	emit_changed()

func editor_allocate_next_archetype_stable_id() -> int:
	var id := maxi(STABLE_ID_START, next_archetype_stable_id)
	next_archetype_stable_id = id + 1
	emit_changed()
	return id

func editor_reconcile_next_ids_after_load() -> void:
	var arch_max := STABLE_ID_START - 1
	for a in archetypes:
		if a != null and a.stable_id > arch_max:
			arch_max = a.stable_id
	next_archetype_stable_id = maxi(STABLE_ID_START, maxi(next_archetype_stable_id, arch_max + 1))
	emit_changed()
