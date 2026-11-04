@tool
class_name GDSceneEditorCli
extends RefCounted

## SceneEditor CLI 主入口（13 条标准命令 + sceneeditor.* 别名 + SceneEditorBootstrapper 脚手架）
## 对应 SceneEditorCli + SceneEditorBootstrapper

const ALL_COMMANDS := [
	"help",
	"keywords.list", "keywords.add", "keywords.rename", "keywords.remove",
	"keywords.regenerate", "keywords.validate",
	"layout.list", "layout.add", "layout.remove", "layout.preview-all-min-max",
	"scaffold.create-module", "scaffold.create-manufactured", "scaffold.add-example-logic",
]

class CliContext extends RefCounted:
	var catalog_path: String = ""
	var entry_name: String = ""
	var from_name: String = ""
	var to_name: String = ""
	var value_type: String = ""
	var layout_path: String = ""
	var archetype_stable_id_raw: String = ""
	var pos_raw: String = ""
	var rot_raw: String = ""
	var scale_raw: String = ""
	var level_raw: String = ""
	var instance_id_raw: String = ""
	var mode_raw: String = ""
	var dry_run: bool = false
	var quiet: bool = false
	var extras: Dictionary = {}


static func run(command: String, args: Array = []) -> String:
	var ctx := _parse_args(args if args != null else [])
	match command:
		"keywords.list":
			return _cmd_keywords_list(ctx)
		"keywords.add":
			return _cmd_keywords_add(ctx)
		"keywords.rename":
			return _cmd_keywords_rename(ctx)
		"keywords.remove":
			return _cmd_keywords_remove(ctx)
		"keywords.regenerate":
			return _cmd_keywords_regenerate(ctx)
		"keywords.validate":
			return _cmd_keywords_validate(ctx)
		"layout.list", "sceneeditor.layout.list":
			return _cmd_layout_list(ctx)
		"layout.add", "sceneeditor.layout.add":
			return _cmd_layout_add(ctx)
		"layout.remove", "sceneeditor.layout.remove":
			return _cmd_layout_remove(ctx)
		"layout.preview-all-min-max", "sceneeditor.layout.preview-all-min-max":
			return _cmd_layout_preview_all_min_max(ctx)
		"scaffold.create-module", "sceneeditor.scaffold.create-module":
			return _cmd_scaffold_create_module(ctx)
		"scaffold.create-manufactured", "sceneeditor.scaffold.create-manufactured":
			return _cmd_scaffold_create_manufactured(ctx)
		"scaffold.add-example-logic", "sceneeditor.scaffold.add-example-logic":
			return _cmd_scaffold_add_example_logic(ctx)
		_:
			return _err(
				command,
				"unknown-command",
				"未知命令：%s（合法集合：keywords.{list|add|rename|remove|regenerate|validate}；layout.{list|add|remove|preview-all-min-max}；scaffold.{create-module|create-manufactured|add-example-logic}；sceneeditor.* 同名）" % command
			)

static func load_catalog(asset_path: String) -> GDKeywordCatalogSystem.KeywordCatalogRes:
	if asset_path == null or asset_path.strip_edges().is_empty():
		return null
	var p := asset_path.strip_edges()
	if not ResourceLoader.exists(p):
		return null
	return ResourceLoader.load(p) as GDKeywordCatalogSystem.KeywordCatalogRes

static func load_layout(asset_path: String) -> GDLevelSceneRes:
	if asset_path == null or asset_path.strip_edges().is_empty():
		return null
	var p := asset_path.strip_edges()
	if not ResourceLoader.exists(p):
		return null
	return ResourceLoader.load(p) as GDLevelSceneRes

# ── keywords.* ──

static func _cmd_keywords_list(ctx: CliContext) -> String:
	const CMD := "keywords.list"
	if ctx.catalog_path.strip_edges().is_empty():
		return _err(CMD, "catalog-required", "缺少 --catalog")
	var catalog := load_catalog(ctx.catalog_path)
	if catalog == null:
		return _err(CMD, "catalog-not-found", "catalog 不存在：%s" % ctx.catalog_path)
	var list: Array = []
	for e in catalog.entries:
		if e == null:
			continue
		list.append({
			"stableId": e.stable_id,
			"name": e.entry_name,
			"valueType": GDCoreTypes.keyword_value_type_name(e.value_type),
			"deprecated": e.deprecated,
		})
	return _ok(CMD, {
		"catalog": ctx.catalog_path,
		"count": list.size(),
		"entries": list,
	})

