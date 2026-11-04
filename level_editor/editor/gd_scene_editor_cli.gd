@tool
class_name GDSceneEditorCli
extends RefCounted

## SceneEditor CLI（keywords.* / layout.* / scaffold.*，并接受 sceneeditor.* 前缀别名）+ SceneEditorBootstrapper 脚手架
## 对应 SceneEditorCli + SceneEditorBootstrapper

const ALIAS_PREFIX := "sceneeditor."

static func commands() -> Dictionary:
	return {
		"keywords.list": {"run": _cmd_keywords_list, "summary": "列出关键字目录条目 (--catalog)"},
		"keywords.add": {"run": _cmd_keywords_add, "summary": "新增关键字条目 (--catalog --name [--valueType])"},
		"keywords.rename": {"run": _cmd_keywords_rename, "summary": "重命名关键字条目 (--catalog --from --to)"},
		"keywords.remove": {"run": _cmd_keywords_remove, "summary": "软删除关键字条目 (--catalog --name)"},
		"keywords.regenerate": {"run": _cmd_keywords_regenerate, "summary": "按目录重新生成枚举代码 (--catalog)"},
		"keywords.validate": {"run": _cmd_keywords_validate, "summary": "校验关键字目录 (--catalog)"},
		"layout.list": {"run": _cmd_layout_list, "summary": "列出关卡摆放实例 (--layout)"},
		"layout.add": {"run": _cmd_layout_add, "summary": "新增摆放实例 (--layout --archetype [--pos --rot --scale --level])"},
		"layout.remove": {"run": _cmd_layout_remove, "summary": "删除摆放实例 (--layout --instance)"},
		"layout.preview-all-min-max": {"run": _cmd_layout_preview_all_min_max, "summary": "预览全部实例的最低 / 最高等级 (--layout [--mode])"},
		"scaffold.create-module": {"run": _cmd_scaffold_create_module, "summary": "创建关卡模块脚手架 (--module --resource-root --scenes-root --scripts-root)"},
		"scaffold.create-manufactured": {"run": _cmd_scaffold_create_manufactured, "summary": "创建制成品 Prefab (--archetype --template --output [--archetype-asset])"},
		"scaffold.add-example-logic": {"run": _cmd_scaffold_add_example_logic, "summary": "生成示例逻辑脚本 (--module --scripts-root)"},
	}

static func command_names() -> PackedStringArray:
	return PackedStringArray(commands().keys())

## sceneeditor.layout.list -> layout.list
static func resolve_alias(command: String) -> String:
	return command.trim_prefix(ALIAS_PREFIX)

static func run(command: String, args: Array = []) -> String:
	return GDCliRoot.dispatch(commands(), resolve_alias(command), args)

static func load_catalog(asset_path: String) -> GDKeywordCatalogSystem.KeywordCatalogRes:
	var p := asset_path.strip_edges()
	return ResourceLoader.load(p) as GDKeywordCatalogSystem.KeywordCatalogRes if not p.is_empty() and ResourceLoader.exists(p) else null

static func load_layout(asset_path: String) -> GDLevelSceneRes:
	var p := asset_path.strip_edges()
	return ResourceLoader.load(p) as GDLevelSceneRes if not p.is_empty() and ResourceLoader.exists(p) else null

## --catalog 指向的目录；失败时返回错误 JSON（String）。
static func _open_catalog(ctx: GDCliRoot.CliContext) -> Variant:
	var path := ctx.get_option("catalog")
	if path.strip_edges().is_empty():
		return ctx.fail("catalog-required", "缺少 --catalog")
	var catalog := load_catalog(path)
	return catalog if catalog != null else ctx.fail("catalog-not-found", "catalog 不存在：%s" % path)

## --layout 指向的关卡；失败时返回错误 JSON（String）。
static func _open_layout(ctx: GDCliRoot.CliContext) -> Variant:
	var path := ctx.get_option("layout")
	if path.strip_edges().is_empty():
		return ctx.fail("layout-required", "缺少 --layout")
	var layout := load_layout(path)
	return layout if layout != null else ctx.fail("not-found", "layout 不存在：%s" % path)

static func _save(res: Resource) -> void:
	if not res.resource_path.is_empty():
		ResourceSaver.save(res, res.resource_path)

static func _is_entry_identifier(entry_name: String) -> bool:
	return GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(entry_name, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.KEYWORD_ENTRY)

static func _has_enum_metadata(catalog: GDKeywordCatalogSystem.KeywordCatalogRes) -> bool:
	return not (catalog.enum_type_name.strip_edges().is_empty() or catalog.enum_namespace.strip_edges().is_empty() or catalog.generated_file_path.strip_edges().is_empty())

# ── keywords.* ──

