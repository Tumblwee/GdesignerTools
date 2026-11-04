@tool
class_name GDSkillForge
extends RefCounted

## 技能装配工厂（对应 SkillForge / SkillForgeTypes）：
## Clip 注册表（从 GDSkillClips 自动发现）、字段目录、显示名、Spec -> GDSkillRes 装配与反向 Describe、技能查找与保存。

const DEFAULT_MODULE_ROOT := "res://game_res"
## 技能资产落盘位置 = <project_root>/skill/<unique_name>.tres（默认 res://game_res/skill）
const SKILL_SUBDIR := "skill"

const TRACK_KIND_BY_SHORT_NAME := {
	"PlayAnimation": GDSkillTypes.SkillTrackKind.ANIMATION,
	"Teleport": GDSkillTypes.SkillTrackKind.MOVEMENT,
	"CheckHit": GDSkillTypes.SkillTrackKind.HITBOX,
	"SpawnProjectile": GDSkillTypes.SkillTrackKind.HITBOX,
	"DealDamage": GDSkillTypes.SkillTrackKind.EFFECT,
	"ApplyEffect": GDSkillTypes.SkillTrackKind.EFFECT,
	"PlaySfx": GDSkillTypes.SkillTrackKind.AUDIO,
	"CameraEffect": GDSkillTypes.SkillTrackKind.CAMERA,
	"SpawnVfx": GDSkillTypes.SkillTrackKind.VFX,
	"ShowSkillIcon": GDSkillTypes.SkillTrackKind.VFX,
	"VisualMove": GDSkillTypes.SkillTrackKind.MOVEMENT,
	"HitStop": GDSkillTypes.SkillTrackKind.CAMERA,
	"HitFlash": GDSkillTypes.SkillTrackKind.EFFECT,
	"TargetShake": GDSkillTypes.SkillTrackKind.EFFECT,
	"PushEvent": GDSkillTypes.SkillTrackKind.EFFECT,
}

const INSTANT_CLIP_TYPES := ["DealDamage", "ApplyEffect", "PlaySfx", "SpawnProjectile", "Teleport", "PushEvent", "CheckHit", "HitStop"]

const DISPLAY_NAME_BY_SHORT_NAME := {
	"DealDamage": "结算伤害",
	"CheckHit": "命中检测",
	"ApplyEffect": "应用效果",
	"SpawnProjectile": "生成投射物",
	"Teleport": "闪现",
	"PlayAnimation": "播放动画",
	"PlaySfx": "播放音效",
	"SpawnVfx": "生成特效",
	"ShowSkillIcon": "展示技能图标",
	"CameraEffect": "镜头效果",
	"VisualMove": "表现位移",
	"HitStop": "暂停帧",
	"HitFlash": "目标闪白",
	"TargetShake": "目标抖动",
	"PushEvent": "推送事件",
}

