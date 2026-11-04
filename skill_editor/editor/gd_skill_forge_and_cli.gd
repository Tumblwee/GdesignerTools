@tool
class_name GDSkillForgeAndCli
extends RefCounted

## 技能装配工厂层（SkillForge）与 CLI 主入口（SkillCli）
## 对应 SkillForge / SkillForgeTypes / SkillCli
## 支持 15 种 Clip 的确定性 Spec -> 单资产 GDSkillRes 装配、字段目录查询、反向 Describe、Validate、Effect 创建与 Preview。

const DEFAULT_MODULE_ROOT := "res://addons/gdesigner_tools/skill_editor"

const ALL_CLIP_TYPES := [
	"DealDamage",
	"CheckHit",
	"ApplyEffect",
	"SpawnProjectile",
	"Teleport",
	"PlayAnimation",
	"PlaySfx",
	"SpawnVfx",
	"ShowSkillIcon",
	"CameraEffect",
	"VisualMove",
	"HitStop",
	"HitFlash",
	"TargetShake",
	"PushEvent",
]

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

static var _in_memory_skills: Dictionary = {} # unique_name -> GDSkillRes

static func register_in_memory_skill(skill: GDSkillRes) -> void:
	if skill != null:
		_in_memory_skills[skill.unique_name] = skill

static func get_all_known_skills(root_dir: String = "res://") -> Array[GDSkillRes]:
	var result: Array[GDSkillRes] = []
	var seen: Dictionary = {}
	for k in _in_memory_skills.keys():
		var s: GDSkillRes = _in_memory_skills[k]
		if s != null:
			result.append(s)
			seen[s.unique_name] = true
	_scan_skills_in_dir(root_dir, seen, result)
	return result

