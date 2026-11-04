@tool
class_name GDLevelCsvExporter
extends RefCounted

## 将 GDLevelSceneRes.placements 导出为 CSV（UTF-8 BOM，Excel 友好）
## 对应 TimiMiniGame.SceneEditor.Editor.Scene.LevelScenePlacementsCsvExporter

const HEADER := (
	"instanceId,archetypeStableId,archetypeName,name,displayName," +
	"posX,posY,posZ,rotX,rotY,rotZ,scaleX,scaleY,scaleZ,initialLevel," +
	"attributeOverrides"
)

static func build_csv(layout: GDLevelSceneRes) -> String:
	if layout == null:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append(HEADER)
	if layout.placements == null or layout.placements.is_empty():
		return "\n".join(lines) + "\n"

	var arch_names := _build_archetype_name_lookup(layout.archetypes)
	var rows: Array[GDPlacementData.PlacementInstance] = []
	for p in layout.placements:
		if p != null:
			rows.append(p)

	rows.sort_custom(func(a: GDPlacementData.PlacementInstance, b: GDPlacementData.PlacementInstance) -> bool:
		return a.instance_id < b.instance_id
	)

	for p in rows:
		var arch_name: String = str(arch_names.get(p.archetype_stable_id, ""))
		var cols: PackedStringArray = PackedStringArray([
			escape_csv_field(str(p.instance_id)),
			escape_csv_field(str(p.archetype_stable_id)),
			escape_csv_field(arch_name),
			escape_csv_field(p.instance_name if p.instance_name != null else ""),
			escape_csv_field(p.display_name if p.display_name != null else ""),
			escape_csv_field(_format_float(p.position.x)),
			escape_csv_field(_format_float(p.position.y)),
			escape_csv_field(_format_float(p.position.z)),
			escape_csv_field(_format_float(p.euler_angles.x)),
			escape_csv_field(_format_float(p.euler_angles.y)),
			escape_csv_field(_format_float(p.euler_angles.z)),
			escape_csv_field(_format_float(p.scale.x)),
			escape_csv_field(_format_float(p.scale.y)),
			escape_csv_field(_format_float(p.scale.z)),
			escape_csv_field(str(p.initial_level)),
			escape_csv_field(_format_attribute_overrides(p.attribute_overrides)),
		])
		lines.append(",".join(cols))

	return "\n".join(lines) + "\n"

static func try_write_to_file(layout: GDLevelSceneRes, file_path: String) -> Dictionary:
	if layout == null:
		return {"ok": false, "error": GDSceneEditorL10n.l("LevelSceneSO 为 null。")}
	if file_path == null or file_path.strip_edges().is_empty():
		return {"ok": false, "error": GDSceneEditorL10n.l("未选择导出路径。")}
	var csv := build_csv(layout)
	var abs_path := ProjectSettings.globalize_path(file_path) if file_path.begins_with("res://") or file_path.begins_with("user://") else file_path
	var dir_path := abs_path.get_base_dir()
	if not dir_path.is_empty() and not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "无法打开文件写入：%s" % file_path}
	# 写入 UTF-8 BOM (EF BB BF) + 内容
	var bom := PackedByteArray([0xEF, 0xBB, 0xBF])
	f.store_buffer(bom)
	f.store_Buffer_or_string(csv) if f.has_method("store_Buffer_or_string") else f.store_buffer(csv.to_utf8_buffer())
	f.close()
	return {"ok": true, "error": ""}

static func _build_archetype_name_lookup(archetypes: Array) -> Dictionary:
	var map: Dictionary = {}
	if archetypes == null:
		return map
	for a in archetypes:
		if a == null or not (a is GDArchetypeRes):
			continue
		var arch := a as GDArchetypeRes
		var label := arch.display_name if not arch.display_name.is_empty() else (
			arch.resource_name if not arch.resource_name.is_empty() else "Archetype"
		)
		map[arch.stable_id] = label
	return map

static func _format_attribute_overrides(overrides: Array) -> String:
	if overrides == null or overrides.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for ov in overrides:
		if ov == null or not (ov is GDPlacementData.PlacementAttributeOverride):
			continue
		var item := ov as GDPlacementData.PlacementAttributeOverride
		parts.append("%s:%d:%s" % [item.tag, item.value_type, _format_override_value(item)])
	return "|".join(parts)

static func _format_override_value(ov: GDPlacementData.PlacementAttributeOverride) -> String:
	match ov.value_type:
		GDCoreTypes.KeywordValueType.INT:
			return str(ov.int_value)
		GDCoreTypes.KeywordValueType.FLOAT:
			return _format_float(ov.float_value)
		GDCoreTypes.KeywordValueType.STRING:
			return ov.string_value if ov.string_value != null else ""
		GDCoreTypes.KeywordValueType.BOOL:
			return "true" if ov.bool_value else "false"
		_:
			return ""

static func _format_float(val: float) -> String:
	if is_equal_approx(val, roundf(val)):
		return str(roundi(val))
	return "%.6f" % val

static func escape_csv_field(val: String) -> String:
	if val == null or val.is_empty():
		return ""
	if val.contains(",") or val.contains("\"") or val.contains("\r") or val.contains("\n"):
		return "\"%s\"" % val.replace("\"", "\"\"")
	return val