## 每种 Clip 可经 Spec / Inspector 编辑的字段：key（Spec 键）、prop（属性名）、kind，可选 enumValues / refType / aliases。
const FIELD_DEFS := {
	"PlayAnimation": [
		{"key": "stateName", "prop": "state_name", "kind": "String", "aliases": []},
		{"key": "crossfadeSeconds", "prop": "crossfade_seconds", "kind": "Float", "aliases": []},
	],
	"PlaySfx": [
		{"key": "clip", "prop": "clip", "kind": "ObjectRef", "refType": "AudioStream", "aliases": []},
		{"key": "volume", "prop": "volume", "kind": "Float", "aliases": []},
	],
	"SpawnVfx": [
		{"key": "vfxPrefab", "prop": "vfx_prefab", "kind": "ObjectRef", "refType": "PackedScene", "aliases": []},
		{"key": "anchor", "prop": "anchor", "kind": "EnumInt", "enumValues": ["CasterRoot", "CasterHand", "TargetRoot"], "aliases": []},
	],
	"ShowSkillIcon": [
		{"key": "displayPrefab", "prop": "display_prefab", "kind": "ObjectRef", "refType": "PackedScene", "aliases": []},
		{"key": "iconOverride", "prop": "icon_override", "kind": "ObjectRef", "refType": "Texture2D", "aliases": []},
		{"key": "headOffsetY", "prop": "head_offset_y", "kind": "Float", "aliases": []},
		{"key": "displaySeconds", "prop": "display_seconds", "kind": "Float", "aliases": ["seconds"]},
	],
	"CameraEffect": [
		{"key": "mode", "prop": "mode", "kind": "EnumInt", "enumValues": ["PushToTarget", "PullFromTarget", "Shake", "FocusTarget"], "aliases": []},
		{"key": "target", "prop": "target", "kind": "EnumInt", "enumValues": ["Target", "Self"], "aliases": []},
		{"key": "zoom01", "prop": "zoom01", "kind": "Float", "aliases": []},
		{"key": "amplitude", "prop": "amplitude", "kind": "Float", "aliases": []},
		{"key": "frequency", "prop": "frequency", "kind": "Float", "aliases": []},
	],
	"VisualMove": [
		{"key": "offset", "prop": "offset", "kind": "Vec3", "aliases": []},
		{"key": "space", "prop": "space", "kind": "EnumInt", "enumValues": ["Local", "CasterForward", "TowardTarget"], "aliases": []},
		{"key": "moveDurationSeconds", "prop": "move_duration_seconds", "kind": "Float", "aliases": ["durationSeconds"]},
		{"key": "returnToOrigin", "prop": "return_to_origin", "kind": "Bool", "aliases": []},
	],
	"HitStop": [
		{"key": "stopFrames", "prop": "stop_frames", "kind": "Int", "aliases": ["frames"]},
		{"key": "referenceFps", "prop": "reference_fps", "kind": "Float", "aliases": ["fps"]},
		{"key": "timeScale", "prop": "time_scale", "kind": "Float", "aliases": []},
		{"key": "exemptCaster", "prop": "exempt_caster", "kind": "Bool", "aliases": []},
		{"key": "exemptTarget", "prop": "exempt_target", "kind": "Bool", "aliases": []},
	],
	"HitFlash": [
		{"key": "color", "prop": "color", "kind": "Color", "aliases": []},
		{"key": "flashSeconds", "prop": "flash_seconds", "kind": "Float", "aliases": ["seconds"]},
	],
	"TargetShake": [
		{"key": "amplitude", "prop": "amplitude", "kind": "Float", "aliases": []},
		{"key": "shakeDurationSeconds", "prop": "shake_duration_seconds", "kind": "Float", "aliases": ["durationSeconds"]},
	],
	"PushEvent": [],
	"SpawnProjectile": [
		{"key": "prefab", "prop": "prefab", "kind": "ObjectRef", "refType": "PackedScene", "aliases": ["projectilePrefab"]},
		{"key": "speed", "prop": "speed", "kind": "Float", "aliases": []},
		{"key": "direction", "prop": "direction", "kind": "EnumInt", "enumValues": ["ToTarget", "CasterForward"], "aliases": []},
		{"key": "reversed", "prop": "reversed", "kind": "Bool", "aliases": []},
		{"key": "landingOffset", "prop": "landing_offset", "kind": "Vec3", "aliases": ["targetOffset"]},
	],
	"DealDamage": [
		{"key": "baseDamage", "prop": "base_damage", "kind": "Int", "aliases": []},
		{"key": "coefficient", "prop": "coefficient", "kind": "Float", "aliases": []},
		{"key": "damageTag", "prop": "damage_tag", "kind": "ObjectRef", "refType": "GameplayTagRes", "aliases": ["damageTagSO"]},
	],
	"CheckHit": [
		{"key": "shape", "prop": "shape", "kind": "EnumInt", "enumValues": ["Sphere", "Box"], "aliases": []},
		{"key": "radiusOrHalfExtent", "prop": "radius_or_half_extent", "kind": "Vec3", "aliases": ["radius"]},
		{"key": "filterTag", "prop": "filter_tag", "kind": "ObjectRef", "refType": "GameplayTagRes", "aliases": ["filterTagSO"]},
	],
	"ApplyEffect": [
		{"key": "effect", "prop": "effect", "kind": "ObjectRef", "refType": "GameplayEffectRes", "aliases": ["effectSO"]},
		{"key": "isInstant", "prop": "is_instant", "kind": "Bool", "aliases": []},
	],
	"Teleport": [
		{"key": "mode", "prop": "mode", "kind": "EnumInt", "enumValues": ["ToTargetSide", "BackToOrigin"], "aliases": []},
		{"key": "offsetFromTarget", "prop": "offset_from_target", "kind": "Float", "aliases": []},
		{"key": "originRecallKey", "prop": "origin_recall_key", "kind": "String", "aliases": ["recallKey"]},
		{"key": "alignToGround", "prop": "align_to_ground", "kind": "Bool", "aliases": []},
	],
}

