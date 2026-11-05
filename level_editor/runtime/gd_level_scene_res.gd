@tool
class_name GDLevelSceneRes
extends Resource

## 关卡场景核心数据资产（对应 LevelSceneSO + LevelArchetypeSO + PlacementInstanceNameUtil）
## ID Schema:
##   PlacementInstance.instance_id: 10000+ 单调递增
##   Archetype.stable_id:           1000+  单调递增
##   PathInstance.path_id:          20000+ 单调递增
## paths / camera_poses 由内部类组成，Godot 无法直接落盘内部类，统一经 codec_data 存取。

const INSTANCE_ID_START := 10000
const STABLE_ID_START := 1000
const PATH_ID_START := 20000
## 关卡原型资产名前缀：PlacementArchetype_<模块>_<名>。
const ARCHETYPE_ASSET_PREFIX := "PlacementArchetype_"

class LevelArchetypeRes extends GDArchetypeRes:
	pass


@export var layout_id: String = ""
@export var format_version: int = 2
@export var display_name: String = ""
## 关卡编辑工作区，与运行时装配的 logic_scene_path / art_scene_path 分开。
@export var scene_path: String = ""
@export var logic_scene_path: String = ""
@export var logic_scene_name: String = ""
@export var art_scene_path: String = ""
@export var art_scene_name: String = ""

@export var placements: Array = []
@export var archetypes: Array[GDArchetypeRes] = []
@export var nav_mesh_prefab: PackedScene = null
@export var path_type_keywords: Resource = null
@export var placement_archetype_type_keywords: Resource = null

@export var next_instance_id: int = INSTANCE_ID_START
@export var next_archetype_stable_id: int = STABLE_ID_START
@export var next_path_id: int = PATH_ID_START

@export var scene_extras: Array = []

var paths: Array = [] # Array[GDPathSystem.PathInstance]
var camera_poses: Array = [] # Array[GDCameraPoseSystem.CameraPose]

## 唯一的落盘入口：paths / camera_poses 的编码形式。保存、加载、duplicate 均自动经过这里。
@export_storage var codec_data: Dictionary:
	get:
		return codec().encode({"paths": paths, "camera_poses": camera_poses})
	set(value):
		var data: Dictionary = codec().decode(value)
		paths = data.get("paths", []).filter(func(p: Variant) -> bool: return p is GDPathSystem.PathInstance)
		camera_poses = data.get("camera_poses", []).filter(func(c: Variant) -> bool: return c is GDCameraPoseSystem.CameraPose)

static var _codec: GDDataCodec = null

## 关卡路径与相机机位（GDPathSystem / GDCameraPoseSystem 内部类）的编解码器。
static func codec() -> GDDataCodec:
	if _codec == null:
		_codec = GDDataCodec.new([GDPathSystem, GDCameraPoseSystem])
	return _codec

func _init() -> void:
	if layout_id.is_empty():
		editor_ensure_layout_id()

func editor_ensure_layout_id() -> void:
	layout_id = "%08x%08x" % [randi(), Time.get_ticks_usec() & 0xFFFFFFFF]

func try_get_camera_pose(pose_name: String) -> Dictionary:
	if pose_name.is_empty():
		return {"ok": false, "pose": null}
	for candidate in camera_poses:
		if candidate != null and candidate.pose_name == pose_name:
			return {"ok": true, "pose": candidate}
	return {"ok": false, "pose": null}

func try_get_scene_extra(key: String) -> Dictionary:
	if key.is_empty():
		return {"ok": false, "version": 0, "json": ""}
	for e in scene_extras:
		if e != null and e.key == key:
			return {"ok": true, "version": e.version, "json": e.json}
	return {"ok": false, "version": 0, "json": ""}

func editor_set_scene_extra(key: String, version: int, json_str: String) -> void:
	if key.is_empty():
		return
	for i in range(scene_extras.size() - 1, -1, -1):
		if scene_extras[i] != null and scene_extras[i].key == key:
			scene_extras.remove_at(i)
	scene_extras.append(GDPlacementExtraRes.new(key, version, json_str))
	emit_changed()

func editor_remove_scene_extra(key: String) -> void:
	if key.is_empty():
		return
	for i in range(scene_extras.size() - 1, -1, -1):
		if scene_extras[i] != null and scene_extras[i].key == key:
			scene_extras.remove_at(i)
	emit_changed()

func editor_bind_archetype_type_keywords(catalog: GDKeywordCatalogSystem.KeywordCatalogRes) -> void:
	placement_archetype_type_keywords = catalog
	emit_changed()