static func _cmd_keywords_add(ctx: CliContext) -> String:
	const CMD := "keywords.add"
	if ctx.catalog_path.strip_edges().is_empty():
		return _err(CMD, "catalog-required", "缺少 --catalog")
	if ctx.entry_name.strip_edges().is_empty():
		return _err(CMD, "name-required", "缺少 --name")
	var catalog := load_catalog(ctx.catalog_path)
	if catalog == null:
		return _err(CMD, "catalog-not-found", "catalog 不存在：%s" % ctx.catalog_path)
	var ename := ctx.entry_name.strip_edges()
	var parsed_vt := GDCoreTypes.parse_keyword_value_type(ctx.value_type)
	var vt := int(parsed_vt.get("value", GDCoreTypes.KeywordValueType.INT))
	var vt_warn := str(parsed_vt.get("warn", ""))

	if catalog.find_active_by_name(ename) != null:
		return _err(CMD, "dup-name", "已存在同名 active entry：%s" % ename)
	var dep := catalog.find_deprecated_by_name(ename)
	if dep == null and not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(ename, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.KEYWORD_ENTRY):
		return _err(CMD, "invalid-identifier", "「%s」不是合法标识符（或 None）。" % ename)

	if ctx.dry_run:
		var predicted_id := dep.stable_id if dep != null else catalog.next_stable_id
		var payload := {
			"dryRun": true,
			"stableId": predicted_id,
			"name": ename,
			"valueType": GDCoreTypes.keyword_value_type_name(vt),
		}
		if not vt_warn.is_empty():
			payload["warn"] = vt_warn
		return _ok(CMD, payload)

	var after := catalog.add_entry(ename)
	if after == null:
		return _err(CMD, "invalid-identifier", "未能添加「%s」。" % ename)
	if not ctx.value_type.strip_edges().is_empty() and vt_warn.is_empty():
		after.value_type = vt
	if not catalog.resource_path.is_empty():
		ResourceSaver.save(catalog, catalog.resource_path)
	var out := {
		"stableId": after.stable_id,
		"name": after.entry_name,
		"valueType": GDCoreTypes.keyword_value_type_name(after.value_type),
	}
	if not vt_warn.is_empty():
		out["warn"] = vt_warn
	return _ok(CMD, out)

static func _cmd_keywords_rename(ctx: CliContext) -> String:
	const CMD := "keywords.rename"
	if ctx.catalog_path.strip_edges().is_empty():
		return _err(CMD, "catalog-required", "缺少 --catalog")
	if ctx.from_name.strip_edges().is_empty():
		return _err(CMD, "from-required", "缺少 --from")
	if ctx.to_name.strip_edges().is_empty():
		return _err(CMD, "to-required", "缺少 --to")
	var catalog := load_catalog(ctx.catalog_path)
	if catalog == null:
		return _err(CMD, "catalog-not-found", "catalog 不存在：%s" % ctx.catalog_path)
	var from_s := ctx.from_name.strip_edges()
	var to_s := ctx.to_name.strip_edges()
	var cur := catalog.find_active_by_name(from_s)
	if cur == null:
		return _err(CMD, "not-found", "找不到 active entry：%s" % from_s)
	if from_s == to_s:
		return _ok(CMD, {"from": from_s, "to": to_s, "stableId": cur.stable_id})
	if catalog.find_active_by_name(to_s) != null:
		return _err(CMD, "collision", "目标名已存在 active entry：%s" % to_s)
	if not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(to_s, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.KEYWORD_ENTRY):
		return _err(CMD, "invalid-identifier", "「%s」不是合法标识符（或 None）。" % to_s)
	if ctx.dry_run:
		return _ok(CMD, {"dryRun": true, "from": from_s, "to": to_s, "stableId": cur.stable_id})
	catalog.rename_entry(from_s, to_s)
	if not catalog.resource_path.is_empty():
		ResourceSaver.save(catalog, catalog.resource_path)
	return _ok(CMD, {"from": from_s, "to": to_s, "stableId": cur.stable_id})