static func _cmd_keywords_list(ctx: GDCliRoot.CliContext) -> String:
	var catalog = _open_catalog(ctx)
	if catalog is String:
		return catalog
	var list: Array = []
	for e in catalog.entries:
		if e != null:
			list.append({
				"stableId": e.stable_id,
				"name": e.entry_name,
				"valueType": GDCoreTypes.keyword_value_type_name(e.value_type),
				"deprecated": e.deprecated,
			})
	return ctx.ok({"catalog": ctx.get_option("catalog"), "count": list.size(), "entries": list})

static func _cmd_keywords_add(ctx: GDCliRoot.CliContext) -> String:
	var catalog = _open_catalog(ctx)
	if catalog is String:
		return catalog
	var ename := ctx.get_option("name").strip_edges()
	if ename.is_empty():
		return ctx.fail("name-required", "缺少 --name")
	var raw_type := ctx.get_option("valueType")
	var parsed_vt := GDCoreTypes.parse_keyword_value_type(raw_type)
	var vt := int(parsed_vt.get("value", GDCoreTypes.KeywordValueType.INT))
	var vt_warn := str(parsed_vt.get("warn", ""))
	var warn := {"warn": vt_warn} if not vt_warn.is_empty() else {}

	if catalog.find_active_by_name(ename) != null:
		return ctx.fail("dup-name", "已存在同名 active entry：%s" % ename)
	var dep = catalog.find_deprecated_by_name(ename)
	if dep == null and not _is_entry_identifier(ename):
		return ctx.fail("invalid-identifier", "「%s」不是合法标识符（或 None）。" % ename)

	if ctx.has_flag("dry-run"):
		var predicted_id: int = dep.stable_id if dep != null else catalog.next_stable_id
		return ctx.ok(warn.merged({"dryRun": true, "stableId": predicted_id, "name": ename, "valueType": GDCoreTypes.keyword_value_type_name(vt)}))

	var after = catalog.add_entry(ename)
	if after == null:
		return ctx.fail("invalid-identifier", "未能添加「%s」。" % ename)
	if not raw_type.strip_edges().is_empty() and vt_warn.is_empty():
		after.value_type = vt
	_save(catalog)
	return ctx.ok(warn.merged({"stableId": after.stable_id, "name": after.entry_name, "valueType": GDCoreTypes.keyword_value_type_name(after.value_type)}))

static func _cmd_keywords_rename(ctx: GDCliRoot.CliContext) -> String:
	var catalog = _open_catalog(ctx)
	if catalog is String:
		return catalog
	var from_s := ctx.get_option("from").strip_edges()
	var to_s := ctx.get_option("to").strip_edges()
	if from_s.is_empty():
		return ctx.fail("from-required", "缺少 --from")
	if to_s.is_empty():
		return ctx.fail("to-required", "缺少 --to")
	var cur = catalog.find_active_by_name(from_s)
	if cur == null:
		return ctx.fail("not-found", "找不到 active entry：%s" % from_s)
	var payload := {"from": from_s, "to": to_s, "stableId": cur.stable_id}
	if from_s == to_s:
		return ctx.ok(payload)
	if catalog.find_active_by_name(to_s) != null:
		return ctx.fail("collision", "目标名已存在 active entry：%s" % to_s)
	if not _is_entry_identifier(to_s):
		return ctx.fail("invalid-identifier", "「%s」不是合法标识符（或 None）。" % to_s)
	if ctx.has_flag("dry-run"):
		return ctx.ok(payload.merged({"dryRun": true}))
	catalog.rename_entry(from_s, to_s)
	_save(catalog)
	return ctx.ok(payload)

static func _cmd_keywords_remove(ctx: GDCliRoot.CliContext) -> String:
	var catalog = _open_catalog(ctx)
	if catalog is String:
		return catalog
	var ename := ctx.get_option("name").strip_edges()
	if ename.is_empty():
		return ctx.fail("name-required", "缺少 --name")
	if catalog.find_active_by_name(ename) == null:
		return ctx.fail("not-found", "找不到 active entry：%s" % ename)
	if ctx.has_flag("dry-run"):
		return ctx.ok({"dryRun": true, "name": ename, "deprecated": true})
	catalog.remove_entry(ename)
	_save(catalog)
	var dep = catalog.find_any_by_name(ename)
	return ctx.ok({"name": ename, "deprecated": dep != null and dep.deprecated})

