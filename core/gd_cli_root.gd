@tool
class_name GDCliRoot
extends RefCounted

## CLI 基础设施（对应 CliRoot / CliContext / CliResult）+ Core 原子创建器命令（AtomCreator / AtomCommands）。
## 每个模块 CLI 暴露 commands() -> {命令名: {"run": Callable(CliContext) -> String, "summary": String}}，
## 由 dispatch() 统一解析参数并分发；命令清单从表推导（见 GdesignerToolsCli）。

## 永远按布尔开关解析、不吞掉后一个参数的选项。
const FLAG_ONLY := ["dry-run", "quiet"]

## 一次命令调用：命令名 + 位置参数 + `--key value` / `--key=value` 选项 + 布尔开关。
class CliContext extends RefCounted:
	var command: String = ""
	var positionals: Array[String] = []
	var options: Dictionary = {} # String -> String
	var flags: Dictionary = {} # String -> true

	func get_option(key: String, fallback: String = "") -> String:
		return str(options.get(key, fallback))

	func has_flag(key: String) -> bool:
		return flags.has(key)

	func ok(payload: Dictionary = {}) -> String:
		return GDCliRoot.result(command, true, payload)

	func fail(code: String, message: String, payload: Dictionary = {}) -> String:
		return GDCliRoot.fail(command, code, message, payload)


## Core atom.* 命令沿用的结果形状：{"ok", "code", "message", ...data}。
class CliResult extends RefCounted:
	var ok: bool = false
	var code: String = ""
	var message: String = ""
	var data: Dictionary = {}

	static func success(payload: Dictionary = {}, msg: String = "ok") -> CliResult:
		var r := CliResult.new()
		r.ok = true
		r.code = "OK"
		r.message = msg
		r.data = payload
		return r

	static func fail(err_code: String, err_msg: String, payload: Dictionary = {}) -> CliResult:
		var r := CliResult.new()
		r.code = err_code
		r.message = err_msg
		r.data = payload
		return r

	func to_json_line() -> String:
		var out := {"ok": ok, "code": code, "message": message}
		out.merge(data, true)
		return JSON.stringify(out)


## 运行时额外注册的命令（项目自定义扩展）；handler 接收 CliContext，返回 JSON 字符串或 CliResult。
static var _registry: Dictionary = {}

static func register_command(cmd_name: String, handler: Callable, summary: String = "") -> void:
	_registry[cmd_name] = {"run": handler, "summary": summary}

## Core 模块命令表：atom.* + register_command 注册的命令。
static func commands() -> Dictionary:
	var table := {
		"atom.create": {"run": _cmd_atom_create, "summary": "创建 AtomBase 脚本与 AtomTemplateRes 模板资产 (--name --type --script-dir --template-dir)"},
		"atom.list-templates": {"run": _cmd_atom_list_templates, "summary": "列出工程内全部 AtomTemplateRes 模板"},
	}
	table.merge(_registry, true)
	return table

## 在命令表中查找并执行命令；未知命令返回 unknown-command。
static func dispatch(table: Dictionary, command: String, args: Array) -> String:
	if not table.has(command):
		return fail(command, "unknown-command", "未知命令：%s（输入 help 查看全部命令）" % command)
	var ctx := parse_args(args)
	ctx.command = command
	var out: Variant = (table[command]["run"] as Callable).call(ctx)
	return out.to_json_line() if out is CliResult else str(out)

static func parse_args(args: Array) -> CliContext:
	var ctx := CliContext.new()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		i += 1
		if not a.begins_with("--"):
			ctx.positionals.append(a)
			continue
		var key := a.substr(2)
		var eq := key.find("=")
		if eq > 0:
			ctx.options[key.substr(0, eq)] = key.substr(eq + 1)
		elif key not in FLAG_ONLY and i < args.size() and not str(args[i]).begins_with("--"):
			ctx.options[key] = str(args[i])
			i += 1
		else:
			ctx.flags[key] = true
	return ctx

static func split_command_line(input: String) -> Array[String]:
	var parts: Array[String] = []
	var current := ""
	var in_quotes := false
	for ch in input:
		if ch == "\"":
			in_quotes = not in_quotes
		elif not in_quotes and (ch == " " or ch == "\t"):
			if not current.is_empty():
				parts.append(current)
				current = ""
		else:
			current += ch
	if not current.is_empty():
		parts.append(current)
	return parts

## 模块命令统一的 JSON 结果：{"ok", "command", ...payload}。
static func result(command: String, ok: bool, payload: Dictionary = {}) -> String:
	var out := {"ok": ok, "command": command}
	out.merge(payload, true)
	return JSON.stringify(out)

static func fail(command: String, code: String, message: String, payload: Dictionary = {}) -> String:
	var out := {"code": code, "message": message}
	out.merge(payload, true)
	return result(command, false, out)