static func _scan_skills_in_dir(dir_path: String, seen: Dictionary, out: Array[GDSkillRes]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname != "." and fname != ".." and not fname.begins_with("."):
			var full := dir_path.path_join(fname) if dir_path != "res://" else "res://" + fname
			if dir.current_is_dir():
				if fname != "GdesignerTools":
					_scan_skills_in_dir(full, seen, out)
			elif (fname.ends_with(".tres") or fname.ends_with(".res")) and fname.begins_with("Skill_"):
				var loaded := ResourceLoader.load(full)
				if loaded is GDSkillRes:
					var sk := loaded as GDSkillRes
					hydrate_skill_if_needed(sk)
					if not seen.has(sk.unique_name):
						seen[sk.unique_name] = true
						out.append(sk)
		fname = dir.get_next()
	dir.list_dir_end()

static func is_known_clip_type(short_name: String) -> bool:
	for k in ALL_CLIP_TYPES:
		if k.to_lower() == short_name.strip_edges().to_lower():
			return true
	return false

static func canonical_clip_short_name(short_name: String) -> String:
	for k in ALL_CLIP_TYPES:
		if k.to_lower() == short_name.strip_edges().to_lower():
			return k
	return short_name

static func get_display_name(short_name: String) -> String:
	var c := canonical_clip_short_name(short_name)
	return str(DISPLAY_NAME_BY_SHORT_NAME.get(c, short_name))

static func get_track_kind(short_name: String) -> int:
	var c := canonical_clip_short_name(short_name)
	return int(TRACK_KIND_BY_SHORT_NAME.get(c, GDSkillTypes.SkillTrackKind.EFFECT))

static func create_clip_instance(short_name: String) -> GDSkillClips.SkillClip:
	var c := canonical_clip_short_name(short_name)
	match c:
		"DealDamage": return GDSkillClips.DealDamageClip.new()
		"CheckHit": return GDSkillClips.CheckHitClip.new()
		"ApplyEffect": return GDSkillClips.ApplyEffectClip.new()
		"SpawnProjectile": return GDSkillClips.SpawnProjectileClip.new()
		"Teleport": return GDSkillClips.TeleportClip.new()
		"PlayAnimation": return GDSkillClips.PlayAnimationClip.new()
		"PlaySfx": return GDSkillClips.PlaySfxClip.new()
		"SpawnVfx": return GDSkillClips.SpawnVfxClip.new()
		"ShowSkillIcon": return GDSkillClips.ShowSkillIconClip.new()
		"CameraEffect": return GDSkillClips.CameraEffectClip.new()
		"VisualMove": return GDSkillClips.VisualMoveClip.new()
		"HitStop": return GDSkillClips.HitStopClip.new()
		"HitFlash": return GDSkillClips.HitFlashClip.new()
		"TargetShake": return GDSkillClips.TargetShakeClip.new()
		"PushEvent": return GDSkillClips.PushEventClip.new()
		_: return null

static func get_field_defs(short_name: String) -> Array[Dictionary]:
	var c := canonical_clip_short_name(short_name)
	match c:
		"PlayAnimation":
			return [
				{"key": "stateName", "prop": "state_name", "kind": "String", "aliases": []},
				{"key": "crossfadeSeconds", "prop": "crossfade_seconds", "kind": "Float", "aliases": []},
			]
		"PlaySfx":
			return [
				{"key": "clip", "prop": "clip", "kind": "ObjectRef", "refType": "AudioStream", "aliases": []},
				{"key": "volume", "prop": "volume", "kind": "Float", "aliases": []},
			]
		"SpawnVfx":
			return [
				{"key": "vfxPrefab", "prop": "vfx_prefab", "kind": "ObjectRef", "refType": "PackedScene", "aliases": []},
				{"key": "anchor", "prop": "anchor", "kind": "EnumInt", "enumValues": ["CasterRoot", "CasterHand", "TargetRoot"], "aliases": []},
			]
		"ShowSkillIcon":
			return [
				{"key": "displayPrefab", "prop": "display_prefab", "kind": "ObjectRef", "refType": "PackedScene", "aliases": []},
				{"key": "iconOverride", "prop": "icon_override", "kind": "ObjectRef", "refType": "Texture2D", "aliases": []},
				{"key": "headOffsetY", "prop": "head_offset_y", "kind": "Float", "aliases": []},
				{"key": "displaySeconds", "prop": "display_seconds", "kind": "Float", "aliases": ["seconds"]},
			]
		"CameraEffect":
			return [
				{"key": "mode", "prop": "mode", "kind": "EnumInt", "enumValues": ["PushToTarget", "PullFromTarget", "Shake", "FocusTarget"], "aliases": []},
				{"key": "target", "prop": "target", "kind": "EnumInt", "enumValues": ["Target", "Self"], "aliases": []},
				{"key": "zoom01", "prop": "zoom01", "kind": "Float", "aliases": []},
				{"key": "amplitude", "prop": "amplitude", "kind": "Float", "aliases": []},
				{"key": "frequency", "prop": "frequency", "kind": "Float", "aliases": []},
			]
		"VisualMove":
			return [
				{"key": "offset", "prop": "offset", "kind": "Vec3", "aliases": []},
				{"key": "space", "prop": "space", "kind": "EnumInt", "enumValues": ["Local", "CasterForward", "TowardTarget"], "aliases": []},
				{"key": "moveDurationSeconds", "prop": "move_duration_seconds", "kind": "Float", "aliases": ["durationSeconds"]},
				{"key": "returnToOrigin", "prop": "return_to_origin", "kind": "Bool", "aliases": []},
			]
		"HitStop":
			return [
				{"key": "stopFrames", "prop": "stop_frames", "kind": "Int", "aliases": ["frames"]},
				{"key": "referenceFps", "prop": "reference_fps", "kind": "Float", "aliases": ["fps"]},
				{"key": "timeScale", "prop": "time_scale", "kind": "Float", "aliases": []},
				{"key": "exemptCaster", "prop": "exempt_caster", "kind": "Bool", "aliases": []},
				{"key": "exemptTarget", "prop": "exempt_target", "kind": "Bool", "aliases": []},
			]
		"HitFlash":
			return [
				{"key": "color", "prop": "color", "kind": "Color", "aliases": []},
				{"key": "flashSeconds", "prop": "flash_seconds", "kind": "Float", "aliases": ["seconds"]},
			]
		"TargetShake":
			return [
				{"key": "amplitude", "prop": "amplitude", "kind": "Float", "aliases": []},
				{"key": "shakeDurationSeconds", "prop": "shake_duration_seconds", "kind": "Float", "aliases": ["durationSeconds"]},
			]
		"PushEvent":
			return []
		"SpawnProjectile":
			return [
				{"key": "prefab", "prop": "prefab", "kind": "ObjectRef", "refType": "PackedScene", "aliases": ["projectilePrefab"]},
				{"key": "speed", "prop": "speed", "kind": "Float", "aliases": []},
				{"key": "direction", "prop": "direction", "kind": "EnumInt", "enumValues": ["ToTarget", "CasterForward"], "aliases": []},
				{"key": "reversed", "prop": "reversed", "kind": "Bool", "aliases": []},
				{"key": "landingOffset", "prop": "landing_offset", "kind": "Vec3", "aliases": ["targetOffset"]},
			]
		"DealDamage":
			return [
				{"key": "baseDamage", "prop": "base_damage", "kind": "Int", "aliases": []},
				{"key": "coefficient", "prop": "coefficient", "kind": "Float", "aliases": []},
				{"key": "damageTag", "prop": "damage_tag", "kind": "ObjectRef", "refType": "GameplayTagRes", "aliases": ["damageTagSO"]},
			]
		"CheckHit":
			return [
				{"key": "shape", "prop": "shape", "kind": "EnumInt", "enumValues": ["Sphere", "Box"], "aliases": []},
				{"key": "radiusOrHalfExtent", "prop": "radius_or_half_extent", "kind": "Vec3", "aliases": ["radius"]},
				{"key": "filterTag", "prop": "filter_tag", "kind": "ObjectRef", "refType": "GameplayTagRes", "aliases": ["filterTagSO"]},
			]
		"ApplyEffect":
			return [
				{"key": "effect", "prop": "effect", "kind": "ObjectRef", "refType": "GameplayEffectRes", "aliases": ["effectSO"]},
				{"key": "isInstant", "prop": "is_instant", "kind": "Bool", "aliases": []},
			]
		"Teleport":
			return [
				{"key": "mode", "prop": "mode", "kind": "EnumInt", "enumValues": ["ToTargetSide", "BackToOrigin"], "aliases": []},
				{"key": "offsetFromTarget", "prop": "offset_from_target", "kind": "Float", "aliases": []},
				{"key": "originRecallKey", "prop": "origin_recall_key", "kind": "String", "aliases": ["recallKey"]},
				{"key": "alignToGround", "prop": "align_to_ground", "kind": "Bool", "aliases": []},
			]
		_:
			return []

static func read_clip_fields(clip: GDSkillClips.SkillClip) -> Dictionary:
	var result: Dictionary = {}
	if clip == null:
		return result
	var short_name := clip.get_clip_short_name()
	var defs := get_field_defs(short_name)
	for def in defs:
		var prop := str(def["prop"])
		var key := str(def["key"])
		var kind := str(def["kind"])
		var val = clip.get(prop)
		match kind:
			"String":
				result[key] = str(val) if val != null else ""
			"Float":
				result[key] = float(val) if val != null else 0.0
			"Int":
				result[key] = int(val) if val != null else 0
			"Bool":
				result[key] = bool(val) if val != null else false
			"EnumInt":
				var evs: Array = def.get("enumValues", [])
				var idx := int(val) if val != null else 0
				result[key] = evs[idx] if (idx >= 0 and idx < evs.size()) else str(idx)
			"Vec3":
				var v: Vector3 = val if val is Vector3 else Vector3.ZERO
				result[key] = [v.x, v.y, v.z]
			"Color":
				var col: Color = val if val is Color else Color.WHITE
				result[key] = [col.r, col.g, col.b, col.a]
			"ObjectRef":
				if val is Resource and not (val as Resource).resource_path.is_empty():
					result[key] = (val as Resource).resource_path
				elif val is Resource and not (val as Resource).resource_name.is_empty():
					result[key] = (val as Resource).resource_name
				else:
					result[key] = ""

	if clip is GDSkillClips.SpawnProjectileClip:
		var sp := clip as GDSkillClips.SpawnProjectileClip
		if sp.trajectory != null:
			result["trajectory"] = _read_trajectory(sp.trajectory)
	elif clip is GDSkillClips.PushEventClip:
		var pe := clip as GDSkillClips.PushEventClip
		if pe.events != null and not pe.events.is_empty():
			var ev_list: Array = []
			for e in pe.events:
				if e != null:
					ev_list.append({
						"eventId": e.event_id,
						"floatParam": e.float_param,
						"stringParam": e.string_param,
						"vectorParam": [e.vector_param.x, e.vector_param.y, e.vector_param.z],
					})
			result["events"] = ev_list
	return result

static func _read_trajectory(traj: GDSkillClips.SkillProjectileTrajectory) -> Dictionary:
	if traj is GDSkillClips.ParabolaTrajectory:
		return {"type": "Parabola", "archHeight": (traj as GDSkillClips.ParabolaTrajectory).arch_height}
	if traj is GDSkillClips.HomingTrajectory:
		return {"type": "Homing", "homingStrength": (traj as GDSkillClips.HomingTrajectory).homing_strength}
	if traj is GDSkillClips.BezierTrajectory:
		var co := (traj as GDSkillClips.BezierTrajectory).control_offset
		return {"type": "Bezier", "controlOffset": [co.x, co.y, co.z]}
	return {"type": "Linear"}

static func build_from_spec(spec_dict: Dictionary, dry_run: bool = false, project_root: String = DEFAULT_MODULE_ROOT) -> Dictionary:
	if spec_dict == null or spec_dict.is_empty():
		return {"ok": false, "error_code": "spec-parse-failed", "error_message": "spec 为空"}

	var raw_name := str(spec_dict.get("name", ""))
	var raw_id := int(spec_dict.get("id", 0))
	var norm := GDSkillTypes.SkillIdentity.try_normalize(raw_name, raw_id)
	if not bool(norm.get("ok", false)):
		return {"ok": false, "error_code": "invalid-name", "error_message": "name/id 非法：name=%s, id=%d" % [raw_name, raw_id]}

	var s_name := str(norm["name"])
	var s_id := int(norm["id"])
	var groups_raw: Array = spec_dict.get("groups", [])
	var clips_raw: Array = spec_dict.get("clips", [])
	if groups_raw.is_empty():
		return {"ok": false, "error_code": "spec-parse-failed", "error_message": "groups 不能为空"}
	if clips_raw.is_empty():
		return {"ok": false, "error_code": "spec-parse-failed", "error_message": "clips 不能为空"}

	var group_names: Dictionary = {}
	for g in groups_raw:
		if not (g is Dictionary):
			return {"ok": false, "error_code": "spec-parse-failed", "error_message": "group 格式错误"}
		var gn := str((g as Dictionary).get("name", "")).strip_edges()
		if gn.is_empty():
			return {"ok": false, "error_code": "spec-parse-failed", "error_message": "group 缺少 name"}
		if group_names.has(gn):
			return {"ok": false, "error_code": "spec-parse-failed", "error_message": "group name 重复：%s" % gn}
		group_names[gn] = true

	var clip_ids: Dictionary = {}
	for c in clips_raw:
		if not (c is Dictionary):
			return {"ok": false, "error_code": "spec-parse-failed", "error_message": "clip 格式错误"}
		var cd := c as Dictionary
		var cid := str(cd.get("id", "")).strip_edges()
		if cid.is_empty():
			return {"ok": false, "error_code": "spec-parse-failed", "error_message": "clip 缺少 id"}
		if clip_ids.has(cid):
			return {"ok": false, "error_code": "spec-parse-failed", "error_message": "clip id 重复：%s" % cid}
		clip_ids[cid] = true
		var ctype := str(cd.get("type", "")).strip_edges()
		if not is_known_clip_type(ctype):
			return {"ok": false, "error_code": "unknown-clip-type", "error_message": "未知 clip 类型：%s（clip id=%s）" % [ctype, cid]}
		var cgrp := str(cd.get("group", "")).strip_edges()
		if not group_names.has(cgrp):
			return {"ok": false, "error_code": "clip-group-not-found", "error_message": "clip「%s」引用了不存在的 group：%s" % [cid, cgrp]}

	var canonical_id := GDSkillTypes.SkillIdentity.to_asset_name(s_name, s_id)
	var root := project_root.trim_suffix("/") if not project_root.strip_edges().is_empty() else DEFAULT_MODULE_ROOT
	var so_path := "%s/GameRes/Skill/%s.tres" % [root, canonical_id]

	var out_group_names: Array[String] = []
	for g in groups_raw:
		out_group_names.append(str((g as Dictionary).get("name", "")).strip_edges())

	if dry_run:
		return {
			"ok": true,
			"dry_run": true,
			"skill_so_path": so_path,
			"group_names": out_group_names,
			"skill": null,
		}

	var so := GDSkillRes.new()
	so.resource_name = canonical_id
	var disp := str(spec_dict.get("display", "")).strip_edges()
	so.configure_header(s_name, s_id, disp if not disp.is_empty() else s_name, str(spec_dict.get("description", "")))

	if spec_dict.get("cost") is Dictionary:
		var cost_d := spec_dict["cost"] as Dictionary
		so.set_cost(str(cost_d.get("attributeName", "Mana")), float(cost_d.get("amount", 0.0)))
	if spec_dict.get("cooldown") is Dictionary:
		var cd_d := spec_dict["cooldown"] as Dictionary
		so.set_cooldown(str(cd_d.get("cdGroup", "Default")), float(cd_d.get("durationSeconds", 0.0)))

	so.clear_groups()
	var group_by_name: Dictionary = {}
	for g in groups_raw:
		var gd := g as Dictionary
		var gn := str(gd.get("name", "")).strip_edges()
		var grp := GDSkillRes.SkillTrackGroup.new(gn)
		if gd.get("tracks") is Array:
			for tr in gd["tracks"]:
				if tr is Dictionary:
					var tr_d := tr as Dictionary
					var k := GDSkillTypes.parse_track_kind(str(tr_d.get("kind", "Effect")))
					var tn := str(tr_d.get("name", "")).strip_edges()
					grp.add_track(GDSkillRes.SkillTrack.new(k, tn))
		group_by_name[gn] = grp
		so.add_group(grp)

	var max_end_ms := 0
	for c in clips_raw:
		var cd := c as Dictionary
		var ctype := str(cd.get("type", "")).strip_edges()
		var cgrp := str(cd.get("group", "")).strip_edges()
		var grp: GDSkillRes.SkillTrackGroup = group_by_name[cgrp]
		var clip := _build_clip_from_dict(cd)
		if clip == null:
			return {"ok": false, "error_code": "clip-build-failed", "error_message": "构建 clip 失败"}
		var kind := get_track_kind(ctype)
		var wanted_track := str(cd.get("track", "")).strip_edges()
		var track := _resolve_or_add_track(grp, wanted_track, kind)
		track.add_clip(clip)
		max_end_ms = maxi(max_end_ms, clip.start_ms + maxi(0, clip.duration_ms))

	var spec_dur := int(spec_dict.get("durationMs", 0))
	so.set_duration(maxi(spec_dur, max_end_ms))
	so.serialized_spec = describe_skill_to_spec_dict(so)

	GDCliRoot.AtomCreator.ensure_dir("%s/GameRes/Skill" % root)
	ResourceSaver.save(so, so_path)
	register_in_memory_skill(so)

	return {
		"ok": true,
		"dry_run": false,
		"skill_so_path": so_path,
		"group_names": out_group_names,
		"skill": so,
	}

static func hydrate_skill_if_needed(so: GDSkillRes) -> void:
	if so == null:
		return
	var needs_hydrate := so.groups.is_empty()
	if not needs_hydrate:
		for g in so.groups:
			if g == null or not (g is GDSkillRes.SkillTrackGroup):
				needs_hydrate = true
				break
	if not needs_hydrate or so.serialized_spec == null or so.serialized_spec.is_empty():
		return
	var spec := so.serialized_spec
	if spec.get("cost") is Dictionary:
		var cost_d := spec["cost"] as Dictionary
		so.set_cost(str(cost_d.get("attributeName", "Mana")), float(cost_d.get("amount", 0.0)))
	if spec.get("cooldown") is Dictionary:
		var cd_d := spec["cooldown"] as Dictionary
		so.set_cooldown(str(cd_d.get("cdGroup", "Default")), float(cd_d.get("durationSeconds", 0.0)))
	so.clear_groups()
	var group_by_name: Dictionary = {}
	var groups_raw: Array = spec.get("groups", [])
	for g in groups_raw:
		if not (g is Dictionary):
			continue
		var gd := g as Dictionary
		var gn := str(gd.get("name", "")).strip_edges()
		var grp := GDSkillRes.SkillTrackGroup.new(gn)
		if gd.get("tracks") is Array:
			for tr in gd["tracks"]:
				if tr is Dictionary:
					var tr_d := tr as Dictionary
					grp.add_track(GDSkillRes.SkillTrack.new(GDSkillTypes.parse_track_kind(str(tr_d.get("kind", "Effect"))), str(tr_d.get("name", "")).strip_edges()))
		group_by_name[gn] = grp
		so.add_group(grp)
	var clips_raw: Array = spec.get("clips", [])
	for c in clips_raw:
		if not (c is Dictionary):
			continue
		var cd := c as Dictionary
		var ctype := str(cd.get("type", "")).strip_edges()
		var cgrp := str(cd.get("group", "")).strip_edges()
		if not group_by_name.has(cgrp):
			continue
		var grp: GDSkillRes.SkillTrackGroup = group_by_name[cgrp]
		var clip := _build_clip_from_dict(cd)
		if clip != null:
			var trk := _resolve_or_add_track(grp, str(cd.get("track", "")).strip_edges(), get_track_kind(ctype))
			trk.add_clip(clip)

static func _resolve_or_add_track(group: GDSkillRes.SkillTrackGroup, wanted_name: String, kind: int) -> GDSkillRes.SkillTrack:
	if not wanted_name.is_empty():
		for t in group.tracks:
			if t != null and t.track_name == wanted_name:
				return t
		var named := GDSkillRes.SkillTrack.new(kind, wanted_name)
		group.add_track(named)
		return named
	for t in group.tracks:
		if t != null and t.kind == kind:
			return t
	var trk := GDSkillRes.SkillTrack.new(kind)
	group.add_track(trk)
	return trk

static func _build_clip_from_dict(cd: Dictionary) -> GDSkillClips.SkillClip:
	var ctype := str(cd.get("type", "")).strip_edges()
	var clip := create_clip_instance(ctype)
	if clip == null:
		return null
	var s_ms := int(cd.get("startMs", 0))
	var d_ms := int(cd.get("durationMs", 0))
	var disp := str(cd.get("displayName", "")).strip_edges()
	clip.set_timing(s_ms, d_ms)
	clip.set_display_name(disp if not disp.is_empty() else get_display_name(ctype))

	var fields: Dictionary = cd.get("fields", {}) if cd.get("fields") is Dictionary else {}
	var defs := get_field_defs(ctype)
	for fkey in fields.keys():
		if fkey == "trajectory" or fkey == "events":
			continue
		var fval = fields[fkey]
		for def in defs:
			var match_key := str(def["key"]).to_lower() == str(fkey).to_lower()
			if not match_key:
				for al in def.get("aliases", []):
					if str(al).to_lower() == str(fkey).to_lower():
						match_key = true
						break
			if match_key:
				_write_clip_field(clip, def, fval)
				break

	if clip is GDSkillClips.SpawnProjectileClip and fields.get("trajectory") is Dictionary:
		var td := fields["trajectory"] as Dictionary
		var ttype := str(td.get("type", "Linear")).to_lower()
		var traj: GDSkillClips.SkillProjectileTrajectory
		match ttype:
			"parabola":
				var pt := GDSkillClips.ParabolaTrajectory.new()
				pt.configure(float(td.get("archHeight", 2.0)))
				traj = pt
			"homing":
				var ht := GDSkillClips.HomingTrajectory.new()
				ht.configure(float(td.get("homingStrength", 0.5)))
				traj = ht
			"bezier":
				var bt := GDSkillClips.BezierTrajectory.new()
				bt.configure(_to_vec3(td.get("controlOffset", [0, 2, 0])))
				traj = bt
			_:
				traj = GDSkillClips.LinearTrajectory.new()
		(clip as GDSkillClips.SpawnProjectileClip).configure_trajectory(traj, (clip as GDSkillClips.SpawnProjectileClip).reversed)

	if clip is GDSkillClips.PushEventClip and fields.get("events") is Array:
		var ev_arr: Array = fields["events"]
		var typed_events: Array[GDSkillClips.SkillCustomEvent] = []
		for item in ev_arr:
			if item is Dictionary:
				var ed := item as Dictionary
				var ce := GDSkillClips.SkillCustomEvent.new()
				ce.configure(
					str(ed.get("eventId", "")),
					float(ed.get("floatParam", 0.0)),
					str(ed.get("stringParam", "")),
					_to_vec3(ed.get("vectorParam", [0, 0, 0]))
				)
				typed_events.append(ce)
		(clip as GDSkillClips.PushEventClip).configure(typed_events)

	return clip

static func _write_clip_field(clip: GDSkillClips.SkillClip, def: Dictionary, raw: Variant) -> void:
	var prop := str(def["prop"])
	var kind := str(def["kind"])
	match kind:
		"String":
			clip.set(prop, str(raw) if raw != null else "")
		"Float":
			clip.set(prop, float(raw) if raw != null else 0.0)
		"Int":
			clip.set(prop, int(raw) if raw != null else 0)
		"Bool":
			clip.set(prop, bool(raw) if raw != null else false)
		"EnumInt":
			if raw is int:
				clip.set(prop, raw)
			else:
				var evs: Array = def.get("enumValues", [])
				var s := str(raw).strip_edges()
				if s.is_valid_int():
					clip.set(prop, s.to_int())
				else:
					for i in range(evs.size()):
						if str(evs[i]).to_lower() == s.to_lower():
							clip.set(prop, i)
							break
		"Vec3":
			clip.set(prop, _to_vec3(raw))
		"Color":
			clip.set(prop, _to_color(raw))
		"ObjectRef":
			if raw is Resource:
				clip.set(prop, raw)
			elif raw is String and not (raw as String).is_empty() and ResourceLoader.exists(raw):
				clip.set(prop, ResourceLoader.load(raw))

static func _to_vec3(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		var a := raw as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if raw is float or raw is int:
		var v := float(raw)
		return Vector3(v, v, v)
	return Vector3.ONE

static func _to_color(raw: Variant) -> Color:
	if raw is Color:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		var a := raw as Array
		var alpha := float(a[3]) if a.size() >= 4 else 1.0
		return Color(float(a[0]), float(a[1]), float(a[2]), alpha)
	return Color.WHITE

# ─────────────────────── SkillCli 主入口 ───────────────────────

static func run_cli(command: String, args: Array = []) -> String:
	var ctx := _parse_cli_args(args if args != null else [])
	match command:
		"skill.list":
			return _cmd_list(ctx)
		"skill.clip-types":
			return _cmd_clip_types()
		"skill.describe":
			return _cmd_describe(ctx)
		"skill.create":
			return _cmd_create(ctx)
		"skill.validate":
			return _cmd_validate(ctx)
		"skill.effect.create":
			return _cmd_effect_create(ctx)
		"skill.preview.setup":
			return _ok("skill.preview.setup", {"scenePath": "%s/GameRes/Preview/SkillPreview.tscn" % DEFAULT_MODULE_ROOT})
		"skill.preview.cast":
			return _cmd_preview_cast(ctx)
		_:
			return _err(
				command,
				"unknown-command",
				"未知命令：%s（合法集合：skill.{list|clip-types|describe|create|validate|effect.create|preview.setup|preview.cast}）" % command
			)

static func _cmd_list(ctx: Dictionary) -> String:
	var root := str(ctx.get("project_path", DEFAULT_MODULE_ROOT))
	var skills := get_all_known_skills(root)
	var items: Array = []
	for so in skills:
		var clip_cnt := 0
		for g in so.groups:
			if g != null:
				for t in g.tracks:
					if t != null:
						clip_cnt += t.clips.size()
		items.append({
			"name": so.skill_name,
			"id": so.skill_id,
			"uniqueName": so.unique_name,
			"display": so.display_name,
			"groupCount": so.groups.size(),
			"durationMs": so.duration_ms,
			"clipCount": clip_cnt,
			"path": so.resource_path,
		})
	return _ok("skill.list", {"count": items.size(), "skills": items})

static func _cmd_clip_types() -> String:
	var clip_types: Array = []
	for short_name in ALL_CLIP_TYPES:
		clip_types.append({
			"type": short_name,
			"display": get_display_name(short_name),
			"track": GDSkillTypes.track_kind_name(get_track_kind(short_name)),
			"fields": get_field_defs(short_name),
		})
	return _ok("skill.clip-types", {
		"count": clip_types.size(),
		"clipTypes": clip_types,
	})

static func _cmd_describe(ctx: Dictionary) -> String:
	var query := str(ctx.get("skill", "")).strip_edges()
	if query.is_empty():
		return _err("skill.describe", "skill-required", "缺少 --skill <name>")
	var so := find_skill_by_query(query, str(ctx.get("project_path", DEFAULT_MODULE_ROOT)))
	if so == null:
		return _err("skill.describe", "not-found", "找不到技能：%s" % query)
	return _ok("skill.describe", {"spec": describe_skill_to_spec_dict(so)})

static func describe_skill_to_spec_dict(so: GDSkillRes) -> Dictionary:
	var groups_json: Array = []
	var clips_json: Array = []
	var ordinal := 0
	for grp in so.groups:
		if grp == null:
			continue
		var tracks_json: Array = []
		for trk in grp.tracks:
			if trk == null:
				continue
			tracks_json.append({
				"name": trk.track_name,
				"kind": GDSkillTypes.track_kind_name(trk.kind),
			})
			for clip in trk.clips:
				if clip == null:
					continue
				var sname: String = clip.get_clip_short_name()
				clips_json.append({
					"id": "%s%d" % [sname, ordinal],
					"type": sname,
					"group": grp.group_name,
					"track": trk.track_name,
					"startMs": clip.start_ms,
					"durationMs": clip.duration_ms,
					"displayName": clip.display_name,
					"fields": read_clip_fields(clip),
				})
				ordinal += 1
		groups_json.append({
			"name": grp.group_name,
			"tracks": tracks_json,
		})

	return {
		"name": so.skill_name,
		"id": so.skill_id,
		"display": so.display_name,
		"description": so.description,
		"durationMs": so.duration_ms,
		"cost": {
			"attributeName": so.cost.attribute_name if so.cost != null else "Mana",
			"amount": so.cost.amount if so.cost != null else 0.0,
		},
		"cooldown": {
			"cdGroup": so.cooldown.cd_group if so.cooldown != null else "Default",
			"durationSeconds": so.cooldown.duration_seconds if so.cooldown != null else 0.0,
		},
		"requiredTags": [],
		"blockedTags": [],
		"groups": groups_json,
		"clips": clips_json,
	}

static func _cmd_create(ctx: Dictionary) -> String:
	var inline_json := str(ctx.get("inline", "")).strip_edges()
	var spec_path := str(ctx.get("spec_path", "")).strip_edges()
	var json_str := ""
	if not inline_json.is_empty():
		json_str = inline_json
	elif not spec_path.is_empty():
		if not FileAccess.file_exists(spec_path):
			return _err("skill.create", "spec-not-found", "spec 文件不存在：%s" % spec_path)
		var f := FileAccess.open(spec_path, FileAccess.READ)
		json_str = f.get_as_text()
		f.close()
	else:
		return _err("skill.create", "spec-required", "缺少 --spec <path> 或 --inline <json>")

	var parsed = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		return _err("skill.create", "spec-parse-failed", "JSON 解析失败")

	var res := build_from_spec(
		parsed as Dictionary,
		bool(ctx.get("dry_run", false)),
		str(ctx.get("project_path", DEFAULT_MODULE_ROOT))
	)
	if not bool(res.get("ok", false)):
		return _err("skill.create", str(res.get("error_code", "create-failed")), str(res.get("error_message", "unknown")))
	var payload := {
		"skillSO": str(res.get("skill_so_path", "")),
		"groups": res.get("group_names", []),
	}
	if bool(res.get("dry_run", false)):
		payload["dryRun"] = true
	return _ok("skill.create", payload)

static func _cmd_validate(ctx: Dictionary) -> String:
	var target := str(ctx.get("skill", "")).strip_edges()
	if target.is_empty():
		return _err("skill.validate", "skill-required", "缺少 --skill <name|all>")
	var root := str(ctx.get("project_path", DEFAULT_MODULE_ROOT))
	var issues_out: Array = []
	if target.to_lower() == "all":
		for so in get_all_known_skills(root):
			var typed := GDSkillEditorMathAndValidator.SkillAssetValidator.validate(so)
			for iss in typed:
				if iss.code != "skill-null":
					issues_out.append({"code": iss.code, "skill": so.unique_name, "detail": iss.detail})
	else:
		var so := find_skill_by_query(target, root)
		if so == null:
			return _err("skill.validate", "not-found", "找不到技能：%s" % target)
		var typed := GDSkillEditorMathAndValidator.SkillAssetValidator.validate(so)
		for iss in typed:
			if iss.code != "skill-null":
				issues_out.append({"code": iss.code, "detail": iss.detail})
	return _ok("skill.validate", {"skill": target, "issues": issues_out})

static func _cmd_effect_create(ctx: Dictionary) -> String:
	var extras: Dictionary = ctx.get("extras", {})
	var eff_name := str(extras.get("name", "")).strip_edges()
	if eff_name.is_empty():
		return _err("skill.effect.create", "name-required", "缺少 --name")
	if not GDSkillTypes.SkillIdentity.is_valid_name(eff_name):
		return _err("skill.effect.create", "invalid-name", "effect name 非法：%s" % eff_name)
	var dur := float(extras.get("duration", "0"))
	var per := float(extras.get("period", "0"))
	var mods_raw := str(extras.get("modifiers", ""))
	var mods: Array[GDSkillTypes.GameplayEffectModifier] = []
	if not mods_raw.strip_edges().is_empty():
		for token in mods_raw.split(","):
			var t := token.strip_edges()
			if t.is_empty():
				continue
			var parts := t.split(":")
			if parts.size() != 3:
				return _err("skill.effect.create", "modifier-parse-failed", "modifier 语法应为 attr:op:magnitude")
			var op_str := parts[1].strip_edges().to_lower()
			var op := GDSkillTypes.ModifierOp.ADD
			if op_str == "multiply":
				op = GDSkillTypes.ModifierOp.MULTIPLY
			elif op_str == "override":
				op = GDSkillTypes.ModifierOp.OVERRIDE
			elif op_str != "add":
				return _err("skill.effect.create", "modifier-parse-failed", "未知 modifier op")
			if not parts[2].strip_edges().is_valid_float():
				return _err("skill.effect.create", "modifier-parse-failed", "magnitude 非数字")
			mods.append(GDSkillTypes.GameplayEffectModifier.new(parts[0].strip_edges(), op, parts[2].strip_edges().to_float()))

	var root := str(ctx.get("project_path", DEFAULT_MODULE_ROOT)).trim_suffix("/")
	var eff_path := "%s/GameRes/Effect/Effect_%s_Skill.tres" % [root, eff_name]
	var dry := bool(ctx.get("dry_run", false))
	if not dry:
		GDCliRoot.AtomCreator.ensure_dir("%s/GameRes/Effect" % root)
		var eff := GDSkillTypes.GameplayEffectRes.new()
		eff.duration = dur
		eff.period = per
		eff.modifiers = mods
		ResourceSaver.save(eff, eff_path)
	var payload := {"effectPath": eff_path, "modifierCount": mods.size()}
	if dry:
		payload["dryRun"] = true
	return _ok("skill.effect.create", payload)

static func _cmd_preview_cast(ctx: Dictionary) -> String:
	var q := str(ctx.get("skill", "")).strip_edges()
	if q.is_empty():
		return _err("skill.preview.cast", "skill-required", "缺少 --skill <name>")
	var so := find_skill_by_query(q, str(ctx.get("project_path", DEFAULT_MODULE_ROOT)))
	var sid := so.unique_name if so != null else GDSkillTypes.SkillIdentity.to_asset_name(q, 0)
	return _ok("skill.preview.cast", {"casted": so != null, "skill": sid})

static func find_skill_by_query(query: String, root: String = DEFAULT_MODULE_ROOT) -> GDSkillRes:
	var q := query.strip_edges()
	if _in_memory_skills.has(q):
		return _in_memory_skills[q]
	var all := get_all_known_skills(root)
	var parsed := GDSkillTypes.SkillIdentity.try_parse_asset_name(q)
	if not bool(parsed.get("ok", false)):
		parsed = GDSkillTypes.SkillIdentity.try_split_name_and_trailing_id(q)
	if not bool(parsed.get("ok", false)):
		parsed = GDSkillTypes.SkillIdentity.try_split_compact_name(q)
	for so in all:
		if so.unique_name == q or so.skill_name.to_lower() == q.to_lower():
			return so
		if bool(parsed.get("ok", false)) and so.skill_name.to_lower() == str(parsed["name"]).to_lower() and so.skill_id == int(parsed["id"]):
			return so
	return null

static func _parse_cli_args(args: Array) -> Dictionary:
	var ctx := {
		"skill": "",
		"spec_path": "",
		"inline": "",
		"project_path": DEFAULT_MODULE_ROOT,
		"dry_run": false,
		"extras": {},
	}
	var i := 0
	while i < args.size():
		var key := str(args[i])
		if key == "--dry-run":
			ctx["dry_run"] = true
			i += 1
			continue
		var val := str(args[i + 1]) if (i + 1 < args.size() and not str(args[i + 1]).begins_with("--")) else ""
		match key:
			"--skill":
				ctx["skill"] = val
				i += 1
			"--spec":
				ctx["spec_path"] = val
				i += 1
			"--inline":
				ctx["inline"] = val
				i += 1
			"--project-path":
				ctx["project_path"] = val
				i += 1
			_:
				if key.begins_with("--") and not val.is_empty():
					(ctx["extras"] as Dictionary)[key.substr(2)] = val
					i += 1
		i += 1
	return ctx

static func _ok(cmd: String, payload: Dictionary) -> String:
	var out := {"ok": true, "command": cmd}
	for k in payload.keys():
		out[k] = payload[k]
	return JSON.stringify(out)

static func _err(cmd: String, code: String, msg: String) -> String:
	return JSON.stringify({"ok": false, "command": cmd, "code": code, "message": msg})