func editor_bind_path_type_keywords(catalog: GDKeywordCatalogSystem.KeywordCatalogRes) -> void:
	path_type_keywords = catalog
	emit_changed()

func editor_bind_scenes(p_scene_path: String, p_art_scene_path: String = "", p_logic_scene_path: String = "") -> void:
	scene_path = p_scene_path
	art_scene_path = p_art_scene_path
	art_scene_name = p_art_scene_path.get_file().get_basename() if not p_art_scene_path.is_empty() else ""
	logic_scene_path = p_logic_scene_path
	logic_scene_name = p_logic_scene_path.get_file().get_basename() if not p_logic_scene_path.is_empty() else ""
	emit_changed()

func editor_add_archetype(archetype: GDArchetypeRes) -> void:
	if archetype == null:
		return
	for a in archetypes:
		if a == archetype:
			return
	archetypes.append(archetype)
	if archetype.stable_id >= next_archetype_stable_id:
		next_archetype_stable_id = archetype.stable_id + 1
	emit_changed()

func editor_remove_archetype(archetype: GDArchetypeRes) -> bool:
	if archetype == null or not archetypes.has(archetype):
		return false
	archetypes.erase(archetype)
	emit_changed()
	return true

func editor_remove_placements_by_archetype_stable_id(arch_stable_id: int) -> int:
	if arch_stable_id <= 0:
		return 0
	var removed := 0
	for i in range(placements.size() - 1, -1, -1):
		var p = placements[i]
		if p != null and p.archetype_stable_id == arch_stable_id:
			placements.remove_at(i)
			removed += 1
	if removed > 0:
		emit_changed()
	return removed

func editor_count_placements_by_archetype_stable_id(arch_stable_id: int) -> int:
	if arch_stable_id <= 0:
		return 0
	var count := 0
	for p in placements:
		if p != null and p.archetype_stable_id == arch_stable_id:
			count += 1
	return count

func editor_add_placement(
	arch_stable_id: int,
	pos: Vector3,
	euler: Vector3,
	p_scale: Vector3,
	initial_level: int
) -> int:
	var res := editor_try_add_placement(arch_stable_id, pos, euler, p_scale, initial_level)
	if not bool(res.get("ok", false)):
		GDGameLogger.log_error_d("[GDLevelSceneRes] 添加 Placement 失败：%s" % str(res.get("error", "")))
		return 0
	return int(res.get("instance_id", 0))

func editor_try_add_placement(
	arch_stable_id: int,
	pos: Vector3,
	euler: Vector3,
	p_scale: Vector3,
	initial_level: int
) -> Dictionary:
	var arch := find_archetype_by_stable_id(arch_stable_id)
	var occupied := _collect_occupied_instance_ids()
	var use_custom := arch != null and arch.use_custom_instance_id_range
	var min_id := arch.instance_id_min if arch != null else 0
	var max_id := arch.instance_id_max if arch != null else 0

	var alloc := GDPlacementData.PlacementInstanceIdRangeLogic.try_allocate(
		use_custom, min_id, max_id, next_instance_id, occupied
	)
	if not bool(alloc.get("ok", false)):
		return {"ok": false, "instance_id": 0, "error": str(alloc.get("error", ""))}

	var inst_id := int(alloc.get("instance_id", 0))
	if not use_custom:
		next_instance_id = int(alloc.get("new_next_instance_id", next_instance_id))

	var inst := GDPlacementInstanceRes.new(inst_id, arch_stable_id, pos, euler, p_scale, initial_level)
	var def_name := compose_default_instance_name(arch, inst_id)
	var def_display := compose_default_instance_display_name(arch, inst_id)
	inst.editor_init_instance_identity(def_name, def_display)

	var def_overrides := GDPlacementData.PlacementInstanceIdRangeLogic.create_default_overrides(arch)
	if not def_overrides.is_empty():
		inst = inst.with_overrides(def_overrides)

	placements.append(inst)
	emit_changed()
	return {"ok": true, "instance_id": inst_id, "error": ""}