static func _cmd_keywords_remove(ctx: CliContext) -> String:
	const CMD := "keywords.remove"
	if ctx.catalog_path.strip_edges().is_empty():
		return _err(CMD, "catalog-required", "缺少 --catalog")
	if ctx.entry_name.strip_edges().is_empty():
		return _err(CMD, "name-required", "缺少 --name")
	var catalog := load_catalog(ctx.catalog_path)
	if catalog == null:
		return _err(CMD, "catalog-not-found", "catalog 不存在：%s" % ctx.catalog_path)
	var ename := ctx.entry_name.strip_edges()
	if catalog.find_active_by_name(ename) == null:
		return _err(CMD, "not-found", "找不到 active entry：%s" % ename)
	if ctx.dry_run:
		return _ok(CMD, {"dryRun": true, "name": ename, "deprecated": true})
	catalog.remove_entry(ename)
	if not catalog.resource_path.is_empty():
		ResourceSaver.save(catalog, catalog.resource_path)
	var dep := catalog.find_any_by_name(ename)
	return _ok(CMD, {"name": ename, "deprecated": dep != null and dep.deprecated})

static func _cmd_keywords_regenerate(ctx: CliContext) -> String:
	const CMD := "keywords.regenerate"
	if ctx.catalog_path.strip_edges().is_empty():
		return _err(CMD, "catalog-required", "缺少 --catalog")
	var catalog := load_catalog(ctx.catalog_path)
	if catalog == null:
		return _err(CMD, "catalog-not-found", "catalog 不存在：%s" % ctx.catalog_path)
	if catalog.enum_type_name.strip_edges().is_empty() or catalog.enum_namespace.strip_edges().is_empty() or catalog.generated_file_path.strip_edges().is_empty():
		return _err(CMD, "enum-metadata-empty", "请先设置 enumTypeName / enumNamespace / generatedFilePath")
	var active_count := 0
	for e in catalog.entries:
		if e != null and not e.deprecated:
			active_count += 1
	if ctx.dry_run:
		return _ok(CMD, {
			"dryRun": true,
			"generatedFilePath": catalog.generated_file_path,
			"entriesCount": active_count,
		})
	if not catalog.regenerate():
		return _err(CMD, "regenerate-failed", "生成失败：%s" % catalog.generated_file_path)
	if not catalog.resource_path.is_empty():
		ResourceSaver.save(catalog, catalog.resource_path)
	return _ok(CMD, {
		"generatedFilePath": catalog.generated_file_path,
		"entriesCount": active_count,
	})

static func _cmd_keywords_validate(ctx: CliContext) -> String:
	const CMD := "keywords.validate"
	if ctx.catalog_path.strip_edges().is_empty():
		return _err(CMD, "catalog-required", "缺少 --catalog")
	var catalog := load_catalog(ctx.catalog_path)
	if catalog == null:
		return _err(CMD, "catalog-not-found", "catalog 不存在：%s" % ctx.catalog_path)
	var issues: Array = []
	if catalog.enum_type_name.strip_edges().is_empty() or catalog.enum_namespace.strip_edges().is_empty() or catalog.generated_file_path.strip_edges().is_empty():
		issues.append({"code": "enum-metadata-empty"})
	var active_ids: Dictionary = {}
	var all_names: Dictionary = {}
	for e in catalog.entries:
		if e == null:
			continue
		var n: String = e.entry_name
		if all_names.has(n):
			issues.append({"code": "duplicate-name", "name": n})
		else:
			all_names[n] = true
		if not e.deprecated:
			if e.stable_id <= 0:
				issues.append({"code": "invalid-stableId", "entry": n, "stableId": e.stable_id})
			if active_ids.has(e.stable_id) and e.stable_id > 0:
				issues.append({"code": "duplicate-stableId", "stableId": e.stable_id})
			active_ids[e.stable_id] = true
		if not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_pascal_case(n) or n == "None" or not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(n, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.KEYWORD_ENTRY):
			issues.append({"code": "invalid-name", "name": n})
	if issues.is_empty():
		return _ok(CMD, {"issues": issues})
	return JSON.stringify({
		"ok": false,
		"command": CMD,
		"code": "validation-failed",
		"message": "catalog 校验失败：%d 个问题" % issues.size(),
		"issues": issues,
	})

