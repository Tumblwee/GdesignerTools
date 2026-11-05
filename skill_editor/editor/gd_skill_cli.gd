@tool
class_name GDSkillCli
extends RefCounted

## 技能编辑器 CLI（对应 SkillCli）：skill.* 命令表。装配与查找逻辑在 GDSkillForge。

const MODIFIER_OPS := {
	"add": GDSkillTypes.ModifierOp.ADD,
	"multiply": GDSkillTypes.ModifierOp.MULTIPLY,
	"override": GDSkillTypes.ModifierOp.OVERRIDE,
}

static func commands() -> Dictionary:
	return {
		"skill.list": {"run": _cmd_list, "summary": "列出全部技能 ([--project-path])"},
		"skill.clip-types": {"run": _cmd_clip_types, "summary": "列出全部 Clip 类型、显示名、轨道与字段目录"},
		"skill.describe": {"run": _cmd_describe, "summary": "把技能导出为 Spec JSON (--skill)"},
		"skill.create": {"run": _cmd_create, "summary": "按 Spec 装配并保存技能 (--spec <path> | --inline <json>) [--dry-run]"},
		"skill.validate": {"run": _cmd_validate, "summary": "校验技能资产 (--skill <name|all>)"},
		"skill.effect.create": {"run": _cmd_effect_create, "summary": "创建 GameplayEffect 资产 (--name [--duration --period --modifiers attr:op:mag,...])"},
		"skill.preview.setup": {"run": _cmd_preview_setup, "summary": "返回技能预览场景路径"},
		"skill.preview.cast": {"run": _cmd_preview_cast, "summary": "在预览中释放技能 (--skill)"},
	}

static func run(command: String, args: Array = []) -> String:
	return GDCliRoot.dispatch(commands(), command, args)

static func _root(ctx: GDCliRoot.CliContext) -> String:
	return ctx.get_option("project-path", GDSkillForge.DEFAULT_MODULE_ROOT)

static func _cmd_list(ctx: GDCliRoot.CliContext) -> String:
	var items: Array = []
	for so in GDSkillForge.get_all_known_skills(_root(ctx)):
		var clip_cnt := 0
		for g in so.groups:
			for t in (g.tracks if g != null else []):
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
	return ctx.ok({"count": items.size(), "skills": items})

static func _cmd_clip_types(ctx: GDCliRoot.CliContext) -> String:
	var clip_types: Array = []
	for short_name in GDSkillForge.clip_types():
		clip_types.append({
			"type": short_name,
			"display": GDSkillForge.get_display_name(short_name),
			"track": GDSkillTypes.track_kind_name(GDSkillForge.get_track_kind(short_name)),
			"fields": GDSkillForge.get_field_defs(short_name),
		})
	return ctx.ok({"count": clip_types.size(), "clipTypes": clip_types})

static func _cmd_describe(ctx: GDCliRoot.CliContext) -> String:
	var query := ctx.get_option("skill").strip_edges()
	if query.is_empty():
		return ctx.fail("skill-required", "缺少 --skill <name>")
	var so := GDSkillForge.find_skill_by_query(query, _root(ctx))
	if so == null:
		return ctx.fail("not-found", "找不到技能：%s" % query)
	return ctx.ok({"spec": GDSkillForge.describe_skill_to_spec_dict(so)})

static func _cmd_create(ctx: GDCliRoot.CliContext) -> String:
	var json_str := ctx.get_option("inline").strip_edges()
	var spec_path := ctx.get_option("spec").strip_edges()
	if json_str.is_empty():
		if spec_path.is_empty():
			return ctx.fail("spec-required", "缺少 --spec <path> 或 --inline <json>")
		if not FileAccess.file_exists(spec_path):
			return ctx.fail("spec-not-found", "spec 文件不存在：%s" % spec_path)
		json_str = FileAccess.get_file_as_string(spec_path)

	var parsed: Variant = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		return ctx.fail("spec-parse-failed", "JSON 解析失败")
	var res := GDSkillForge.build_from_spec(parsed, ctx.has_flag("dry-run"), _root(ctx))
	if not bool(res.get("ok", false)):
		return ctx.fail(str(res.get("error_code", "create-failed")), str(res.get("error_message", "unknown")))
	var payload := {"skillSO": str(res.get("skill_so_path", "")), "groups": res.get("group_names", [])}
	if bool(res.get("dry_run", false)):
		payload["dryRun"] = true
	return ctx.ok(payload)

