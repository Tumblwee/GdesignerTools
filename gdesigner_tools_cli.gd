@tool
class_name GdesignerToolsCli
extends RefCounted

## 统一 CLI 入口：合并 Core / 关卡 / 技能 / 引导各模块的命令表。
## 命令清单由各模块 commands() 推导，供控制台、help 与自动补全使用。

## 解析并执行一整行命令，返回 JSON 字符串。
static func run(command_line: String) -> String:
	var argv := GDCliRoot.split_command_line(command_line)
	if argv.is_empty():
		return JSON.stringify({"ok": false, "code": "BAD_ARG", "message": "empty command"})
	var table := _table()
	var command := argv[0] if table.has(argv[0]) else GDSceneEditorCli.resolve_alias(argv[0])
	return GDCliRoot.dispatch(table, command, argv.slice(1))

## 全部命令：[{"name", "summary"}]，按模块顺序。
static func commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table := _table()
	for command in table:
		out.append({"name": command, "summary": str(table[command]["summary"])})
	return out

static func _table() -> Dictionary:
	var table := {"help": {"run": _cmd_help, "summary": "列出全部命令"}}
	for module: Dictionary in [GDCliRoot.commands(), GDSceneEditorCli.commands(), GDSkillCli.commands(), GDGuideCli.commands()]:
		table.merge(module)
	return table

static func _cmd_help(ctx: GDCliRoot.CliContext) -> String:
	return ctx.ok({"commands": commands()})