static var _clip_scripts: Dictionary = {} # short name -> Script（GDSkillClips 中全部具体 Clip，按声明顺序）
static var _in_memory_skills: Dictionary = {} # unique_name -> GDSkillRes

# ── Clip registry ──

## 全部 Clip 类型短名（如 "DealDamage"）。在 GDSkillClips 中新增 XxxClip 即自动出现。
static func clip_types() -> PackedStringArray:
	return PackedStringArray(_clip_registry().keys())

static func is_known_clip_type(short_name: String) -> bool:
	return _clip_registry().has(canonical_clip_short_name(short_name))

static func canonical_clip_short_name(short_name: String) -> String:
	var wanted := short_name.strip_edges().to_lower()
	for k in _clip_registry():
		if k.to_lower() == wanted:
			return k
	return short_name

static func create_clip_instance(short_name: String) -> GDSkillClips.SkillClip:
	var script: GDScript = _clip_registry().get(canonical_clip_short_name(short_name))
	return script.new() if script != null else null

static func get_display_name(short_name: String) -> String:
	return str(DISPLAY_NAME_BY_SHORT_NAME.get(canonical_clip_short_name(short_name), short_name))

static func get_track_kind(short_name: String) -> int:
	return int(TRACK_KIND_BY_SHORT_NAME.get(canonical_clip_short_name(short_name), GDSkillTypes.SkillTrackKind.EFFECT))

## 推荐放在该类轨道上的片段类型（按注册顺序）。
static func clip_types_for_kind(kind: int) -> PackedStringArray:
	var result := PackedStringArray()
	for short_name in clip_types():
		if get_track_kind(short_name) == kind:
			result.append(short_name)
	return result

## 只在起点触发一次、自身时长由其它字段决定的片段，新建时时长为 0。
static func is_instant_clip_type(short_name: String) -> bool:
	return INSTANT_CLIP_TYPES.has(canonical_clip_short_name(short_name))

static func get_field_defs(short_name: String) -> Array[Dictionary]:
	var defs: Array[Dictionary] = []
	defs.assign(FIELD_DEFS.get(canonical_clip_short_name(short_name), []))
	return defs

static func _clip_registry() -> Dictionary:
	if _clip_scripts.is_empty():
		var base: Script = GDSkillClips.SkillClip
		for script in (GDSkillClips as Script).get_script_constant_map().values():
			if script is GDScript and _inherits(script, base):
				_clip_scripts[script.new().get_clip_short_name()] = script
	return _clip_scripts

static func _inherits(script: Script, base: Script) -> bool:
	var s := script.get_base_script()
	while s != null:
		if s == base:
			return true
		s = s.get_base_script()
	return false

# ── Skill registry / lookup / save ──

static func register_in_memory_skill(skill: GDSkillRes) -> void:
	if skill != null:
		unregister_in_memory_skill(skill)
		_in_memory_skills[skill.unique_name] = skill

## 改名或删除后调用：登记键是旧的 unique_name，按对象移除。
static func unregister_in_memory_skill(skill: GDSkillRes) -> void:
	for key in _in_memory_skills.keys():
		if _in_memory_skills[key] == skill:
			_in_memory_skills.erase(key)

## 内存中登记的技能 + root_dir 下全部 Skill_*.tres / .res（按 unique_name 去重，内存优先）。
static func get_all_known_skills(root_dir: String = DEFAULT_MODULE_ROOT) -> Array[GDSkillRes]:
	var result: Array[GDSkillRes] = []
	var seen := {}
	for s: GDSkillRes in _in_memory_skills.values():
		if s != null and not seen.has(s.unique_name):
			seen[s.unique_name] = true
			result.append(s)
	_scan_skills_in_dir(root_dir, seen, result)
	return result