# ── layout.* ──

static func _cmd_layout_list(ctx: CliContext) -> String:
	const CMD := "layout.list"
	if ctx.layout_path.strip_edges().is_empty():
		return _err(CMD, "layout-required", "缺少 --layout")
	var so := load_layout(ctx.layout_path)
	if so == null:
		return _err(CMD, "not-found", "layout 不存在：%s" % ctx.layout_path)
	var list: Array = []
	for p in so.placements:
		if p == null:
			continue
		list.append({
			"instanceId": p.instance_id,
			"archetypeStableId": p.archetype_stable_id,
			"posX": p.position.x,
			"posY": p.position.y,
			"posZ": p.position.z,
			"initialLevel": p.initial_level,
		})
	return _ok(CMD, {
		"layout": ctx.layout_path,
		"placements": list,
		"count": list.size(),
	})

static func _cmd_layout_add(ctx: CliContext) -> String:
	const CMD := "layout.add"
	if ctx.layout_path.strip_edges().is_empty():
		return _err(CMD, "layout-required", "缺少 --layout")
	var so := load_layout(ctx.layout_path)
	if so == null:
		return _err(CMD, "not-found", "layout 不存在：%s" % ctx.layout_path)
	if ctx.archetype_stable_id_raw.strip_edges().is_empty():
		return _err(CMD, "invalid-archetype", "缺少或无效的 --archetype")
	if not ctx.archetype_stable_id_raw.strip_edges().is_valid_int():
		return _err(CMD, "invalid-archetype", "无法解析 stableId：%s" % ctx.archetype_stable_id_raw)
	var arch_id := ctx.archetype_stable_id_raw.strip_edges().to_int()
	var pos := _parse_vector3(ctx.pos_raw, Vector3.ZERO)
	var rot := _parse_vector3(ctx.rot_raw, Vector3.ZERO)
	var sc := _parse_vector3(ctx.scale_raw, Vector3.ONE)
	var lv := 1
	if not ctx.level_raw.strip_edges().is_empty() and ctx.level_raw.strip_edges().is_valid_int():
		var parsed_lv := ctx.level_raw.strip_edges().to_int()
		if parsed_lv >= GDPlacementData.PlacementLevel.MIN_LEVEL:
			lv = parsed_lv
	if ctx.dry_run:
		return _ok(CMD, {
			"dryRun": true,
			"archetypeStableId": arch_id,
			"instanceId": maxi(GDLevelSceneRes.INSTANCE_ID_START, so.next_instance_id),
		})
	var res := so.editor_try_add_placement(arch_id, pos, rot, sc, lv)
	if not bool(res.get("ok", false)):
		return _err(CMD, "allocate-failed", str(res.get("error", "分配 InstanceId 失败")))
	if not so.resource_path.is_empty():
		ResourceSaver.save(so, so.resource_path)
	return _ok(CMD, {"instanceId": int(res.get("instance_id", 0))})

static func _cmd_layout_remove(ctx: CliContext) -> String:
	const CMD := "layout.remove"
	if ctx.layout_path.strip_edges().is_empty():
		return _err(CMD, "layout-required", "缺少 --layout")
	var so := load_layout(ctx.layout_path)
	if so == null:
		return _err(CMD, "not-found", "layout 不存在：%s" % ctx.layout_path)
	if ctx.instance_id_raw.strip_edges().is_empty():
		return _err(CMD, "instance-required", "缺少 --instance")
	if not ctx.instance_id_raw.strip_edges().is_valid_int() or ctx.instance_id_raw.strip_edges().to_int() <= 0:
		return _err(CMD, "instance-invalid", "--instance 必须是正整数 instanceId：%s" % ctx.instance_id_raw)
	var inst_id := ctx.instance_id_raw.strip_edges().to_int()
	if ctx.dry_run:
		var found := so.editor_try_get_placement(inst_id)
		if not bool(found.get("ok", false)):
			return _err(CMD, "not-found", "找不到 instanceId：%d" % inst_id)
		return _ok(CMD, {"dryRun": true, "removed": inst_id})
	if not so.editor_remove_placement(inst_id):
		return _err(CMD, "not-found", "找不到 instanceId：%d" % inst_id)
	if not so.resource_path.is_empty():
		ResourceSaver.save(so, so.resource_path)
	return _ok(CMD, {"removed": inst_id})

