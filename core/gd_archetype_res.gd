@tool
class_name GDArchetypeRes
extends Resource

## 通用原型 Resource（对应 TimiMiniGame.Core.ArchetypeSO + IArchetype + ArchetypeRegistry + EntityCatalogSO）
## 关卡编辑器（GDLevelArchetypeRes）、演员编辑器（GDActorArchetypeRes）共用此基类。

@export var stable_id: int = 0
@export var display_name: String = ""
@export var archetype_type_stable_id: int = 0
@export var manufactured_prefab_address: String = ""
@export var preview_prefab_address: String = ""
@export var use_custom_instance_id_range: bool = false
@export var instance_id_min: int = 0
@export var instance_id_max: int = 0
@export var custom_attributes: Array[GDCustomAttributeDef] = []
@export var is_override_archetype: bool = false
@export var override_base_archetype: GDArchetypeRes = null

## Editor prefab address lookup registry: address (file stem or res:// path) -> res:// path
static var _address_to_path: Dictionary = {}

var entity_prefab_address: String:
	get:
		return manufactured_prefab_address

var has_valid_custom_instance_id_range: bool:
	get:
		return use_custom_instance_id_range and instance_id_min > 0 and instance_id_max >= instance_id_min

func editor_bind_stable_id(p_stable_id: int) -> void:
	stable_id = p_stable_id
	emit_changed()

func editor_set_override_base(p_base: GDArchetypeRes) -> void:
	is_override_archetype = true
	override_base_archetype = p_base
	emit_changed()

func editor_set_display_name(p_display_name: String) -> void:
	display_name = p_display_name
	emit_changed()

func editor_set_archetype_type_stable_id(p_type_stable_id: int) -> void:
	archetype_type_stable_id = p_type_stable_id
	emit_changed()

func editor_set_custom_instance_id_range(p_use: bool, p_min: int, p_max: int) -> void:
	use_custom_instance_id_range = p_use
	instance_id_min = p_min
	instance_id_max = p_max
	emit_changed()

func editor_set_prefab_addresses(p_entity_addr: String, p_preview_addr: String) -> void:
	manufactured_prefab_address = p_entity_addr
	preview_prefab_address = p_preview_addr
	emit_changed()

func editor_init_with_addresses(
	p_stable_id: int,
	p_display_name: String,
	p_entity_addr: String,
	p_preview_addr: String
) -> void:
	stable_id = p_stable_id
	display_name = p_display_name
	manufactured_prefab_address = p_entity_addr
	preview_prefab_address = p_preview_addr
	emit_changed()

func editor_set_custom_attributes(defs: Array[GDCustomAttributeDef]) -> void:
	custom_attributes = defs
	emit_changed()

func editor_resolve_manufactured_prefab() -> PackedScene:
	return editor_resolve_prefab_by_address(manufactured_prefab_address)

func editor_resolve_preview_prefab() -> PackedScene:
	return editor_resolve_prefab_by_address(preview_prefab_address)

func editor_get_catalog_thumbnail_prefab() -> PackedScene:
	var preview := editor_resolve_preview_prefab()
	return preview if preview != null else editor_resolve_manufactured_prefab()

static func register_prefab_address(address: String, res_path: String) -> void:
	if not address.is_empty() and not res_path.is_empty():
		_address_to_path[address] = res_path

static func resolve_address_of_path(res_path: String) -> String:
	if res_path.is_empty():
		return ""
	return res_path.get_file().get_basename()

static func editor_resolve_prefab_path_by_address(address: String) -> String:
	if address.is_empty():
		return ""
	if address.begins_with("res://") and ResourceLoader.exists(address):
		return address
	if _address_to_path.has(address) and ResourceLoader.exists(_address_to_path[address]):
		return _address_to_path[address]
	var found := _scan_for_scene_by_stem("res://", address)
	if not found.is_empty():
		_address_to_path[address] = found
	return found

static func editor_resolve_prefab_by_address(address: String) -> PackedScene:
	var path := editor_resolve_prefab_path_by_address(address)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	return res as PackedScene

static func _scan_for_scene_by_stem(dir_path: String, stem: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname != "." and fname != ".." and not fname.begins_with("."):
			var full := dir_path.path_join(fname) if dir_path != "res://" else "res://" + fname
			if dir.current_is_dir():
				if fname != "GdesignerTools":
					var sub := _scan_for_scene_by_stem(full, stem)
					if not sub.is_empty():
						dir.list_dir_end()
						return sub
			elif fname.ends_with(".tscn") or fname.ends_with(".scn"):
				if fname.get_basename() == stem:
					dir.list_dir_end()
					return full
		fname = dir.get_next()
	dir.list_dir_end()
	return ""


## 默认 IArchetypeRegistry 实现（stableId -> archetype 字典 + 顺序列表）
class ArchetypeRegistry extends RefCounted:
	var _by_stable_id: Dictionary = {} # int -> GDArchetypeRes
	var _ordered: Array[GDArchetypeRes] = []

	func _init(archetypes: Array = []) -> void:
		for a in archetypes:
			if a == null or not (a is GDArchetypeRes):
				continue
			var arch: GDArchetypeRes = a
			if _by_stable_id.has(arch.stable_id):
				GDGameLogger.log_warning(
					"[ArchetypeRegistry] duplicate archetype stableId=%d · 保留首个 (%s)" % [
						arch.stable_id,
						(_by_stable_id[arch.stable_id] as GDArchetypeRes).display_name
					]
				)
				continue
			_by_stable_id[arch.stable_id] = arch
			_ordered.append(arch)

	var all: Array[GDArchetypeRes]:
		get:
			return _ordered

	var count: int:
		get:
			return _ordered.size()

	func find_by_stable_id(p_stable_id: int) -> GDArchetypeRes:
		return _by_stable_id.get(p_stable_id, null)

	func try_get_by_stable_id(p_stable_id: int) -> Dictionary:
		if _by_stable_id.has(p_stable_id):
			return {"ok": true, "archetype": _by_stable_id[p_stable_id]}
		return {"ok": false, "archetype": null}