static func find_skill_by_query(query: String, root: String = DEFAULT_MODULE_ROOT) -> GDSkillRes:
	var q := query.strip_edges()
	if _in_memory_skills.has(q):
		return _in_memory_skills[q]
	var parsed := GDSkillTypes.SkillIdentity.try_parse_asset_name(q)
	if not bool(parsed.get("ok", false)):
		parsed = GDSkillTypes.SkillIdentity.try_split_name_and_trailing_id(q)
	if not bool(parsed.get("ok", false)):
		parsed = GDSkillTypes.SkillIdentity.try_split_compact_name(q)
	for so in get_all_known_skills(root):
		if so.unique_name == q or so.skill_name.to_lower() == q.to_lower():
			return so
		if bool(parsed.get("ok", false)) and so.skill_name.to_lower() == str(parsed["name"]).to_lower() and so.skill_id == int(parsed["id"]):
			return so
	return null

static func skill_asset_path(unique_name: String, project_root: String = DEFAULT_MODULE_ROOT) -> String:
	var root := project_root.strip_edges().trim_suffix("/")
	return "%s/%s/%s.tres" % [root if not root.is_empty() else DEFAULT_MODULE_ROOT, SKILL_SUBDIR, unique_name]

## 保存到 <project_root>/skill/<unique_name>.tres，并登记到内存注册表。
static func save_skill(skill: GDSkillRes, project_root: String = DEFAULT_MODULE_ROOT) -> Dictionary:
	var path := skill_asset_path(skill.unique_name, project_root)
	GDCliRoot.AtomCreator.ensure_dir(path.get_base_dir())
	skill.resource_name = skill.unique_name
	var err := ResourceSaver.save(skill, path)
	if err != OK:
		return {"ok": false, "path": path, "error": error_string(err)}
	register_in_memory_skill(skill)
	return {"ok": true, "path": path, "error": ""}