static func _cmd_layout_preview_all_min_max(ctx: CliContext) -> String:
	const CMD := "layout.preview-all-min-max"
	if ctx.layout_path.strip_edges().is_empty():
		return _err(CMD, "layout-required", "缺少 --layout")
	var so := load_layout(ctx.layout_path)
	if so == null:
		return _err(CMD, "not-found", "layout 不存在：%s" % ctx.layout_path)
	var mode := ctx.mode_raw.strip_edges().to_lower() if not ctx.mode_raw.strip_edges().is_empty() else "default"
	return _ok(CMD, {
		"switched": so.placements.size(),
		"mode": mode,
		"note": "Phase 2: 优先预览Prefab，否则默认态 VisualAtom（运行时等级模型由项目建筑表驱动）",
	})

# ── scaffold.* ──

static func _cmd_scaffold_create_module(ctx: CliContext) -> String:
	const CMD := "scaffold.create-module"
	var module_name := str(ctx.extras.get("module", "")).strip_edges()
	if module_name.is_empty():
		return _err(CMD, "module-required", "缺少 --module <name>")
	var resource_root := str(ctx.extras.get("resource-root", "")).strip_edges()
	var scenes_root := str(ctx.extras.get("scenes-root", "")).strip_edges()
	var scripts_root := str(ctx.extras.get("scripts-root", "")).strip_edges()
	if resource_root.is_empty() or scenes_root.is_empty() or scripts_root.is_empty():
		return _err(CMD, "root-required", "缺少必填路径：--resource-root <path> --scenes-root <path> --scripts-root <path>")

	var result := create_module_scaffold(module_name, resource_root, scenes_root, scripts_root, ctx.dry_run)
	if not bool(result.get("ok", false)):
		return _err(CMD, str(result.get("error_code", "create-failed")), str(result.get("error_message", "unknown")))
	return _ok(CMD, {
		"moduleName": module_name,
		"resourceRoot": resource_root,
		"scenesRoot": scenes_root,
		"scriptsRoot": scripts_root,
		"createdCount": (result.get("created_assets", []) as Array).size(),
		"createdAssets": result.get("created_assets", []),
		"warnings": result.get("warnings", []),
		"dryRun": ctx.dry_run,
	})

static func _cmd_scaffold_create_manufactured(ctx: CliContext) -> String:
	const CMD := "scaffold.create-manufactured"
	var template_path := str(ctx.extras.get("template", "")).strip_edges()
	var output_path := str(ctx.extras.get("output", "")).strip_edges()
	var arch_asset := str(ctx.extras.get("archetype-asset", "")).strip_edges()
	if ctx.archetype_stable_id_raw.strip_edges().is_empty():
		return _err(CMD, "archetype-required", "缺少 --archetype <stableId>")
	if not ctx.archetype_stable_id_raw.strip_edges().is_valid_int():
		return _err(CMD, "invalid-archetype", "--archetype 非数字：%s" % ctx.archetype_stable_id_raw)
	var arch_id := ctx.archetype_stable_id_raw.strip_edges().to_int()
	if template_path.is_empty():
		return _err(CMD, "template-required", "缺少 --template <prefabPath>")
	if output_path.is_empty():
		return _err(CMD, "output-required", "缺少 --output <prefabPath>")
	if ctx.dry_run:
		return _ok(CMD, {
			"dryRun": true,
			"archetypeStableId": arch_id,
			"template": template_path,
			"output": output_path,
		})
	var res := create_manufactured_prefab(arch_id, output_path, arch_asset)
	if not bool(res.get("ok", false)):
		return _err(CMD, str(res.get("error_code", "create-failed")), str(res.get("error_message", "unknown")))
	return _ok(CMD, {"outputPath": output_path, "archetypeStableId": arch_id})