func editor_try_standardize_instance_ids(archetype: GDArchetypeRes) -> Dictionary:
	if archetype == null:
		return {"ok": false, "remaps": [], "error": "原型为空。"}
	if not archetype.use_custom_instance_id_range:
		return {"ok": false, "remaps": [], "error": "请先勾选「自定义 ID 段」并设置 Min / Max。"}
	var plan := GDPlacementData.PlacementInstanceIdRangeLogic.try_plan_standardize(
		placements, archetype.stable_id, archetype.instance_id_min, archetype.instance_id_max
	)
	if not bool(plan.get("ok", false)):
		return plan
	var remaps: Array = plan.get("remaps", [])
	if remaps.is_empty():
		return {"ok": true, "remaps": [], "error": ""}

	var steps: Array[Dictionary] = []
	for r in remaps:
		var old_id := int(r["old_id"])
		var new_id := int(r["new_id"])
		var found := editor_try_get_placement(old_id)
		if not bool(found.get("ok", false)):
			return {"ok": false, "remaps": [], "error": "标准化取消：找不到 InstanceId=%d。" % old_id}
		steps.append({"inst": found["inst"], "old_id": old_id, "new_id": new_id})

	var occupied := _collect_occupied_instance_ids()
	var temps := GDPlacementData.PlacementInstanceIdRangeLogic.allocate_temp_ids(steps.size(), occupied)
	for i in range(steps.size()):
		_rewrite_instance_id_preserving_identity(steps[i]["inst"], steps[i]["old_id"], temps[i])
	for i in range(steps.size()):
		_rewrite_instance_id_preserving_identity(steps[i]["inst"], temps[i], steps[i]["new_id"])
	emit_changed()
	return {"ok": true, "remaps": remaps, "error": ""}

static func _rewrite_instance_id_preserving_identity(inst: GDPlacementData.PlacementInstance, old_id: int, new_id: int) -> void:
	inst.editor_rewrite_instance_id(new_id)
	var old_str := str(old_id)
	var new_str := str(new_id)
	var n := inst.instance_name
	var d := inst.display_name
	var n_up := n.replace(old_str, new_str) if n.contains(old_str) else n
	var d_up := d.replace(old_str, new_str) if d.contains(old_str) else d
	if n_up != n or d_up != d:
		inst.editor_init_instance_identity(n_up, d_up)

## 改一个实例的 ID；名称和显示名里的旧 ID 一并替换。新 ID 必须是正整数且未被占用。
func editor_reset_instance_id(old_id: int, new_id: int) -> bool:
	var found := editor_try_get_placement(old_id)
	if new_id <= 0 or not bool(found.get("ok", false)) or bool(editor_try_get_placement(new_id).get("ok", false)):
		return false
	_rewrite_instance_id_preserving_identity(found["inst"], old_id, new_id)
	emit_changed()
	return true

func editor_allocate_next_archetype_stable_id() -> int:
	var id := maxi(STABLE_ID_START, next_archetype_stable_id)
	next_archetype_stable_id = id + 1
	emit_changed()
	return id

func editor_allocate_next_instance_id() -> int:
	var alloc := GDPlacementData.PlacementInstanceIdRangeLogic.try_allocate(
		false, 0, 0, next_instance_id, _collect_occupied_instance_ids()
	)
	if not bool(alloc.get("ok", false)):
		GDGameLogger.log_error_d("[GDLevelSceneRes] 分配 InstanceId 失败：%s" % str(alloc.get("error", "")))
		return 0
	next_instance_id = int(alloc.get("new_next_instance_id", next_instance_id))
	emit_changed()
	return int(alloc.get("instance_id", 0))

func editor_reconcile_next_ids_after_load() -> void:
	var inst_max := INSTANCE_ID_START - 1
	for p in placements:
		if p != null and p.instance_id > inst_max:
			inst_max = p.instance_id
	next_instance_id = maxi(INSTANCE_ID_START, maxi(next_instance_id, inst_max + 1))

	var arch_max := STABLE_ID_START - 1
	for a in archetypes:
		if a != null and a.stable_id > arch_max:
			arch_max = a.stable_id
	next_archetype_stable_id = maxi(STABLE_ID_START, maxi(next_archetype_stable_id, arch_max + 1))

	var path_max := PATH_ID_START - 1
	for pt in paths:
		if pt != null and pt.path_id > path_max:
			path_max = pt.path_id
	next_path_id = maxi(PATH_ID_START, maxi(next_path_id, path_max + 1))
	emit_changed()

func editor_overwrite_next_ids(p_next_instance_id: int, p_next_archetype_stable_id: int) -> void:
	next_instance_id = maxi(INSTANCE_ID_START, p_next_instance_id)
	next_archetype_stable_id = maxi(STABLE_ID_START, p_next_archetype_stable_id)
	emit_changed()