static func _scan_skills_in_dir(dir_path: String, seen: Dictionary, out: Array[GDSkillRes]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname != "." and fname != ".." and not fname.begins_with("."):
			var full := dir_path.path_join(fname)
			if dir.current_is_dir():
				if fname != "GdesignerTools":
					_scan_skills_in_dir(full, seen, out)
			elif (fname.ends_with(".tres") or fname.ends_with(".res")) and fname.begins_with(GDSkillTypes.SkillIdentity.ASSET_PREFIX):
				var sk := ResourceLoader.load(full) as GDSkillRes
				if sk != null and not seen.has(sk.unique_name):
					seen[sk.unique_name] = true
					out.append(sk)
		fname = dir.get_next()
	dir.list_dir_end()

# ── Spec -> GDSkillRes ──

## 校验并装配 Spec；dry_run=false 时经 save_skill 落盘。
## 返回 {ok, dry_run, skill_so_path, group_names, skill} 或 {ok=false, error_code, error_message}。
static func build_from_spec(spec_dict: Dictionary, dry_run: bool = false, project_root: String = DEFAULT_MODULE_ROOT) -> Dictionary:
	if spec_dict.is_empty():
		return _spec_error("spec-parse-failed", "spec 为空")

	var raw_name := str(spec_dict.get("name", ""))
	var raw_id := int(spec_dict.get("id", 0))
	var norm := GDSkillTypes.SkillIdentity.try_normalize(raw_name, raw_id)
	if not bool(norm.get("ok", false)):
		return _spec_error("invalid-name", "name/id 非法：name=%s, id=%d" % [raw_name, raw_id])

	var groups_raw: Array = spec_dict.get("groups", [])
	var clips_raw: Array = spec_dict.get("clips", [])
	if groups_raw.is_empty():
		return _spec_error("spec-parse-failed", "groups 不能为空")
	if clips_raw.is_empty():
		return _spec_error("spec-parse-failed", "clips 不能为空")

	var group_names: Array[String] = []
	for g in groups_raw:
		if not (g is Dictionary):
			return _spec_error("spec-parse-failed", "group 格式错误")
		var gn := str(g.get("name", "")).strip_edges()
		if gn.is_empty():
			return _spec_error("spec-parse-failed", "group 缺少 name")
		if group_names.has(gn):
			return _spec_error("spec-parse-failed", "group name 重复：%s" % gn)
		group_names.append(gn)

	var clip_ids := {}
	for c in clips_raw:
		if not (c is Dictionary):
			return _spec_error("spec-parse-failed", "clip 格式错误")
		var cid := str(c.get("id", "")).strip_edges()
		if cid.is_empty():
			return _spec_error("spec-parse-failed", "clip 缺少 id")
		if clip_ids.has(cid):
			return _spec_error("spec-parse-failed", "clip id 重复：%s" % cid)
		clip_ids[cid] = true
		var ctype := str(c.get("type", "")).strip_edges()
		if not is_known_clip_type(ctype):
			return _spec_error("unknown-clip-type", "未知 clip 类型：%s（clip id=%s）" % [ctype, cid])
		var cgrp := str(c.get("group", "")).strip_edges()
		if not group_names.has(cgrp):
			return _spec_error("clip-group-not-found", "clip「%s」引用了不存在的 group：%s" % [cid, cgrp])

	var s_name := str(norm["name"])
	var s_id := int(norm["id"])
	var so_path := skill_asset_path(GDSkillTypes.SkillIdentity.to_asset_name(s_name, s_id), project_root)
	if dry_run:
		return {"ok": true, "dry_run": true, "skill_so_path": so_path, "group_names": group_names, "skill": null}

	var so := GDSkillRes.new()
	var disp := str(spec_dict.get("display", "")).strip_edges()
	so.configure_header(s_name, s_id, disp if not disp.is_empty() else s_name, str(spec_dict.get("description", "")))
	var cost: Variant = spec_dict.get("cost")
	if cost is Dictionary:
		so.set_cost(str(cost.get("attributeName", "Mana")), float(cost.get("amount", 0.0)))
	var cooldown: Variant = spec_dict.get("cooldown")
	if cooldown is Dictionary:
		so.set_cooldown(str(cooldown.get("cdGroup", "Default")), float(cooldown.get("durationSeconds", 0.0)))

	var group_by_name := {}
	for g in groups_raw:
		var grp := GDSkillRes.SkillTrackGroup.new(str(g.get("name", "")).strip_edges())
		var tracks: Variant = g.get("tracks", [])
		for tr in (tracks if tracks is Array else []):
			if tr is Dictionary:
				grp.add_track(GDSkillRes.SkillTrack.new(GDSkillTypes.parse_track_kind(str(tr.get("kind", "Effect"))), str(tr.get("name", "")).strip_edges()))
		group_by_name[grp.group_name] = grp
		so.add_group(grp)

	var max_end_ms := 0
	for c in clips_raw:
		var clip := build_clip_from_dict(c)
		if clip == null:
			return _spec_error("clip-build-failed", "构建 clip 失败")
		var grp: GDSkillRes.SkillTrackGroup = group_by_name[str(c.get("group", "")).strip_edges()]
		var kind := get_track_kind(str(c.get("type", "")).strip_edges())
		_resolve_or_add_track(grp, str(c.get("track", "")).strip_edges(), kind).add_clip(clip)
		max_end_ms = maxi(max_end_ms, clip.start_ms + maxi(0, clip.duration_ms))
	so.set_duration(maxi(int(spec_dict.get("durationMs", 0)), max_end_ms))

	var saved := save_skill(so, project_root)
	if not bool(saved["ok"]):
		return _spec_error("save-failed", "保存失败：%s（%s）" % [saved["path"], saved["error"]])
	return {"ok": true, "dry_run": false, "skill_so_path": so_path, "group_names": group_names, "skill": so}

static func _spec_error(code: String, message: String) -> Dictionary:
	return {"ok": false, "error_code": code, "error_message": message}

## 指定名称时按名找轨道，否则按种类找；找不到就新建。
static func _resolve_or_add_track(group: GDSkillRes.SkillTrackGroup, wanted_name: String, kind: int) -> GDSkillRes.SkillTrack:
	for t in group.tracks:
		if t != null and (t.track_name == wanted_name if not wanted_name.is_empty() else t.kind == kind):
			return t
	var trk := GDSkillRes.SkillTrack.new(kind, wanted_name)
	group.add_track(trk)
	return trk

## Spec 中单个 clip 字典 -> Clip 实例（未知类型返回 null）。
static func build_clip_from_dict(cd: Dictionary) -> GDSkillClips.SkillClip:
	var ctype := str(cd.get("type", "")).strip_edges()
	var clip := create_clip_instance(ctype)
	if clip == null:
		return null
	clip.set_timing(int(cd.get("startMs", 0)), int(cd.get("durationMs", 0)))
	var disp := str(cd.get("displayName", "")).strip_edges()
	clip.set_display_name(disp if not disp.is_empty() else get_display_name(ctype))

	var fields: Dictionary = cd.get("fields") if cd.get("fields") is Dictionary else {}
	var defs := get_field_defs(ctype)
	for fkey in fields:
		var def := _find_field_def(defs, str(fkey))
		if not def.is_empty():
			_write_clip_field(clip, def, fields[fkey])

	var projectile := clip as GDSkillClips.SpawnProjectileClip
	if projectile != null and fields.get("trajectory") is Dictionary:
		projectile.configure_trajectory(_build_trajectory(fields["trajectory"]), projectile.reversed)
	var push := clip as GDSkillClips.PushEventClip
	if push != null and fields.get("events") is Array:
		var events: Array[GDSkillClips.SkillCustomEvent] = []
		for ed in fields["events"]:
			if ed is Dictionary:
				var ce := GDSkillClips.SkillCustomEvent.new()
				ce.configure(str(ed.get("eventId", "")), float(ed.get("floatParam", 0.0)), str(ed.get("stringParam", "")), _to_vec3(ed.get("vectorParam", [0, 0, 0])))
				events.append(ce)
		push.configure(events)
	return clip

static func _find_field_def(defs: Array[Dictionary], key: String) -> Dictionary:
	var wanted := key.to_lower()
	for def in defs:
		if str(def["key"]).to_lower() == wanted or def.get("aliases", []).any(func(al: Variant) -> bool: return str(al).to_lower() == wanted):
			return def
	return {}

static func _build_trajectory(td: Dictionary) -> GDSkillClips.SkillProjectileTrajectory:
	match str(td.get("type", "Linear")).to_lower():
		"parabola":
			var pt := GDSkillClips.ParabolaTrajectory.new()
			pt.configure(float(td.get("archHeight", 2.0)))
			return pt
		"homing":
			var ht := GDSkillClips.HomingTrajectory.new()
			ht.configure(float(td.get("homingStrength", 0.5)))
			return ht
		"bezier":
			var bt := GDSkillClips.BezierTrajectory.new()
			bt.configure(_to_vec3(td.get("controlOffset", [0, 2, 0])))
			return bt
		_:
			return GDSkillClips.LinearTrajectory.new()

static func _write_clip_field(clip: GDSkillClips.SkillClip, def: Dictionary, raw: Variant) -> void:
	var prop := str(def["prop"])
	match str(def["kind"]):
		"String":
			clip.set(prop, str(raw) if raw != null else "")
		"Float":
			clip.set(prop, float(raw) if raw != null else 0.0)
		"Int":
			clip.set(prop, int(raw) if raw != null else 0)
		"Bool":
			clip.set(prop, bool(raw) if raw != null else false)
		"EnumInt":
			var s := str(raw).strip_edges()
			if raw is int or s.is_valid_int():
				clip.set(prop, s.to_int())
			else:
				var names: Array = def.get("enumValues", []).map(func(v: Variant) -> String: return str(v).to_lower())
				if names.has(s.to_lower()):
					clip.set(prop, names.find(s.to_lower()))
		"Vec3":
			clip.set(prop, _to_vec3(raw))
		"Color":
			clip.set(prop, _to_color(raw))
		"ObjectRef":
			if raw is Resource:
				clip.set(prop, raw)
			elif raw is String and not raw.is_empty() and ResourceLoader.exists(raw):
				clip.set(prop, ResourceLoader.load(raw))

static func _to_vec3(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	if raw is float or raw is int:
		return Vector3.ONE * float(raw)
	return Vector3.ONE

static func _to_color(raw: Variant) -> Color:
	if raw is Color:
		return raw
	if raw is Array and raw.size() >= 3:
		return Color(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]) if raw.size() >= 4 else 1.0)
	return Color.WHITE