static func _cmd_keywords_regenerate(ctx: GDCliRoot.CliContext) -> String:
	var catalog = _open_catalog(ctx)
	if catalog is String:
		return catalog
	if not _has_enum_metadata(catalog):
		return ctx.fail("enum-metadata-empty", "请先设置 enumTypeName / enumNamespace / generatedFilePath")
	var payload := {
		"generatedFilePath": catalog.generated_file_path,
		"entriesCount": catalog.entries.filter(func(e: Variant) -> bool: return e != null and not e.deprecated).size(),
	}
	if ctx.has_flag("dry-run"):
		return ctx.ok(payload.merged({"dryRun": true}))
	if not catalog.regenerate():
		return ctx.fail("regenerate-failed", "生成失败：%s" % catalog.generated_file_path)
	_save(catalog)
	return ctx.ok(payload)

static func _cmd_keywords_validate(ctx: GDCliRoot.CliContext) -> String:
	var catalog = _open_catalog(ctx)
	if catalog is String:
		return catalog
	var issues: Array = []
	if not _has_enum_metadata(catalog):
		issues.append({"code": "enum-metadata-empty"})
	var active_ids: Dictionary = {}
	var all_names: Dictionary = {}
	for e in catalog.entries:
		if e == null:
			continue
		var n: String = e.entry_name
		if all_names.has(n):
			issues.append({"code": "duplicate-name", "name": n})
		all_names[n] = true
		if not e.deprecated:
			if e.stable_id <= 0:
				issues.append({"code": "invalid-stableId", "entry": n, "stableId": e.stable_id})
			elif active_ids.has(e.stable_id):
				issues.append({"code": "duplicate-stableId", "stableId": e.stable_id})
			active_ids[e.stable_id] = true
		if not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_pascal_case(n) or n == "None" or not _is_entry_identifier(n):
			issues.append({"code": "invalid-name", "name": n})
	if issues.is_empty():
		return ctx.ok({"issues": issues})
	return ctx.fail("validation-failed", "catalog 校验失败：%d 个问题" % issues.size(), {"issues": issues})

# ── layout.* ──

static func _cmd_layout_list(ctx: GDCliRoot.CliContext) -> String:
	var layout = _open_layout(ctx)
	if layout is String:
		return layout
	var list: Array = []
	for p in layout.placements:
		if p != null:
			list.append({
				"instanceId": p.instance_id,
				"archetypeStableId": p.archetype_stable_id,
				"posX": p.position.x,
				"posY": p.position.y,
				"posZ": p.position.z,
				"initialLevel": p.initial_level,
			})
	return ctx.ok({"layout": ctx.get_option("layout"), "placements": list, "count": list.size()})

static func _cmd_layout_add(ctx: GDCliRoot.CliContext) -> String:
	var layout = _open_layout(ctx)
	if layout is String:
		return layout
	var arch_raw := ctx.get_option("archetype").strip_edges()
	if arch_raw.is_empty():
		return ctx.fail("invalid-archetype", "缺少或无效的 --archetype")
	if not arch_raw.is_valid_int():
		return ctx.fail("invalid-archetype", "无法解析 stableId：%s" % arch_raw)
	var arch_id := arch_raw.to_int()
	var level_raw := ctx.get_option("level").strip_edges()
	var lv := level_raw.to_int() if level_raw.is_valid_int() and level_raw.to_int() >= GDPlacementData.PlacementLevel.MIN_LEVEL else 1
	if ctx.has_flag("dry-run"):
		return ctx.ok({
			"dryRun": true,
			"archetypeStableId": arch_id,
			"instanceId": maxi(GDLevelSceneRes.INSTANCE_ID_START, layout.next_instance_id),
		})
	var res: Dictionary = layout.editor_try_add_placement(
		arch_id,
		_parse_vector3(ctx.get_option("pos"), Vector3.ZERO),
		_parse_vector3(ctx.get_option("rot"), Vector3.ZERO),
		_parse_vector3(ctx.get_option("scale"), Vector3.ONE),
		lv
	)
	if not bool(res.get("ok", false)):
		return ctx.fail("allocate-failed", str(res.get("error", "分配 InstanceId 失败")))
	_save(layout)
	return ctx.ok({"instanceId": int(res.get("instance_id", 0))})

static func _cmd_layout_remove(ctx: GDCliRoot.CliContext) -> String:
	var layout = _open_layout(ctx)
	if layout is String:
		return layout
	var inst_raw := ctx.get_option("instance").strip_edges()
	if inst_raw.is_empty():
		return ctx.fail("instance-required", "缺少 --instance")
	if not inst_raw.is_valid_int() or inst_raw.to_int() <= 0:
		return ctx.fail("instance-invalid", "--instance 必须是正整数 instanceId：%s" % ctx.get_option("instance"))
	var inst_id := inst_raw.to_int()
	if ctx.has_flag("dry-run"):
		if not bool(layout.editor_try_get_placement(inst_id).get("ok", false)):
			return ctx.fail("not-found", "找不到 instanceId：%d" % inst_id)
		return ctx.ok({"dryRun": true, "removed": inst_id})
	if not layout.editor_remove_placement(inst_id):
		return ctx.fail("not-found", "找不到 instanceId：%d" % inst_id)
	_save(layout)
	return ctx.ok({"removed": inst_id})

