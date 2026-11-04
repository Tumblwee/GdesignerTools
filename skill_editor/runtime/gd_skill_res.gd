@tool
class_name GDSkillRes
extends Resource

## 单资产技能数据模型（对应 SkillSO / SkillCost / SkillCooldown / SkillTrackGroup / SkillTrack）
## 不变量：unique_name == "Skill_{skill_name}_{skill_id}" == 文件名 == Holder 查找键 == CLI 产物名。
## cost / cooldown / groups 由内部类组成，Godot 无法直接落盘内部类，统一经 codec_data 存取。

class SkillCost extends Resource:
	@export var raw_attribute_name: String = "Mana"
	@export var amount: float = 0.0

	var attribute_name: String:
		get:
			return "Mana" if raw_attribute_name.is_empty() else raw_attribute_name

	var has_cost: bool:
		get:
			return amount > 0.0

	func _init(p_attr: String = "Mana", p_amount: float = 0.0) -> void:
		raw_attribute_name = p_attr
		amount = p_amount


class SkillCooldown extends Resource:
	@export var raw_cd_group: String = "Default"
	@export var duration_seconds: float = 0.0

	var cd_group: String:
		get:
			return "Default" if raw_cd_group.is_empty() else raw_cd_group

	var has_cooldown: bool:
		get:
			return duration_seconds > 0.0

	func _init(p_group: String = "Default", p_dur: float = 0.0) -> void:
		raw_cd_group = p_group
		duration_seconds = p_dur


class SkillTrack extends Resource:
	@export var kind: int = GDSkillTypes.SkillTrackKind.EFFECT
	@export var track_name: String = "Effect"
	@export var clips: Array = [] # Array[GDSkillClips.SkillClip]

	func _init(p_kind: int = GDSkillTypes.SkillTrackKind.EFFECT, p_name: String = "") -> void:
		configure(p_kind, p_name)

	func add_clip(clip: GDSkillClips.SkillClip) -> void:
		if clip != null:
			clips.append(clip)

	func configure(p_kind: int, p_name: String) -> void:
		kind = p_kind
		track_name = p_name if not p_name.is_empty() else GDSkillTypes.track_kind_name(p_kind)


class SkillTrackGroup extends Resource:
	@export var group_name: String = ""
	@export var tracks: Array = [] # Array[SkillTrack]

	func _init(p_name: String = "") -> void:
		group_name = p_name

	func add_track(track: SkillTrack) -> void:
		if track != null:
			tracks.append(track)

	func configure(p_name: String) -> void:
		group_name = p_name


# ── SkillSO Header & Timeline ──

@export var skill_name: String = "New"
@export var skill_id: int = 0
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var required_tags: Array = []
@export var blocked_tags: Array = []
@export var duration_ms: int = 1000

var cost: SkillCost = SkillCost.new()
var cooldown: SkillCooldown = SkillCooldown.new()
var groups: Array = [] # Array[SkillTrackGroup]

## 唯一的落盘入口：cost / cooldown / groups 的编码形式。保存、加载、duplicate 均自动经过这里。
@export_storage var codec_data: Dictionary:
	get:
		return codec().encode({"cost": cost, "cooldown": cooldown, "groups": groups})
	set(value):
		var data: Dictionary = codec().decode(value)
		cost = data.get("cost") if data.get("cost") is SkillCost else SkillCost.new()
		cooldown = data.get("cooldown") if data.get("cooldown") is SkillCooldown else SkillCooldown.new()
		groups = data.get("groups", []).filter(func(g: Variant) -> bool: return g is SkillTrackGroup)

static var _codec: GDDataCodec = null

var unique_name: String:
	get:
		return GDSkillTypes.SkillIdentity.to_asset_name(skill_name, skill_id)

## 技能时间轴数据（本类内部类 + GDSkillClips 全部 Clip / Trajectory）的编解码器。
static func codec() -> GDDataCodec:
	if _codec == null:
		_codec = GDDataCodec.new([GDSkillRes, GDSkillClips])
	return _codec

func configure_header(p_name: String, p_id: int, p_display_name: String, p_description: String) -> void:
	skill_name = p_name
	skill_id = maxi(0, p_id)
	display_name = p_display_name
	description = p_description
	emit_changed()

func set_icon(p_icon: Texture2D) -> void:
	icon = p_icon
	emit_changed()

func set_cost(p_attr: String, p_amount: float) -> void:
	cost = SkillCost.new(p_attr, p_amount)
	emit_changed()

func set_cooldown(p_group: String, p_duration_seconds: float) -> void:
	cooldown = SkillCooldown.new(p_group, p_duration_seconds)
	emit_changed()

func set_tags(p_required: Array, p_blocked: Array) -> void:
	required_tags = p_required
	blocked_tags = p_blocked
	emit_changed()

func set_duration(p_duration_ms: int) -> void:
	duration_ms = maxi(0, p_duration_ms)
	emit_changed()

func add_group(group: SkillTrackGroup) -> void:
	if group != null:
		groups.append(group)
		emit_changed()

func clear_groups() -> void:
	groups.clear()
	emit_changed()
