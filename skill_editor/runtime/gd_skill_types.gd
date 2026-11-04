@tool
class_name GDSkillTypes
extends RefCounted

## 技能模块枚举、身份拼法与 GameplayTag / GameplayEffect 共享资产模型
## 对应 SkillClipEnums / SkillIdentity / ModifierOp / GameplayTagSO / GameplayEffectModifier / GameplayEffectSO / AttributeKind / AttributeNameMap / SkillClock

enum SkillTrackKind {
	ANIMATION = 0,
	MOVEMENT = 1,
	HITBOX = 2,
	EFFECT = 3,
	AUDIO = 4,
	CAMERA = 5,
	VFX = 6,
}

enum SkillHitShapeKind {
	SPHERE = 0,
	BOX = 1,
}

enum SkillProjectileDirectionKind {
	TO_TARGET = 0,
	CASTER_FORWARD = 1,
}

enum SkillTeleportModeKind {
	TO_TARGET_SIDE = 0,
	BACK_TO_ORIGIN = 1,
}

enum SkillVfxAnchorKind {
	CASTER_ROOT = 0,
	CASTER_HAND = 1,
	TARGET_ROOT = 2,
}

enum SkillCameraEffectMode {
	PUSH_TO_TARGET = 0,
	PULL_FROM_TARGET = 1,
	SHAKE = 2,
	FOCUS_TARGET = 3,
}

enum SkillCameraTargetKind {
	TARGET = 0,
	SELF = 1,
}

enum SkillVisualMoveSpace {
	LOCAL = 0,
	CASTER_FORWARD = 1,
	TOWARD_TARGET = 2,
}

enum ModifierOp {
	ADD = 0,
	MULTIPLY = 1,
	OVERRIDE = 2,
}

enum AttributeKind {
	HEALTH = 1,
	MAX_HEALTH = 2,
	MANA = 3,
	MAX_MANA = 4,
	ATTACK_POWER = 5,
	DEFENSE = 6,
	MOVE_SPEED = 7,
}


## 属性名映射（对应 AttributeNameMap）
static func try_map_attribute_name(attr_name: String) -> Dictionary:
	if attr_name == null or attr_name.is_empty():
		return {"ok": false, "kind": 0}
	match attr_name.strip_edges().to_lower():
		"hp", "health":
			return {"ok": true, "kind": AttributeKind.HEALTH}
		"maxhp", "maxhealth":
			return {"ok": true, "kind": AttributeKind.MAX_HEALTH}
		"mp", "mana", "stamina":
			return {"ok": true, "kind": AttributeKind.MANA}
		"maxmp", "maxmana":
			return {"ok": true, "kind": AttributeKind.MAX_MANA}
		"attackpower", "atk", "attack":
			return {"ok": true, "kind": AttributeKind.ATTACK_POWER}
		"defense", "def":
			return {"ok": true, "kind": AttributeKind.DEFENSE}
		"movespeed", "speed":
			return {"ok": true, "kind": AttributeKind.MOVE_SPEED}
		_:
			return {"ok": false, "kind": 0}

static func track_kind_name(kind: int) -> String:
	match kind:
		SkillTrackKind.ANIMATION: return "Animation"
		SkillTrackKind.MOVEMENT: return "Movement"
		SkillTrackKind.HITBOX: return "Hitbox"
		SkillTrackKind.EFFECT: return "Effect"
		SkillTrackKind.AUDIO: return "Audio"
		SkillTrackKind.CAMERA: return "Camera"
		SkillTrackKind.VFX: return "Vfx"
		_: return "Effect"

static func parse_track_kind(s: String) -> int:
	match s.strip_edges().to_lower():
		"animation": return SkillTrackKind.ANIMATION
		"movement": return SkillTrackKind.MOVEMENT
		"hitbox": return SkillTrackKind.HITBOX
		"effect": return SkillTrackKind.EFFECT
		"audio": return SkillTrackKind.AUDIO
		"camera": return SkillTrackKind.CAMERA
		"vfx": return SkillTrackKind.VFX
		_: return SkillTrackKind.EFFECT


