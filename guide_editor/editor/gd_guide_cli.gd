@tool
class_name GDGuideCli
extends RefCounted

## 新手引导编辑器 CLI（对应 GuideCli）：guide.list / guide.validate / guide.create。

static func commands() -> Dictionary:
	return {
		"guide.list": {"run": _cmd_list, "summary": "列出引导图（内存注册表，或 --library <path> 指定的引导库）"},
		"guide.validate": {"run": _cmd_validate, "summary": "校验引导图 (--asset <path|graphId> 或第一个位置参数)"},
		"guide.create": {"run": _cmd_create, "summary": "新建引导图骨架 (--id --name [--asset res://...tres])"},
	}

static func run(command: String, args: Array = []) -> String:
	return GDCliRoot.dispatch(commands(), command, args)

static func _asset_arg(ctx: GDCliRoot.CliContext) -> String:
	var asset := ctx.get_option("asset")
	return asset if not asset.is_empty() or ctx.positionals.is_empty() else ctx.positionals[0]

static func _cmd_list(ctx: GDCliRoot.CliContext) -> String:
	var lib_path := ctx.get_option("library")
	var graphs: Array = GDGuideEditing.find_all_graphs()
	if not lib_path.is_empty():
		var lib := ResourceLoader.load(lib_path) as GDGuideLibraryRes if ResourceLoader.exists(lib_path) else null
		if lib == null:
			return ctx.fail("library.missing", lib_path)
		graphs = lib.graphs
	var rows: Array = []
	for g in graphs:
		if g is GDGuideGraphRes:
			rows.append({"id": g.graph_id, "name": g.display_name, "path": g.resource_path})
	return ctx.ok({"graphs": rows})

static func _cmd_validate(ctx: GDCliRoot.CliContext) -> String:
	var asset_path := _asset_arg(ctx)
	var graph: GDGuideGraphRes = null
	if not asset_path.is_empty() and ResourceLoader.exists(asset_path):
		graph = ResourceLoader.load(asset_path) as GDGuideGraphRes
	elif asset_path.is_valid_int():
		graph = GDGuideEditing.find_graph(asset_path.to_int())
	if graph == null:
		return ctx.fail("asset.missing", asset_path if not asset_path.is_empty() else "缺少 --asset")
	var report := GDGuideValidation.GuideGraphValidator.validate(graph)
	var issues: Array = []
	for i in report.issues:
		issues.append({"severity": "Error" if i.is_error else "Warning", "code": i.code, "message": i.message, "nodeId": i.node_id})
	return GDCliRoot.result(ctx.command, not report.has_errors, {
		"path": asset_path,
		"errors": report.error_count,
		"warnings": report.warning_count,
		"issues": issues,
	})

static func _cmd_create(ctx: GDCliRoot.CliContext) -> String:
	var id_raw := ctx.get_option("id")
	if not id_raw.is_valid_int() or id_raw.to_int() <= 0:
		return ctx.fail("id.invalid", "--id 必须是正整数")
	var gid := id_raw.to_int()
	var gname := ctx.get_option("name").strip_edges()
	if gname.is_empty():
		return ctx.fail("name.missing", "缺少 --name")
	if GDGuideEditing.find_graph(gid) != null:
		return ctx.fail("id.duplicate", "图 Id 已存在")
	var graph := GDGuideGraphRes.new()
	graph.set_graph_id(gid)
	graph.set_display_name(gname)
	graph.add_default_skeleton()
	var asset_path := _asset_arg(ctx)
	if not asset_path.is_empty():
		if not (asset_path.begins_with("res://") or asset_path.begins_with("user://")):
			return ctx.fail("asset.invalid", "资产路径必须以 res:// 或 user:// 开头")
		var err := GDDocument.new(graph).save(asset_path)
		if err != OK:
			return ctx.fail("save.failed", "保存失败：%s（%s）" % [asset_path, error_string(err)])
	GDGuideEditing.register_in_memory_graph(graph)
	return ctx.ok({"path": asset_path})