func editor_remove_placement(p_instance_id: int) -> bool:
	for i in range(placements.size()):
		if placements[i] != null and placements[i].instance_id == p_instance_id:
			placements.remove_at(i)
			emit_changed()
			return true
	return false

func editor_move_placement(p_instance_id: int, insert_index: int) -> bool:
	var from := -1
	for i in range(placements.size()):
		if placements[i] != null and placements[i].instance_id == p_instance_id:
			from = i
			break
	if from < 0:
		return false
	var clamped := clampi(insert_index, 0, placements.size())
	var to := clamped - 1 if clamped > from else clamped
	if to == from:
		return false
	var inst = placements[from]
	placements.remove_at(from)
	placements.insert(to, inst)
	emit_changed()
	return true

func editor_try_get_placement(p_instance_id: int) -> Dictionary:
	for i in range(placements.size()):
		if placements[i] != null and placements[i].instance_id == p_instance_id:
			return {"ok": true, "inst": placements[i], "index": i}
	return {"ok": false, "inst": null, "index": -1}

func editor_replace_placement(p_instance_id: int, updated: GDPlacementData.PlacementInstance) -> void:
	for i in range(placements.size()):
		if placements[i] != null and placements[i].instance_id == p_instance_id:
			placements[i] = updated
			emit_changed()
			return

func editor_replace_placement_archetype(p_instance_id: int, new_arch_stable_id: int) -> bool:
	if p_instance_id <= 0 or new_arch_stable_id <= 0:
		return false
	var found := editor_try_get_placement(p_instance_id)
	if not bool(found.get("ok", false)):
		return false
	var inst: GDPlacementData.PlacementInstance = found["inst"]
	if inst.archetype_stable_id == new_arch_stable_id:
		return false
	var arch := find_archetype_by_stable_id(new_arch_stable_id)
	if arch == null:
		return false
	var updated := inst.with_archetype_stable_id(new_arch_stable_id) \
		.with_name(compose_default_instance_name(arch, p_instance_id)) \
		.with_display_name(compose_default_instance_display_name(arch, p_instance_id))
	editor_replace_placement(p_instance_id, updated)
	return true

func editor_refresh_placement_identities_after_archetype_rename(
	archetype: GDArchetypeRes,
	old_asset_name: String,
	old_display_name: String
) -> int:
	if archetype == null:
		return 0
	var changed := 0
	for inst in placements:
		if inst == null or inst.archetype_stable_id != archetype.stable_id:
			continue
		var id: int = inst.instance_id
		var cur_name: String = inst.instance_name
		var cur_disp: String = inst.display_name
		var name_is_default: bool = (cur_name == _compose_instance_name_from_asset(old_asset_name, id)) or (
			not old_asset_name.is_empty() and cur_name == "%s_%d" % [old_asset_name, id]
		)
		var name_updated := compose_default_instance_name(archetype, id) if name_is_default else cur_name
		var disp_updated := compose_default_instance_display_name(archetype, id) \
			if cur_disp == _compose_instance_display_name_raw(old_display_name, old_asset_name, id) else cur_disp
		if name_updated != cur_name or disp_updated != cur_disp:
			inst.editor_init_instance_identity(name_updated, disp_updated)
			changed += 1
	if changed > 0:
		emit_changed()
	return changed

## 重命名原型（资源名 + 显示名），并同步仍在用默认命名的实例名 / 显示名。
func editor_rename_archetype(archetype: GDArchetypeRes, new_asset_name: String, new_display_name: String) -> Dictionary:
	if archetype == null or not archetypes.has(archetype):
		return {"ok": false, "changed": 0, "error": "原型不在当前关卡里。"}
	var clean_name := new_asset_name.strip_edges()
	var clean_disp := new_display_name.strip_edges()
	if not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(clean_name, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.TYPE_NAME):
		return {"ok": false, "changed": 0, "error": "名称必须是合法标识符（字母/数字/下划线，不可数字开头）。"}
	if clean_disp.is_empty():
		return {"ok": false, "changed": 0, "error": "显示名不能为空。"}
	for other in archetypes:
		if other != null and other != archetype and other.resource_name == clean_name:
			return {"ok": false, "changed": 0, "error": "已存在同名原型：%s" % clean_name}
	var old_asset := archetype.resource_name
	var old_display := archetype.display_name
	archetype.resource_name = clean_name
	archetype.editor_set_display_name(clean_disp)
	var changed := editor_refresh_placement_identities_after_archetype_rename(archetype, old_asset, old_display)
	emit_changed()
	return {"ok": true, "changed": changed, "error": ""}