static func _cmd_scaffold_add_example_logic(ctx: CliContext) -> String:
	const CMD := "scaffold.add-example-logic"
	var module_name := str(ctx.extras.get("module", "")).strip_edges()
	if module_name.is_empty():
		return _err(CMD, "module-required", "缺少 --module <name>")
	var scripts_root := str(ctx.extras.get("scripts-root", "")).strip_edges()
	if scripts_root.is_empty():
		return _err(CMD, "root-required", "缺少必填路径：--scripts-root <path>")
	if ctx.dry_run:
		return _ok(CMD, {"dryRun": true, "moduleName": module_name})
	var logic_dir := "%s/Logic" % scripts_root.trim_suffix("/")
	GDCliRoot.AtomCreator.ensure_dir(logic_dir)
	var model_path := "%s/%sExampleModel.gd" % [logic_dir, module_name]
	var f := FileAccess.open(model_path, FileAccess.WRITE)
	if f != null:
		f.store_string("extends RefCounted\n# Example model for %s\n" % module_name)
		f.close()
	return _ok(CMD, {"moduleName": module_name, "createdFiles": [model_path]})

static func create_module_scaffold(
	module_name: String,
	resource_root: String,
	scenes_root: String,
	scripts_root: String,
	dry_run: bool = false
) -> Dictionary:
	if not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(module_name, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.TYPE_NAME):
		return {"ok": false, "error_code": "invalid-module-name", "error_message": "模块名不合法：%s" % module_name}

	var r_root := resource_root.trim_suffix("/")
	var s_root := scenes_root.trim_suffix("/")
	var c_root := scripts_root.trim_suffix("/")

	var layout_path := "%s/LevelScene_%s.tres" % [r_root, module_name]
	var kw_path := "%s/Config/Keywords/PlacementArchetypeTypeKeywords_%s.tres" % [r_root, module_name]
	var arch_folder := "%s/Archetypes/SampleArchetype" % r_root
	var arch_path := "%s/PlacementArchetype_%s_Sample.tres" % [arch_folder, module_name]
	var prefab_path := "%s/Entity_%s_Sample.tscn" % [arch_folder, module_name]
	var editor_scene_path := "%s/Editor_%s_Layout.tscn" % [s_root, module_name]
	var logic_scene_path := "%s/%sLogic.tscn" % [s_root, module_name]
	var art_scene_path := "%s/%sArt.tscn" % [s_root, module_name]

	var created: Array[String] = [
		layout_path, kw_path, arch_path, prefab_path,
		editor_scene_path, logic_scene_path, art_scene_path,
	]
	if dry_run:
		return {"ok": true, "created_assets": created, "warnings": []}

	for d in [
		"%s/Config/Keywords" % r_root,
		arch_folder,
		s_root,
		"%s/Logic" % c_root,
		"%s/Data" % c_root,
		"%s/Keywords" % c_root,
	]:
		GDCliRoot.AtomCreator.ensure_dir(d)

	# 创建场景模板
	for sp in [editor_scene_path, logic_scene_path, art_scene_path]:
		if not ResourceLoader.exists(sp):
			var root_n := Node3D.new()
			root_n.name = sp.get_file().get_basename()
			var ps := PackedScene.new()
			ps.pack(root_n)
			ResourceSaver.save(ps, sp)
			root_n.free()

	# 创建类型目录
	var kw := GDKeywordCatalogRes.new()
	kw.enum_namespace = "%s.Keywords" % module_name
	kw.enum_type_name = "%sArchetypeType" % module_name
	kw.add_entry("Building", "基础建筑", "")
	ResourceSaver.save(kw, kw_path)

	# 创建示例 Entity Prefab 与 Archetype
	create_manufactured_prefab(1000, prefab_path, "")
	var arch := GDLevelArchetypeRes.new()
	arch.editor_init_with_addresses(1000, "示例建筑", prefab_path.get_file().get_basename(), "")
	arch.editor_set_archetype_type_stable_id(1)
	ResourceSaver.save(arch, arch_path)

	# 创建 LevelSceneRes
	var layout := GDLevelSceneRes.new()
	layout.display_name = module_name
	layout.editor_bind_scenes(editor_scene_path, art_scene_path, logic_scene_path)
	layout.editor_bind_archetype_type_keywords(kw)
	layout.editor_add_archetype(arch)
	layout.editor_add_placement(1000, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 1)
	ResourceSaver.save(layout, layout_path)

	return {"ok": true, "created_assets": created, "warnings": []}

