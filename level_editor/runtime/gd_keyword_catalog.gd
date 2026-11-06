@tool
class_name GDKeywordCatalogSystem
extends RefCounted

## Keyword Catalog 与代码生成系统（对应 KeywordIdentifierUtil / KeywordEntry / KeywordCatalogSO / PlacementArchetypeTypeKeywordsSO / KeywordCodeGenerator）

class KeywordIdentifierUtil extends RefCounted:
	enum IdentifierPolicy {
		KEYWORD_ENTRY = 0,
		TYPE_NAME = 1,
		NONE = 2,
	}

	const CSHARP_KEYWORDS := {
		"abstract": true, "as": true, "base": true, "bool": true, "break": true, "byte": true,
		"case": true, "catch": true, "char": true, "checked": true, "class": true, "const": true,
		"continue": true, "decimal": true, "default": true, "delegate": true, "do": true, "double": true,
		"else": true, "enum": true, "event": true, "explicit": true, "extern": true, "false": true,
		"finally": true, "fixed": true, "float": true, "for": true, "foreach": true, "goto": true,
		"if": true, "implicit": true, "in": true, "int": true, "interface": true, "internal": true,
		"is": true, "lock": true, "long": true, "namespace": true, "new": true, "null": true,
		"object": true, "operator": true, "out": true, "override": true, "params": true, "private": true,
		"protected": true, "public": true, "readonly": true, "ref": true, "return": true, "sbyte": true,
		"sealed": true, "short": true, "sizeof": true, "stackalloc": true, "static": true, "string": true,
		"struct": true, "switch": true, "this": true, "throw": true, "true": true, "try": true,
		"typeof": true, "uint": true, "ulong": true, "unchecked": true, "unsafe": true, "ushort": true,
		"using": true, "virtual": true, "void": true, "volatile": true, "while": true,
	}

	static func validate_identifier(ident: String, policy: int = IdentifierPolicy.KEYWORD_ENTRY) -> Dictionary:
		if ident.is_empty():
			return {"ok": false, "reason": "标识符不能为空。"}
		var c0 := ident.unicode_at(0)
		var first_ok := (c0 >= 65 and c0 <= 90) or (c0 >= 97 and c0 <= 122) or c0 == 95
		if not first_ok:
			return {"ok": false, "reason": "「%s」必须以字母或下划线开头。" % ident}
		for i in range(1, ident.length()):
			var c := ident.unicode_at(i)
			var ok := (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
			if not ok:
				return {"ok": false, "reason": "「%s」只能包含字母 / 数字 / 下划线。" % ident}
		if CSHARP_KEYWORDS.has(ident):
			return {"ok": false, "reason": "「%s」是保留关键字，不能作为标识符。" % ident}
		if policy == IdentifierPolicy.KEYWORD_ENTRY and ident in ["None", "NONE"]:
			return {"ok": false, "reason": "「None」是生成枚举的保留 0 值，不能作为 keyword 名。"}
		return {"ok": true, "reason": ""}

	static func is_valid_identifier(ident: String, policy: int = IdentifierPolicy.KEYWORD_ENTRY) -> bool:
		return bool(validate_identifier(ident, policy).get("ok", false))

	static func is_pascal_case(ident: String) -> bool:
		if ident.is_empty():
			return false
		var c0 := ident.unicode_at(0)
		return c0 >= 65 and c0 <= 90

	static func validate_namespace(ns: String) -> Dictionary:
		if ns.strip_edges().is_empty():
			return {"ok": false, "reason": "namespace 不能为空。"}
		var segments := ns.strip_edges().split(".")
		for seg in segments:
			var res := validate_identifier(seg, IdentifierPolicy.TYPE_NAME)
			if not bool(res.get("ok", false)):
				return {"ok": false, "reason": "namespace 段非法：%s" % str(res.get("reason", ""))}
		return {"ok": true, "reason": ""}


class KeywordEntry extends Resource:
	@export var stable_id: int = 0
	@export var entry_name: String = ""
	@export var display_name: String = ""
	@export var description: String = ""
	@export var deprecated: bool = false
	@export var icon_id: String = ""
	## 透明值仅用于兼容旧目录；未配置时按类型 ID 取默认色。
	@export var display_color: Color = Color(0, 0, 0, 0)
	@export var value_type: int = GDCoreTypes.KeywordValueType.STRING

	func get_display_color() -> Color:
		return display_color if display_color.a > 0.0 else default_display_color(stable_id)

	static func default_display_color(type_id: int) -> Color:
		var hues: Array[float] = [0.56, 0.12, 0.33, 0.74, 0.02, 0.46, 0.83, 0.22]
		return Color.from_hsv(hues[absi(type_id) % hues.size()], 0.52, 0.9)

	func assign_stable_id(id: int) -> void:
		stable_id = id

	func set_entry_name(p_name: String) -> void:
		entry_name = p_name

	func set_deprecated(v: bool) -> void:
		deprecated = v

	func editor_set_metadata(p_display_name: String, p_description: String) -> void:
		display_name = p_display_name
		description = p_description

	func editor_set_icon_id(p_icon_id: String) -> void:
		icon_id = p_icon_id


class KeywordCatalogSnapshotEntry extends Resource:
	@export var stable_id: int = 0
	@export var entry_name: String = ""

	func _init(p_id: int = 0, p_name: String = "") -> void:
		stable_id = p_id
		entry_name = p_name


class KeywordCatalogRes extends Resource:
	@export var next_stable_id: int = 1
	@export var enum_namespace: String = ""
	@export var enum_type_name: String = ""
	@export var generated_file_path: String = ""
	@export var rewrite_scan_root: String = "res://"
	## 不用内部类做数组元素类型，否则 Godot 存盘后会丢掉条目。
	@export var entries: Array = []
	@export var last_generated_snapshot: Array = []
	@export var default_entry_value_type: int = GDCoreTypes.KeywordValueType.STRING

	var generated_output_folder: String:
		get:
			if generated_file_path.strip_edges().is_empty():
				return ""
			return generated_file_path.replace("\\", "/").get_base_dir()

	func editor_set_generated_output_folder(folder: String) -> void:
		var clean := folder.strip_edges().replace("\\", "/").trim_suffix("/")
		if clean.is_empty():
			generated_file_path = ""
		else:
			var tname := enum_type_name.strip_edges() if not enum_type_name.strip_edges().is_empty() else (
				resource_name if not resource_name.is_empty() else "GeneratedKeywords"
			)
			generated_file_path = "%s/%s.g.gd" % [clean, tname]
		emit_changed()

	func add_entry(p_name: String, p_display_name: String = "", p_description: String = "") -> KeywordEntry:
		if p_name.strip_edges().is_empty():
			GDGameLogger.log_error_d("[KeywordCatalogRes] AddEntry: name 不能为空。")
			return null
		var clean_name := p_name.strip_edges()
		if find_active_by_name(clean_name) != null:
			GDGameLogger.log_error_d("[KeywordCatalogRes] AddEntry: 已存在同名 active entry「%s」。" % clean_name)
			return null
		var dep := find_deprecated_by_name(clean_name)
		if dep != null:
			dep.set_deprecated(false)
			dep.set_entry_name(clean_name)
			dep.editor_set_metadata(p_display_name, p_description)
			emit_changed()
			return dep
		if not KeywordIdentifierUtil.is_valid_identifier(clean_name, KeywordIdentifierUtil.IdentifierPolicy.KEYWORD_ENTRY):
			GDGameLogger.log_error_d("[KeywordCatalogRes] AddEntry: 「%s」不是合法标识符。" % clean_name)
			return null
		var entry := GDKeywordEntryRes.new()
		entry.value_type = default_entry_value_type
		entry.set_entry_name(clean_name)
		entry.editor_set_metadata(p_display_name, p_description)
		var id := editor_allocate_next_stable_id()
		entry.assign_stable_id(id)
		entry.display_color = KeywordEntry.default_display_color(id)
		entries.append(entry)
		emit_changed()
		return entry

	func remove_entry(p_name: String) -> bool:
		var entry := find_active_by_name(p_name)
		if entry == null:
			GDGameLogger.log_warning("[KeywordCatalogRes] RemoveEntry: 找不到 active entry「%s」。" % p_name)
			return false
		entry.set_deprecated(true)
		emit_changed()
		return true

	func rename_entry(old_name: String, new_name: String) -> bool:
		if new_name.strip_edges().is_empty():
			GDGameLogger.log_error_d("[KeywordCatalogRes] RenameEntry: newName 不能为空。")
			return false
		var clean_new := new_name.strip_edges()
		var entry := find_active_by_name(old_name)
		if entry == null:
			GDGameLogger.log_error_d("[KeywordCatalogRes] RenameEntry: 找不到「%s」。" % old_name)
			return false
		if clean_new != old_name and find_active_by_name(clean_new) != null:
			GDGameLogger.log_error_d("[KeywordCatalogRes] RenameEntry: 目标名「%s」已存在。" % clean_new)
			return false
		if not KeywordIdentifierUtil.is_valid_identifier(clean_new, KeywordIdentifierUtil.IdentifierPolicy.KEYWORD_ENTRY):
			GDGameLogger.log_error_d("[KeywordCatalogRes] RenameEntry: 「%s」不是合法标识符。" % clean_new)
			return false
		entry.set_entry_name(clean_new)
		emit_changed()
		return true

	func regenerate() -> bool:
		var ok := KeywordCodeGenerator.generate(self, generated_file_path, enum_namespace)
		if ok:
			var snap: Array[KeywordCatalogSnapshotEntry] = []
			for e in entries:
				if e != null and not e.deprecated:
					snap.append(GDKeywordSnapshotRes.new(e.stable_id, e.entry_name))
			last_generated_snapshot = snap
			emit_changed()
		return ok

	func is_enum_up_to_date() -> bool:
		var snap_map: Dictionary = {}
		for s in last_generated_snapshot:
			if s != null:
				snap_map[s.stable_id] = s.entry_name
		var active_map: Dictionary = {}
		for e in entries:
			if e != null and not e.deprecated:
				active_map[e.stable_id] = e.entry_name
		if snap_map.size() != active_map.size():
			return false
		for k in active_map.keys():
			if not snap_map.has(k) or snap_map[k] != active_map[k]:
				return false
		return true

	func editor_allocate_next_stable_id() -> int:
		var id := maxi(1, next_stable_id)
		next_stable_id = maxi(next_stable_id, id + 1)
		emit_changed()
		return id

	func editor_reconcile_next_stable_id_after_load() -> void:
		var max_id := 0
		for e in entries:
			if e != null and e.stable_id > max_id:
				max_id = e.stable_id
		next_stable_id = maxi(next_stable_id, max_id + 1)

	func find_active_by_name(p_name: String) -> KeywordEntry:
		for e in entries:
			if e != null and not e.deprecated and e.entry_name == p_name:
				return e
		return null

	func find_deprecated_by_name(p_name: String) -> KeywordEntry:
		for e in entries:
			if e != null and e.deprecated and e.entry_name == p_name:
				return e
		return null

	func find_any_by_name(p_name: String) -> KeywordEntry:
		for e in entries:
			if e != null and e.entry_name == p_name:
				return e
		return null

	func find_active_by_stable_id(p_stable_id: int) -> KeywordEntry:
		for e in entries:
			if e != null and not e.deprecated and e.stable_id == p_stable_id:
				return e
		return null


class KeywordCodeGenerator extends RefCounted:
	static func generate(catalog: KeywordCatalogRes, output_path: String, enum_ns: String = "") -> bool:
		if catalog == null:
			GDGameLogger.log_error_d("[KeywordCodeGenerator] catalog 为空。")
			return false
		var target_path := output_path.strip_edges() if not output_path.strip_edges().is_empty() else catalog.generated_file_path.strip_edges()
		if target_path.is_empty():
			GDGameLogger.log_error_d("[KeywordCodeGenerator] outputPath 为空。")
			return false
		var type_name := catalog.enum_type_name.strip_edges()
		if type_name.is_empty():
			GDGameLogger.log_error_d("[KeywordCodeGenerator] EnumTypeName 未设置。")
			return false
		var type_check := KeywordIdentifierUtil.validate_identifier(type_name, KeywordIdentifierUtil.IdentifierPolicy.TYPE_NAME)
		if not bool(type_check.get("ok", false)):
			GDGameLogger.log_error_d("[KeywordCodeGenerator] EnumTypeName 非法：%s" % str(type_check.get("reason", "")))
			return false
		var ns := enum_ns.strip_edges() if not enum_ns.strip_edges().is_empty() else catalog.enum_namespace.strip_edges()
		if ns.is_empty():
			GDGameLogger.log_error_d("[KeywordCodeGenerator] enumNamespace 为空。")
			return false
		var ns_check := KeywordIdentifierUtil.validate_namespace(ns)
		if not bool(ns_check.get("ok", false)):
			GDGameLogger.log_error_d("[KeywordCodeGenerator] enumNamespace 非法：%s" % str(ns_check.get("reason", "")))
			return false

		var active: Array[KeywordEntry] = []
		for e in catalog.entries:
			if e != null and not e.deprecated:
				active.append(e)

		var errors: Array[String] = []
		_validate_entries(active, errors)
		if not errors.is_empty():
			for err in errors:
				GDGameLogger.log_error_d("[KeywordCodeGenerator] %s" % err)
			return false

		var content := build_code_text(type_name, ns, active, target_path.ends_with(".cs"))
		var abs_path := ProjectSettings.globalize_path(target_path) if target_path.begins_with("res://") else target_path
		var base_dir := abs_path.get_base_dir()
		if not base_dir.is_empty() and not DirAccess.dir_exists_absolute(base_dir):
			DirAccess.make_dir_recursive_absolute(base_dir)
		var f := FileAccess.open(abs_path, FileAccess.WRITE)
		if f == null:
			GDGameLogger.log_error_d("[KeywordCodeGenerator] 写入失败：%s" % target_path)
			return false
		f.store_string(content)
		f.close()
		return true

	static func build_code_text(type_name: String, ns: String, active: Array[KeywordEntry], csharp_format: bool = false) -> String:
		if csharp_format:
			return _build_csharp_text(type_name, ns, active)
		var lines: PackedStringArray = PackedStringArray()
		lines.append("# <auto-generated>")
		lines.append("# 本文件由 KeywordCatalog 重新生成，请勿手工修改。")
		lines.append("# namespace: %s" % ns)
		lines.append("# stable-id-map:")
		if active.is_empty():
			lines.append("#   (empty)")
		else:
			for e in active:
				lines.append("#   %d = %s   # valueType=%s" % [
					e.stable_id,
					e.entry_name,
					GDCoreTypes.keyword_value_type_name(e.value_type)
				])
		lines.append("# </auto-generated>")
		lines.append("extends RefCounted")
		lines.append("")
		lines.append("enum %s {" % type_name)
		lines.append("\tNONE = 0,")
		for e in active:
			lines.append("\t%s = %d," % [e.entry_name, e.stable_id])
		lines.append("}")
		lines.append("")
		lines.append("const KNOWN_IDS := {")
		lines.append("\t\"None\": 0,")
		for e in active:
			lines.append("\t\"%s\": %d," % [e.entry_name, e.stable_id])
		lines.append("}")
		return "\n".join(lines) + "\n"

	static func _build_csharp_text(type_name: String, ns: String, active: Array[KeywordEntry]) -> String:
		var lines: PackedStringArray = PackedStringArray()
		lines.append("// <auto-generated>")
		lines.append("// 本文件由 KeywordCatalog Inspector「重新生成」生成，请勿手工修改。")
		lines.append("// stable-id-map:")
		if active.is_empty():
			lines.append("//   (empty)")
		else:
			for e in active:
				lines.append("//   %d = %s   // valueType=%s" % [
					e.stable_id,
					e.entry_name,
					GDCoreTypes.keyword_value_type_name(e.value_type)
				])
		lines.append("// </auto-generated>")
		lines.append("")
		lines.append("namespace %s" % ns)
		lines.append("{")
		lines.append("    public enum %s" % type_name)
		lines.append("    {")
		lines.append("        None = 0,")
		for e in active:
			lines.append("        %s = %d," % [e.entry_name, e.stable_id])
		lines.append("    }")
		lines.append("}")
		return "\n".join(lines) + "\n"

	static func _validate_entries(active: Array[KeywordEntry], errors: Array[String]) -> void:
		var seen_ids: Dictionary = {}
		var seen_names: Dictionary = {}
		for i in range(active.size()):
			var e := active[i]
			if e.entry_name.is_empty():
				errors.append("Entry #%d 缺 Name。" % i)
				continue
			if not KeywordIdentifierUtil.is_valid_identifier(e.entry_name, KeywordIdentifierUtil.IdentifierPolicy.KEYWORD_ENTRY):
				errors.append("Entry #%d Name「%s」非法（需合法标识符且不得为 None）。" % [i, e.entry_name])
			if e.stable_id <= 0:
				errors.append("Entry #%d(%s) stableId 非法（必须 > 0）。" % [i, e.entry_name])
			if seen_ids.has(e.stable_id):
				errors.append("Entry #%d(%s) stableId=%d 重复。" % [i, e.entry_name, e.stable_id])
			seen_ids[e.stable_id] = true
			if seen_names.has(e.entry_name):
				errors.append("Entry #%d Name「%s」重复。" % [i, e.entry_name])
			seen_names[e.entry_name] = true