static func _cmd_layout_preview_all_min_max(ctx: GDCliRoot.CliContext) -> String:
	var layout = _open_layout(ctx)
	if layout is String:
		return layout
	var mode := ctx.get_option("mode").strip_edges().to_lower()
	return ctx.ok({
		"switched": layout.placements.size(),
		"mode": mode if not mode.is_empty() else "default",
		"note": "Phase 2: 优先预览Prefab，否则默认态 VisualAtom（运行时等级模型由项目建筑表驱动）",
	})

# ── scaffold.* ──

static func _cmd_scaffold_create_module(ctx: GDCliRoot.CliContext) -> String:
	var module_name := ctx.get_option("module").strip_edges()
	if module_name.is_empty():
		return ctx.fail("module-required", "缺少 --module <name>")
	var resource_root := ctx.get_option("resource-root").strip_edges()
	var scenes_root := ctx.get_option("scenes-root").strip_edges()
	var scripts_root := ctx.get_option("scripts-root").strip_edges()
	if resource_root.is_empty() or scenes_root.is_empty() or scripts_root.is_empty():
		return ctx.fail("root-required", "缺少必填路径：--resource-root <path> --scenes-root <path> --scripts-root <path>")

	var result := create_module_scaffold(module_name, resource_root, scenes_root, scripts_root, ctx.has_flag("dry-run"))
	if not bool(result.get("ok", false)):
		return ctx.fail(str(result.get("error_code", "create-failed")), str(result.get("error_message", "unknown")))
	return ctx.ok({
		"moduleName": module_name,
		"resourceRoot": resource_root,
		"scenesRoot": scenes_root,
		"scriptsRoot": scripts_root,
		"createdCount": (result.get("created_assets", []) as Array).size(),
		"createdAssets": result.get("created_assets", []),
		"warnings": result.get("warnings", []),
		"dryRun": ctx.has_flag("dry-run"),
	})

static func _cmd_scaffold_create_manufactured(ctx: GDCliRoot.CliContext) -> String:
	var template_path := ctx.get_option("template").strip_edges()
	var output_path := ctx.get_option("output").strip_edges()
	var arch_asset := ctx.get_option("archetype-asset").strip_edges()
	if ctx.get_option("archetype").strip_edges().is_empty():
		return ctx.fail("archetype-required", "缺少 --archetype <stableId>")
	if not ctx.get_option("archetype").strip_edges().is_valid_int():
		return ctx.fail("invalid-archetype", "--archetype 非数字：%s" % ctx.get_option("archetype"))
	var arch_id := ctx.get_option("archetype").strip_edges().to_int()
	if template_path.is_empty():
		return ctx.fail("template-required", "缺少 --template <prefabPath>")
	if output_path.is_empty():
		return ctx.fail("output-required", "缺少 --output <prefabPath>")
	if ctx.has_flag("dry-run"):
		return ctx.ok({
			"dryRun": true,
			"archetypeStableId": arch_id,
			"template": template_path,
			"output": output_path,
		})
	var res := create_manufactured_prefab(arch_id, output_path, arch_asset)
	if not bool(res.get("ok", false)):
		return ctx.fail(str(res.get("error_code", "create-failed")), str(res.get("error_message", "unknown")))
	return ctx.ok({"outputPath": output_path, "archetypeStableId": arch_id})

static func _cmd_scaffold_add_example_logic(ctx: GDCliRoot.CliContext) -> String:
	var module_name := ctx.get_option("module").strip_edges()
	if module_name.is_empty():
		return ctx.fail("module-required", "缺少 --module <name>")
	var scripts_root := ctx.get_option("scripts-root").strip_edges()
	if scripts_root.is_empty():
		return ctx.fail("root-required", "缺少必填路径：--scripts-root <path>")
	if ctx.has_flag("dry-run"):
		return ctx.ok({"dryRun": true, "moduleName": module_name})
	var logic_dir := "%s/Logic" % scripts_root.trim_suffix("/")
	GDCliRoot.AtomCreator.ensure_dir(logic_dir)
	var model_path := "%s/%sExampleModel.gd" % [logic_dir, module_name]
	var f := FileAccess.open(model_path, FileAccess.WRITE)
	if f != null:
		f.store_string("extends RefCounted\n# Example model for %s\n" % module_name)
		f.close()
	return ctx.ok({"moduleName": module_name, "createdFiles": [model_path]})

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
	if s.strip_edges().is_empty():
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