# ── GDSkillRes -> Spec（skill.describe）──

## 反向导出 Spec（可再喂给 build_from_spec），供 CLI describe 与外部工具使用；与持久化无关。
static func describe_skill_to_spec_dict(so: GDSkillRes) -> Dictionary:
	var groups_json: Array = []
	var clips_json: Array = []
	for grp in so.groups:
		if grp == null:
			continue
		var tracks_json: Array = []
		for trk in grp.tracks:
			if trk == null:
				continue
			tracks_json.append({"name": trk.track_name, "kind": GDSkillTypes.track_kind_name(trk.kind)})
			for clip in trk.clips:
				if clip == null:
					continue
				var sname: String = clip.get_clip_short_name()
				clips_json.append({
					"id": "%s%d" % [sname, clips_json.size()],
					"type": sname,
					"group": grp.group_name,
					"track": trk.track_name,
					"startMs": clip.start_ms,
					"durationMs": clip.duration_ms,
					"displayName": clip.display_name,
					"fields": read_clip_fields(clip),
				})
		groups_json.append({"name": grp.group_name, "tracks": tracks_json})

	return {
		"name": so.skill_name,
		"id": so.skill_id,
		"display": so.display_name,
		"description": so.description,
		"durationMs": so.duration_ms,
		"cost": {"attributeName": so.cost.attribute_name, "amount": so.cost.amount},
		"cooldown": {"cdGroup": so.cooldown.cd_group, "durationSeconds": so.cooldown.duration_seconds},
		"requiredTags": [],
		"blockedTags": [],
		"groups": groups_json,
		"clips": clips_json,
	}