# ── Paths (20000+) ──

func editor_add_path(p_type_keyword: int, p_spline: GDPathSystem.SplineData, p_speed: float = 1.0) -> int:
	var pid := editor_allocate_next_path_id()
	var inst := GDPathSystem.PathInstance.new(pid, p_type_keyword, p_spline, p_speed)
	inst.editor_init_path_identity("Path_%d" % pid, "Path #%d" % pid)
	paths.append(inst)
	emit_changed()
	return pid

func editor_remove_path(p_path_id: int) -> bool:
	for i in range(paths.size()):
		if paths[i] != null and paths[i].path_id == p_path_id:
			paths.remove_at(i)
			emit_changed()
			return true
	return false

func editor_try_get_path(p_path_id: int) -> Dictionary:
	for i in range(paths.size()):
		if paths[i] != null and paths[i].path_id == p_path_id:
			return {"ok": true, "path": paths[i], "index": i}
	return {"ok": false, "path": null, "index": -1}

func editor_replace_path(p_path_id: int, updated: GDPathSystem.PathInstance) -> void:
	for i in range(paths.size()):
		if paths[i] != null and paths[i].path_id == p_path_id:
			paths[i] = updated
			emit_changed()
			return

func editor_allocate_next_path_id() -> int:
	var id := maxi(PATH_ID_START, next_path_id)
	next_path_id = id + 1
	emit_changed()
	return id

# ── Camera Poses ──

func editor_add_camera_pose(
	p_name: String,
	p_display_name: String,
	p_pos: Vector3,
	p_euler: Vector3,
	p_fov: float
) -> int:
	var pose := GDCameraPoseSystem.CameraPose.new(p_pos, p_euler, p_fov)
	pose.editor_init_identity(p_name, p_display_name)
	camera_poses.append(pose)
	emit_changed()
	return camera_poses.size() - 1

func editor_remove_camera_pose_at(index: int) -> bool:
	if index < 0 or index >= camera_poses.size():
		return false
	camera_poses.remove_at(index)
	emit_changed()
	return true

func editor_replace_camera_pose_at(index: int, updated: GDCameraPoseSystem.CameraPose) -> bool:
	if updated == null or index < 0 or index >= camera_poses.size():
		return false
	camera_poses[index] = updated
	emit_changed()
	return true

func editor_try_get_camera_pose(index: int) -> Dictionary:
	if index >= 0 and index < camera_poses.size():
		return {"ok": true, "pose": camera_poses[index]}
	return {"ok": false, "pose": null}

# ── Internal helpers ──

func find_archetype_by_stable_id(arch_stable_id: int) -> GDArchetypeRes:
	if arch_stable_id <= 0:
		return null
	for a in archetypes:
		if a != null and a.stable_id == arch_stable_id:
			return a
	return null

func _collect_occupied_instance_ids() -> Dictionary:
	var occ: Dictionary = {}
	for p in placements:
		if p != null and p.instance_id > 0:
			occ[p.instance_id] = true
	return occ

func compose_default_instance_name(archetype: GDArchetypeRes, inst_id: int) -> String:
	var asset_name := ""
	if archetype != null:
		asset_name = archetype.resource_name if not archetype.resource_name.is_empty() else archetype.resource_path.get_file().get_basename()
	return _compose_instance_name_from_asset(asset_name, inst_id)

func _compose_instance_name_from_asset(asset_name: String, inst_id: int) -> String:
	if asset_name.is_empty():
		return "Placement_%d" % inst_id
	var simplified := asset_name
	if simplified.begins_with(ARCHETYPE_ASSET_PREFIX):
		simplified = simplified.substr(ARCHETYPE_ASSET_PREFIX.length())
		var us := simplified.find("_")
		if us > 0 and us + 1 < simplified.length():
			simplified = simplified.substr(us + 1)
	return "%s_%d" % [simplified, inst_id]

static func compose_default_instance_display_name(archetype: GDArchetypeRes, inst_id: int) -> String:
	var disp := archetype.display_name if archetype != null else ""
	var asset := (archetype.resource_name if not archetype.resource_name.is_empty() else archetype.resource_path.get_file().get_basename()) if archetype != null else ""
	return _compose_instance_display_name_raw(disp, asset, inst_id)

static func _compose_instance_display_name_raw(arch_display: String, arch_asset: String, inst_id: int) -> String:
	var raw := arch_display if not arch_display.is_empty() else (arch_asset if not arch_asset.is_empty() else "Placement")
	return "%s #%d" % [raw, inst_id]