## SkillIdentity 对应：技能资产身份拼法与解析单源（Skill_{Name}_{Id}）
class SkillIdentity extends RefCounted:
	const EXPLORE_NAME := "Explore"
	const ASSET_PREFIX := "Skill_"
	const LEGACY_SUFFIX := "_Skill"

	static func to_asset_name(skill_name: String, skill_id: int) -> String:
		return "%s%s_%d" % [ASSET_PREFIX, skill_name if skill_name != null else "", skill_id]

	static func is_valid_name(skill_name: String) -> bool:
		if skill_name == null or skill_name.is_empty():
			return false
		var c0 := skill_name.unicode_at(0)
		var first_ok := (c0 >= 65 and c0 <= 90) or (c0 >= 97 and c0 <= 122) or c0 == 95
		if not first_ok:
			return false
		for i in range(1, skill_name.length()):
			var c := skill_name.unicode_at(i)
			var ok := (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
			if not ok:
				return false
		return true

	static func try_parse_asset_name(asset_name: String) -> Dictionary:
		if asset_name == null or not asset_name.begins_with(ASSET_PREFIX):
			return {"ok": false, "name": "", "id": 0}
		var rest := asset_name.substr(ASSET_PREFIX.length())
		if rest.ends_with(LEGACY_SUFFIX):
			var middle := rest.substr(0, rest.length() - LEGACY_SUFFIX.length())
			var split_res := try_split_compact_name(middle)
			if bool(split_res.get("ok", false)):
				return split_res
			if is_valid_name(middle):
				return {"ok": true, "name": middle, "id": 0}
			return {"ok": false, "name": "", "id": 0}
		return try_split_name_and_trailing_id(rest)

	static func try_split_compact_name(compact: String) -> Dictionary:
		if compact == null or compact.is_empty():
			return {"ok": false, "name": "", "id": 0}
		var last_letter := compact.length() - 1
		while last_letter >= 0 and compact.unicode_at(last_letter) >= 48 and compact.unicode_at(last_letter) <= 57:
			last_letter -= 1
		if last_letter < 0 or last_letter == compact.length() - 1:
			return {"ok": false, "name": "", "id": 0}
		var n := compact.substr(0, last_letter + 1)
		if not is_valid_name(n):
			return {"ok": false, "name": "", "id": 0}
		var tail := compact.substr(last_letter + 1)
		if not tail.is_valid_int() or tail.to_int() < 0:
			return {"ok": false, "name": "", "id": 0}
		return {"ok": true, "name": n, "id": tail.to_int()}

	static func try_split_name_and_trailing_id(name_and_id: String) -> Dictionary:
		if name_and_id == null or name_and_id.is_empty():
			return {"ok": false, "name": "", "id": 0}
		var last := name_and_id.rfind("_")
		if last <= 0 or last >= name_and_id.length() - 1:
			return {"ok": false, "name": "", "id": 0}
		var tail := name_and_id.substr(last + 1)
		if not tail.is_valid_int() or tail.to_int() < 0:
			return {"ok": false, "name": "", "id": 0}
		var n := name_and_id.substr(0, last)
		if not is_valid_name(n):
			return {"ok": false, "name": "", "id": 0}
		return {"ok": true, "name": n, "id": tail.to_int()}

	static func try_normalize(raw_name: String, raw_id: int) -> Dictionary:
		var n := raw_name.strip_edges() if raw_name != null else ""
		var id := raw_id
		var split := try_split_compact_name(n)
		if bool(split.get("ok", false)):
			var s_name := str(split["name"])
			var s_id := int(split["id"])
			if raw_id == 0 or raw_id == s_id:
				n = s_name
				id = s_id
			else:
				return {"ok": false, "name": "", "id": 0}
		if is_valid_name(n) and id >= 0:
			return {"ok": true, "name": n, "id": id}
		return {"ok": false, "name": "", "id": 0}


## GameplayTagSO 对应（带 ParentTag 祖孙树与防环 IsDescendantOf）
class GameplayTagRes extends Resource:
	@export var tag_name: String = ""
	@export var parent_tag: GameplayTagRes = null
	@export_multiline var description: String = ""

	func is_descendant_of(other: GameplayTagRes) -> bool:
		if other == null:
			return false
		var cursor: GameplayTagRes = self
		var safety := 64
		while cursor != null and safety > 0:
			safety -= 1
			if cursor == other:
				return true
			cursor = cursor.parent_tag
		return false


## GameplayEffectModifier 对应
class GameplayEffectModifier extends Resource:
	@export var attribute_name: String = ""
	@export var op: int = ModifierOp.ADD
	@export var magnitude: float = 0.0

	func _init(p_attr: String = "", p_op: int = ModifierOp.ADD, p_mag: float = 0.0) -> void:
		attribute_name = p_attr
		op = p_op
		magnitude = p_mag


## GameplayEffectSO 对应
class GameplayEffectRes extends Resource:
	@export var duration: float = 0.0
	@export var period: float = 0.0
	@export var modifiers: Array[GameplayEffectModifier] = []
	@export var granted_tags: Array[GameplayTagRes] = []


## SkillClock 对应：技能模块级可暂停时钟（引用计数式暂停 + 同帧去重守卫）
class SkillClock extends RefCounted:
	static var _now_seconds: float = 0.0
	static var _pause_depth: int = 0
	static var _last_advanced_frame: int = -1

	static var now_seconds: float:
		get:
			return _now_seconds

	static var is_paused: bool:
		get:
			return _pause_depth > 0

	static func advance(unscaled_delta_time: float, current_frame: int = -1) -> void:
		var frame := current_frame if current_frame >= 0 else Engine.get_process_frames()
		if frame == _last_advanced_frame and current_frame == -1:
			return
		_last_advanced_frame = frame
		if _pause_depth > 0:
			return
		if unscaled_delta_time <= 0.0:
			return
		_now_seconds += unscaled_delta_time

	static func pause() -> void:
		_pause_depth += 1

	static func resume() -> void:
		if _pause_depth > 0:
			_pause_depth -= 1

	static func reset_for_test() -> void:
		_now_seconds = 0.0
		_pause_depth = 0
		_last_advanced_frame = -1