static func read_clip_fields(clip: GDSkillClips.SkillClip) -> Dictionary:
	var result := {}
	for def in get_field_defs(clip.get_clip_short_name()):
		var val: Variant = clip.get(str(def["prop"]))
		var key := str(def["key"])
		match str(def["kind"]):
			"String":
				result[key] = str(val)
			"Float":
				result[key] = float(val)
			"Int":
				result[key] = int(val)
			"Bool":
				result[key] = bool(val)
			"EnumInt":
				var evs: Array = def.get("enumValues", [])
				var idx := int(val)
				result[key] = evs[idx] if idx >= 0 and idx < evs.size() else str(idx)
			"Vec3":
				var v: Vector3 = val if val is Vector3 else Vector3.ZERO
				result[key] = [v.x, v.y, v.z]
			"Color":
				var col: Color = val if val is Color else Color.WHITE
				result[key] = [col.r, col.g, col.b, col.a]
			"ObjectRef":
				result[key] = _ref_label(val)

	var projectile := clip as GDSkillClips.SpawnProjectileClip
	var push := clip as GDSkillClips.PushEventClip
	if projectile != null and projectile.trajectory != null:
		result["trajectory"] = _read_trajectory(projectile.trajectory)
	elif push != null and not push.events.is_empty():
		var events: Array = []
		for e in push.events:
			if e != null:
				events.append({
					"eventId": e.event_id,
					"floatParam": e.float_param,
					"stringParam": e.string_param,
					"vectorParam": [e.vector_param.x, e.vector_param.y, e.vector_param.z],
				})
		result["events"] = events
	return result

static func _ref_label(val: Variant) -> String:
	if not (val is Resource):
		return ""
	return val.resource_path if not val.resource_path.is_empty() else val.resource_name

static func _read_trajectory(traj: Variant) -> Dictionary:
	if traj is GDSkillClips.ParabolaTrajectory:
		return {"type": "Parabola", "archHeight": traj.arch_height}
	if traj is GDSkillClips.HomingTrajectory:
		return {"type": "Homing", "homingStrength": traj.homing_strength}
	if traj is GDSkillClips.BezierTrajectory:
		var offset: Vector3 = traj.control_offset
		return {"type": "Bezier", "controlOffset": [offset.x, offset.y, offset.z]}
	return {"type": "Linear"}
