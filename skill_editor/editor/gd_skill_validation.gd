@tool
class_name GDSkillValidation
extends RefCounted

## 技能资产静态校验（SkillAssetValidator）+ SKILL.md 规则 Linter（S0..S7）+ tools.yaml Doctor（D0..D4）
## 对应 SkillAssetValidator / SkillLinter / SkillDoctor

class SkillValidationIssue extends RefCounted:
	var code: String = ""
	var detail: String = ""
	## 出问题的位置 [组, 轨道, 片段]，可以只有前缀；空表示整个技能。
	var path: PackedInt32Array = PackedInt32Array()

	func _init(p_code: String = "", p_detail: String = "", p_path: PackedInt32Array = PackedInt32Array()) -> void:
		code = p_code
		detail = p_detail
		path = p_path

	func format_issue() -> String:
		return code if detail.is_empty() else "%s — %s" % [code, detail]


class SkillAssetValidator extends RefCounted:
	static func validate(so: GDSkillRes) -> Array[SkillValidationIssue]:
		var issues: Array[SkillValidationIssue] = []
		if so == null:
			issues.append(SkillValidationIssue.new("skill-null", "未提供 SkillSO"))
			return issues

		if not GDSkillTypes.SkillIdentity.is_valid_name(so.skill_name):
			issues.append(SkillValidationIssue.new("skill-name-missing", so.resource_name))
		elif so.skill_id < 0:
			issues.append(SkillValidationIssue.new("skill-id-invalid", str(so.skill_id)))
		elif not so.resource_path.is_empty():
			var file_name := so.resource_path.get_file().get_basename()
			if so.unique_name != file_name:
				issues.append(SkillValidationIssue.new("skill-id-mismatch", "%s != %s" % [so.unique_name, file_name]))

		if so.groups.is_empty():
			issues.append(SkillValidationIssue.new("no-groups", so.unique_name))

		var group_names: Dictionary = {}
		var max_end_ms := 0
		for g in range(so.groups.size()):
			var group = so.groups[g]
			if group == null:
				issues.append(SkillValidationIssue.new("group-missing", str(g)))
				continue
			if group.group_name.is_empty():
				issues.append(SkillValidationIssue.new("group-name-missing", str(g), PackedInt32Array([g])))
			elif group_names.has(group.group_name):
				issues.append(SkillValidationIssue.new("group-name-duplicate", group.group_name, PackedInt32Array([g])))
			else:
				group_names[group.group_name] = true

			for t in range(group.tracks.size()):
				var track = group.tracks[t]
				if track == null:
					continue
				for c in range(track.clips.size()):
					var clip = track.clips[c]
					if clip == null:
						issues.append(SkillValidationIssue.new("clip-missing", group.group_name, PackedInt32Array([g, t, c])))
						continue
					max_end_ms = maxi(max_end_ms, clip.start_ms + maxi(0, clip.duration_ms))
					_add_missing_ref(issues, group.group_name, clip, PackedInt32Array([g, t, c]))

		if so.duration_ms < max_end_ms:
			issues.append(SkillValidationIssue.new("duration-too-short", "%d < %d" % [so.duration_ms, max_end_ms]))

		_add_null_tag_issues(issues, so.required_tags, "requiredTags")
		_add_null_tag_issues(issues, so.blocked_tags, "blockedTags")
		return issues

	static func _add_missing_ref(issues: Array[SkillValidationIssue], group_name: String, clip: GDSkillClips.SkillClip, at: PackedInt32Array = PackedInt32Array()) -> void:
		var short_name := clip.get_clip_short_name()
		if clip is GDSkillClips.ApplyEffectClip and (clip as GDSkillClips.ApplyEffectClip).effect == null:
			issues.append(SkillValidationIssue.new("ref-missing", "%s.%s.effect" % [group_name, short_name], at))
		elif clip is GDSkillClips.SpawnProjectileClip and (clip as GDSkillClips.SpawnProjectileClip).prefab == null:
			issues.append(SkillValidationIssue.new("ref-missing", "%s.%s.prefab" % [group_name, short_name], at))

	static func _add_null_tag_issues(issues: Array[SkillValidationIssue], tags: Array, field_name: String) -> void:
		for i in range(tags.size()):
			if tags[i] == null:
				issues.append(SkillValidationIssue.new("ref-missing", "%s[%d]" % [field_name, i]))