static func create_manufactured_prefab(_arch_stable_id: int, output_path: String, arch_asset_path: String) -> Dictionary:
	GDCliRoot.AtomCreator.ensure_dir(output_path.get_base_dir())
	var root := GDEntityNode.new()
	root.name = output_path.get_file().get_basename()
	var visual := GDVisualAtom.new()
	visual.name = "VisualAtom"
	root.editor_register_atom(visual)
	var interact := GDInteractableAtom.new()
	interact.name = "InteractableAtom"
	root.editor_register_atom(interact)

	var ps := PackedScene.new()
	var err := ps.pack(root)
	root.free()
	if err != OK:
		return {"ok": false, "error_code": "pack-failed", "error_message": "PackedScene.pack 失败"}
	err = ResourceSaver.save(ps, output_path)
	if err != OK:
		return {"ok": false, "error_code": "save-failed", "error_message": "ResourceSaver.save 失败：%s" % output_path}

	var addr := output_path.get_file().get_basename()
	GDArchetypeRes.register_prefab_address(addr, output_path)
	if not arch_asset_path.is_empty() and ResourceLoader.exists(arch_asset_path):
		var arch := ResourceLoader.load(arch_asset_path) as GDArchetypeRes
		if arch != null:
			arch.editor_set_prefab_addresses(addr, arch.preview_prefab_address)
			ResourceSaver.save(arch, arch_asset_path)
	return {"ok": true, "output_path": output_path}

# ── Helpers ──

static func _parse_vector3(s: String, fallback: Vector3) -> Vector3:
	if s == null or s.strip_edges().is_empty():
		return fallback
	var parts := s.split(",")
	if parts.size() != 3:
		return fallback
	var p0 := parts[0].strip_edges()
	var p1 := parts[1].strip_edges()
	var p2 := parts[2].strip_edges()
	if not p0.is_valid_float() or not p1.is_valid_float() or not p2.is_valid_float():
		return fallback
	return Vector3(p0.to_float(), p1.to_float(), p2.to_float())

static func _parse_args(args: Array) -> CliContext:
	var ctx := CliContext.new()
	var i := 0
	while i < args.size():
		var key := str(args[i])
		if key == "--dry-run":
			ctx.dry_run = true
			i += 1
			continue
		if key == "--quiet":
			ctx.quiet = true
			i += 1
			continue
		var val := str(args[i + 1]) if i + 1 < args.size() else ""
		match key:
			"--catalog":
				ctx.catalog_path = val
				i += 1
			"--name":
				ctx.entry_name = val
				i += 1
			"--from":
				ctx.from_name = val
				i += 1
			"--to":
				ctx.to_name = val
				i += 1
			"--valueType":
				ctx.value_type = val
				i += 1
			"--layout":
				ctx.layout_path = val
				i += 1
			"--archetype":
				ctx.archetype_stable_id_raw = val
				i += 1
			"--pos":
				ctx.pos_raw = val
				i += 1
			"--rot":
				ctx.rot_raw = val
				i += 1
			"--scale":
				ctx.scale_raw = val
				i += 1
			"--level":
				ctx.level_raw = val
				i += 1
			"--instance":
				ctx.instance_id_raw = val
				i += 1
			"--mode":
				ctx.mode_raw = val
				i += 1
			_:
				if key.begins_with("--") and not val.begins_with("--"):
					ctx.extras[key.substr(2)] = val
					i += 1
		i += 1
	return ctx

static func _ok(command: String, payload: Dictionary) -> String:
	var p := payload.duplicate()
	p["ok"] = true
	p["command"] = command
	return JSON.stringify(p)

static func _err(command: String, code: String, msg: String) -> String:
	return JSON.stringify({
		"ok": false,
		"command": command,
		"code": code,
		"message": msg,
	})