## AtomCreator 逻辑（脚本 + AtomTemplateRes 生成）
class AtomCreator extends RefCounted:
	const DEFAULT_TEMP_DIR := "res://addons/gdesigner_tools/config/atom_temps"

	static func create_atom(req: Dictionary) -> Dictionary:
		var script_name := str(req.get("script_name", "")).strip_edges()
		var display_name := str(req.get("display_name", script_name)).strip_edges()
		var description := str(req.get("description", "")).strip_edges()
		var atom_type := int(req.get("atom_type", GDCoreTypes.AtomType.LOGIC))
		var script_dir := str(req.get("script_dir", "")).strip_edges().trim_suffix("/")
		var template_dir := str(req.get("template_dir", DEFAULT_TEMP_DIR)).strip_edges().trim_suffix("/")

		if not is_valid_type_name(script_name):
			return {"ok": false, "error_code": "BAD_ARG", "error_message": "脚本名不是合法标识符：%s" % script_name}
		if script_dir.is_empty():
			return {"ok": false, "error_code": "BAD_ARG", "error_message": "缺少脚本落盘目录（--script-dir）"}
		if template_dir.is_empty():
			return {"ok": false, "error_code": "BAD_ARG", "error_message": "缺少模板落盘目录（--template-dir）"}

		ensure_dir(script_dir)
		ensure_dir(template_dir)

		var script_path := "%s/%s.gd" % [script_dir, script_name]
		var template_path := "%s/AtomTemplate_%s.tres" % [template_dir, script_name]
		if ResourceLoader.exists(template_path):
			return {"ok": false, "error_code": "EXISTS", "error_message": "模板已存在：%s" % template_path}

		if not FileAccess.file_exists(script_path):
			var f := FileAccess.open(script_path, FileAccess.WRITE)
			if f == null:
				return {"ok": false, "error_code": "IO_ERR", "error_message": "无法写入脚本：%s" % script_path}
			f.store_string(_build_atom_gdscript(script_name, display_name, description))
			f.close()

		var loaded_script := load(script_path) as Script
		var tpl := GDEntityAtomSystem.AtomTemplateRes.new()
		tpl.write_metadata(
			display_name if not display_name.is_empty() else script_name,
			description,
			atom_type,
			null,
			loaded_script,
			script_name
		)
		var err := ResourceSaver.save(tpl, template_path)
		if err != OK:
			return {"ok": false, "error_code": "SAVE_ERR", "error_message": "保存模板失败：%s" % template_path}

		return {
			"ok": true,
			"script_path": script_path,
			"asset_path": template_path,
			"needs_recompile": false,
		}

	static func is_valid_type_name(s: String) -> bool:
		return s.is_valid_ascii_identifier()

	static func ensure_dir(res_dir: String) -> void:
		var abs_dir := ProjectSettings.globalize_path(res_dir)
		if not DirAccess.dir_exists_absolute(abs_dir):
			DirAccess.make_dir_recursive_absolute(abs_dir)

	static func _build_atom_gdscript(script_name: String, display_name: String, desc: String) -> String:
		var safe_desc := desc if not desc.is_empty() else display_name
		return (
			"@tool\n" +
			"extends GDEntityAtomSystem.AtomBase\n\n" +
			"## 原子作用：%s\n" % safe_desc.replace("\n", " ") +
			"## 实例配置写在本组件导出字段；通用元数据见 AtomTemplateRes。\n"
		)


static func _cmd_atom_create(ctx: CliContext) -> CliResult:
	var name_opt := ctx.get_option("name")
	var at := GDCoreTypes.AtomType.LOGIC
	match ctx.get_option("type", "Logic").to_lower():
		"visual":
			at = GDCoreTypes.AtomType.VISUAL
		"ui":
			at = GDCoreTypes.AtomType.UI

	var res := AtomCreator.create_atom({
		"script_name": name_opt,
		"display_name": ctx.get_option("display", name_opt),
		"description": ctx.get_option("desc"),
		"atom_type": at,
		"script_dir": ctx.get_option("script-dir"),
		"template_dir": ctx.get_option("template-dir", AtomCreator.DEFAULT_TEMP_DIR),
	})
	if not bool(res.get("ok", false)):
		return CliResult.fail(str(res.get("error_code", "FAIL")), str(res.get("error_message", "failed")))
	return CliResult.success({
		"scriptPath": res.get("script_path", ""),
		"assetPath": res.get("asset_path", ""),
	})

static func _cmd_atom_list_templates(_ctx: CliContext) -> CliResult:
	var items: Array = []
	for t in find_all_atom_templates():
		items.append({
			"displayName": t.display_name,
			"atomType": GDCoreTypes.atom_type_name(t.atom_type),
			"scriptTypeName": t.atom_script_type_name,
			"path": t.resource_path,
		})
	return CliResult.success({"count": items.size(), "templates": items})

static func find_all_atom_templates(root_dir: String = "res://") -> Array[GDEntityAtomSystem.AtomTemplateRes]:
	var out: Array[GDEntityAtomSystem.AtomTemplateRes] = []
	_scan_templates(root_dir, out)
	return out

static func _scan_templates(dir_path: String, out: Array[GDEntityAtomSystem.AtomTemplateRes]) -> void:
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
					_scan_templates(full, out)
			elif (fname.ends_with(".tres") or fname.ends_with(".res")) and fname.begins_with("AtomTemplate_"):
				var loaded := ResourceLoader.load(full)
				if loaded is GDEntityAtomSystem.AtomTemplateRes:
					out.append(loaded)
		fname = dir.get_next()
	dir.list_dir_end()