## SkillLinter 对应：规则码 S0..S7
class SkillLinter extends RefCounted:
	const SOFT_LINE_LIMIT := 120
	const HARD_LINE_LIMIT := 150
	const REQUIRED_FRONTMATTER := ["name", "description", "triggers", "globs"]

	static func lint_markdown_text(lines: PackedStringArray, rel_path: String = "SKILL.md") -> Array[Dictionary]:
		var issues: Array[Dictionary] = []
		var n := lines.size()
		if n > HARD_LINE_LIMIT:
			issues.append({"severity": "Critical", "code": "S1", "file": rel_path, "line": n, "message": "SKILL.md 行数 %d > 硬上限 %d" % [n, HARD_LINE_LIMIT]})
		elif n > SOFT_LINE_LIMIT:
			issues.append({"severity": "Warning", "code": "S1", "file": rel_path, "line": n, "message": "SKILL.md 行数 %d > 软上限 %d" % [n, SOFT_LINE_LIMIT]})

		# Frontmatter S5
		var fm_start := -1
		var fm_end := -1
		for i in range(lines.size()):
			if lines[i].strip_edges() == "---":
				if fm_start < 0:
					fm_start = i
				else:
					fm_end = i
					break
			elif fm_start < 0 and not lines[i].strip_edges().is_empty():
				break
		if fm_start < 0 or fm_end < 0:
			issues.append({"severity": "Critical", "code": "S5", "file": rel_path, "line": 1, "message": "缺少 Frontmatter（`---` 分隔的 YAML 块）"})
		else:
			var present: Dictionary = {}
			for i in range(fm_start + 1, fm_end):
				var ln := lines[i]
				var colon := ln.find(":")
				if colon > 0:
					present[ln.substr(0, colon).strip_edges().to_lower()] = true
			for req in REQUIRED_FRONTMATTER:
				if not present.has(req):
					issues.append({"severity": "Critical", "code": "S5", "file": rel_path, "line": fm_start + 1, "message": "Frontmatter 缺字段：%s" % req})

		# S4 Required sections
		for prefix in ["## 1.", "## 3.", "## 5.", "## 7."]:
			var found := false
			for ln in lines:
				if ln.begins_with(prefix):
					found = true
					break
			if not found:
				issues.append({"severity": "Warning", "code": "S4", "file": rel_path, "line": 0, "message": "缺少章节 `%s...`" % prefix})
		return issues


## SkillDoctor 对应：核对 tools.yaml ↔ CLI Registry 一致性（规则码 D0..D4）
class SkillDoctor extends RefCounted:
	const VALID_ROLES := {"V": true, "G": true, "I": true, "P": true, "R": true}

	static func doctor_yaml_text(lines: PackedStringArray, registered_commands: Dictionary, rel_path: String = "tools.yaml") -> Array[Dictionary]:
		var issues: Array[Dictionary] = []
		var version := 0
		var has_tools_key := false
		var tools: Array[Dictionary] = []
		var cur_tool: Dictionary = {}
		var section := ""

		for i in range(lines.size()):
			var raw := lines[i]
			var hash_idx := raw.find("#")
			var clean := (raw.substr(0, hash_idx) if hash_idx >= 0 else raw).strip_edges(false, true)
			if clean.strip_edges().is_empty():
				continue
			var indent := clean.length() - clean.strip_edges(true, false).length()
			var t := clean.strip_edges()
			if indent == 0:
				if not cur_tool.is_empty():
					tools.append(cur_tool)
					cur_tool = {}
				if t.begins_with("version:"):
					var v_str := t.substr(8).strip_edges()
					if v_str.is_valid_int():
						version = v_str.to_int()
					section = ""
				elif t.begins_with("tools:"):
					has_tools_key = true
					section = "" if t.substr(6).strip_edges() == "[]" else "tools"
				else:
					section = ""
				continue
			if section == "tools":
				if t.begins_with("- "):
					if not cur_tool.is_empty():
						tools.append(cur_tool)
					cur_tool = {"line": i + 1, "name": "", "role": "", "required": false}
					var after := t.substr(2).strip_edges()
					if not after.is_empty():
						_apply_kv(after, cur_tool)
				elif not cur_tool.is_empty():
					_apply_kv(t, cur_tool)
		if not cur_tool.is_empty():
			tools.append(cur_tool)

		if version <= 0:
			issues.append({"severity": "Warning", "code": "D1", "file": rel_path, "line": 0, "message": "tools.yaml 缺 `version:` 字段或非正整数"})
		if not has_tools_key:
			issues.append({"severity": "Warning", "code": "D1", "file": rel_path, "line": 0, "message": "tools.yaml 缺 `tools:` 列表"})

		var seen: Dictionary = {}
		for idx in range(tools.size()):
			var te := tools[idx]
			var tname := str(te["name"])
			var trole := str(te["role"])
			var ln := int(te["line"])
			if tname.is_empty():
				issues.append({"severity": "Critical", "code": "D2", "file": rel_path, "line": ln, "message": "tools[%d] 缺 `name:`" % idx})
				continue
			if seen.has(tname):
				issues.append({"severity": "Warning", "code": "D2", "file": rel_path, "line": ln, "message": "tools[%d] 重复 name='%s'" % [idx, tname]})
			seen[tname] = true
			if trole.is_empty():
				issues.append({"severity": "Warning", "code": "D2", "file": rel_path, "line": ln, "message": "tools[%d] 缺 `role:`" % idx})
			elif not VALID_ROLES.has(trole):
				issues.append({"severity": "Critical", "code": "D2", "file": rel_path, "line": ln, "message": "role='%s' 不在 {V,G,I,P,R}" % trole})

			if not registered_commands.has(tname):
				if bool(te["required"]):
					issues.append({"severity": "Critical", "code": "D3", "file": rel_path, "line": ln, "message": "required=true 的 CLI `%s` 未注册" % tname})
				else:
					issues.append({"severity": "Warning", "code": "D4", "file": rel_path, "line": ln, "message": "CLI `%s` 未注册（required=false）" % tname})
		return issues

	static func _apply_kv(kv: String, target: Dictionary) -> void:
		var colon := kv.find(":")
		if colon <= 0:
			return
		var k := kv.substr(0, colon).strip_edges().to_lower()
		var v := kv.substr(colon + 1).strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
		match k:
			"name": target["name"] = v
			"role": target["role"] = v
			"required": target["required"] = v.to_lower() == "true"