static func _cmd_validate(ctx: GDCliRoot.CliContext) -> String:
	var target := ctx.get_option("skill").strip_edges()
	if target.is_empty():
		return ctx.fail("skill-required", "缺少 --skill <name|all>")
	var issues_out: Array = []
	if target.to_lower() == "all":
		for so in GDSkillForge.get_all_known_skills(_root(ctx)):
			for iss in GDSkillValidation.SkillAssetValidator.validate(so):
				issues_out.append({"code": iss.code, "skill": so.unique_name, "detail": iss.detail})
	else:
		var so := GDSkillForge.find_skill_by_query(target, _root(ctx))
		if so == null:
			return ctx.fail("not-found", "找不到技能：%s" % target)
		for iss in GDSkillValidation.SkillAssetValidator.validate(so):
			issues_out.append({"code": iss.code, "detail": iss.detail})
	return ctx.ok({"skill": target, "issues": issues_out})

static func _cmd_effect_create(ctx: GDCliRoot.CliContext) -> String:
	var eff_name := ctx.get_option("name").strip_edges()
	if eff_name.is_empty():
		return ctx.fail("name-required", "缺少 --name")
	if not GDSkillTypes.SkillIdentity.is_valid_name(eff_name):
		return ctx.fail("invalid-name", "effect name 非法：%s" % eff_name)
	var mods: Array[GDGameplayEffectModifierRes] = []
	for token in ctx.get_option("modifiers").split(",", false):
		var t := token.strip_edges()
		if t.is_empty():
			continue
		var parts := t.split(":")
		if parts.size() != 3:
			return ctx.fail("modifier-parse-failed", "modifier 语法应为 attr:op:magnitude")
		var op: int = MODIFIER_OPS.get(parts[1].strip_edges().to_lower(), -1)
		if op < 0:
			return ctx.fail("modifier-parse-failed", "未知 modifier op")
		if not parts[2].strip_edges().is_valid_float():
			return ctx.fail("modifier-parse-failed", "magnitude 非数字")
		mods.append(GDGameplayEffectModifierRes.new(parts[0].strip_edges(), op, parts[2].strip_edges().to_float()))

	var root := _root(ctx).trim_suffix("/")
	var eff_path := "%s/skill/effect/Effect_%s_Skill.tres" % [root, eff_name]
	var payload := {"effectPath": eff_path, "modifierCount": mods.size()}
	if ctx.has_flag("dry-run"):
		payload["dryRun"] = true
		return ctx.ok(payload)
	var eff := GDGameplayEffectRes.new()
	eff.duration = ctx.get_option("duration", "0").to_float()
	eff.period = ctx.get_option("period", "0").to_float()
	eff.modifiers = mods
	var err := GDDocument.new(eff).save(eff_path)
	if err != OK:
		return ctx.fail("save-failed", "保存失败：%s（%s）" % [eff_path, error_string(err)])
	return ctx.ok(payload)

static func _cmd_preview_setup(ctx: GDCliRoot.CliContext) -> String:
	return ctx.ok({"scenePath": "%s/skill/preview/SkillPreview.tscn" % GDSkillForge.DEFAULT_MODULE_ROOT})

static func _cmd_preview_cast(ctx: GDCliRoot.CliContext) -> String:
	var q := ctx.get_option("skill").strip_edges()
	if q.is_empty():
		return ctx.fail("skill-required", "缺少 --skill <name>")
	var so := GDSkillForge.find_skill_by_query(q, _root(ctx))
	return ctx.ok({"casted": so != null, "skill": so.unique_name if so != null else GDSkillTypes.SkillIdentity.to_asset_name(q, 0)})
