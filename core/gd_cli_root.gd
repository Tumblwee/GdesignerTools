@tool
class_name GDCliRoot
extends RefCounted

## Core CLI 骨架与原子创建器命令（对应 CliRoot / CliContext / CliResult / AtomCreator / AtomCommands）

class CliContext extends RefCounted:
	var positionals: Array[String] = []
	var options: Dictionary = {} # String -> String
	var flags: Dictionary = {} # String -> bool

	func _init(p_pos: Array[String] = [], p_opts: Dictionary = {}, p_flags: Dictionary = {}) -> void:
		positionals = p_pos
		options = p_opts
		flags = p_flags

	func get_option(key: String, fallback: String = "") -> String:
		return str(options.get(key, fallback))

	func has_flag(key: String) -> bool:
		return flags.has(key)


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
		r.ok = false
		r.code = err_code
		r.message = err_msg
		r.data = payload
		return r

	func to_json_line() -> String:
		var out := {
			"ok": ok,
			"code": code,
			"message": message,
		}
		for k in data.keys():
			out[k] = data[k]
		return JSON.stringify(out)


static var _registry: Dictionary = {} # command_name -> {"callable": Callable, "summary": String}
static var _builtins_registered: bool = false

static func _ensure_builtins() -> void:
	if _builtins_registered:
		return
	_builtins_registered = true
	register_command(
		"atom.create",
		Callable(GDCliRoot, "_cmd_atom_create"),
		"创建 AtomBase 脚本与 AtomTemplateRes 模板资产 (--name --type --script-dir --template-dir)"
	)
	register_command(
		"atom.list-templates",
		Callable(GDCliRoot, "_cmd_atom_list_templates"),
		"列出工程内全部 AtomTemplateRes 模板"
	)

static func register_command(cmd_name: String, handler: Callable, summary: String = "") -> void:
	_registry[cmd_name] = {
		"callable": handler,
		"summary": summary,
	}

static func get_registered_commands() -> Dictionary:
	_ensure_builtins()
	return _registry

static func execute(argv: Array) -> CliResult:
	_ensure_builtins()
	if argv == null or argv.is_empty():
		return CliResult.fail("BAD_ARG", "empty argv")
	var cmd_name := str(argv[0])
	if not _registry.has(cmd_name):
		return CliResult.fail("NOT_FOUND", "command '%s' not registered" % cmd_name)
	var ctx := parse_args(argv, 1)
	var entry: Dictionary = _registry[cmd_name]
	var cb: Callable = entry["callable"]
	return cb.call(ctx)

static func execute_line(command_line: String) -> CliResult:
	var parts := split_command_line(command_line)
	return execute(parts)

static func parse_args(argv: Array, start_index: int = 1) -> CliContext:
	var pos: Array[String] = []
	var opts: Dictionary = {}
	var flgs: Dictionary = {}
	var i := start_index
	while i < argv.size():
		var a := str(argv[i])
		if a.begins_with("--"):
			var eq := a.find("=")
			if eq > 2:
				var key := a.substr(2, eq - 2)
				var val := a.substr(eq + 1)
				opts[key] = val
			else:
				var key := a.substr(2)
				if i + 1 < argv.size() and not str(argv[i + 1]).begins_with("-"):
					i += 1
					opts[key] = str(argv[i])
				else:
					flgs[key] = true
		else:
			pos.append(a)
		i += 1
	return CliContext.new(pos, opts, flgs)

static func split_command_line(input: String) -> Array[String]:
	var parts: Array[String] = []
	if input.strip_edges().is_empty():
		return parts
	var current := ""
	var in_quotes := false
	for i in range(input.length()):
		var ch := input[i]
		if ch == "\"":
			in_quotes = not in_quotes
			continue
		if not in_quotes and (ch == " " or ch == "\t"):
			if not current.is_empty():
				parts.append(current)
				current = ""
			continue
		current += ch
	if not current.is_empty():
		parts.append(current)
	return parts


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
		if s.is_empty():
			return false
		var c0 := s.unicode_at(0)
		var is_letter := (c0 >= 65 and c0 <= 90) or (c0 >= 97 and c0 <= 122) or c0 == 95
		if not is_letter:
			return false
		for i in range(1, s.length()):
			var c := s.unicode_at(i)
			var ok := (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
			if not ok:
				return false
		return true

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
	var type_str := ctx.get_option("type", "Logic")
	var script_dir := ctx.get_option("script-dir")
	var template_dir := ctx.get_option("template-dir", AtomCreator.DEFAULT_TEMP_DIR)
	var display := ctx.get_option("display", name_opt)
	var desc := ctx.get_option("desc", "")

	var at := GDCoreTypes.AtomType.LOGIC
	match type_str.to_lower():
		"visual":
			at = GDCoreTypes.AtomType.VISUAL
		"ui":
			at = GDCoreTypes.AtomType.UI
		_:
			at = GDCoreTypes.AtomType.LOGIC

	var res := AtomCreator.create_atom({
		"script_name": name_opt,
		"display_name": display,
		"description": desc,
		"atom_type": at,
		"script_dir": script_dir,
		"template_dir": template_dir,
	})
	if not bool(res.get("ok", false)):
		return CliResult.fail(str(res.get("error_code", "FAIL")), str(res.get("error_message", "failed")))
	return CliResult.success({
		"scriptPath": res.get("script_path", ""),
		"assetPath": res.get("asset_path", ""),
	})

static func _cmd_atom_list_templates(_ctx: CliContext) -> CliResult:
	var templates := find_all_atom_templates()
	var items: Array = []
	for t in templates:
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
			elif fname.ends_with(".tres") or fname.ends_with(".res"):
				if fname.begins_with("AtomTemplate_"):
					var loaded := ResourceLoader.load(full)
					if loaded is GDEntityAtomSystem.AtomTemplateRes:
						out.append(loaded)
		fname = dir.get_next()
	dir.list_dir_end()
